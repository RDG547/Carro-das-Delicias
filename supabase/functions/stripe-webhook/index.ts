import "@supabase/functions-js/edge-runtime.d.ts";
import {
  appendPaymentEvent,
  corsHeaders,
  createAdminClient,
  errorResponse,
  HttpError,
  jsonResponse,
  markOrderPaid,
  normalizeStripePaymentStatus,
  requiredEnv,
  stringValue,
  updatePaymentState,
  updatePaymentStatusOnly,
} from "../_shared/payments.ts";

type StripeObject = Record<string, unknown>;

const STRIPE_SUCCESS_EVENTS = new Set([
  "checkout.session.completed",
  "checkout.session.async_payment_succeeded",
  "payment_intent.succeeded",
  "charge.succeeded",
  "charge.captured",
]);

const STRIPE_FAILURE_EVENTS = new Set([
  "checkout.session.async_payment_failed",
  "payment_intent.payment_failed",
  "charge.failed",
]);

const STRIPE_CANCELLED_EVENTS = new Set([
  "payment_intent.canceled",
]);

const STRIPE_EXPIRED_EVENTS = new Set([
  "checkout.session.expired",
  "charge.expired",
]);

const STRIPE_PENDING_EVENTS = new Set([
  "charge.pending",
  "payment_intent.processing",
  "payment_intent.requires_action",
]);

const STRIPE_REFUND_EVENTS = new Set([
  "charge.refunded",
  "charge.refund.updated",
  "refund.created",
  "refund.updated",
]);

const STRIPE_DISPUTE_EVENTS = new Set([
  "charge.dispute.created",
  "charge.dispute.updated",
  "charge.dispute.closed",
  "charge.dispute.funds_reinstated",
  "charge.dispute.funds_withdrawn",
]);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      throw new HttpError(405, "Metodo nao permitido.");
    }

    const rawBody = await req.text();
    await verifyStripeSignature(rawBody, req.headers);

    const event = JSON.parse(rawBody) as Record<string, unknown>;
    const eventType = stringValue(event.type);
    const data = event.data as Record<string, unknown> | undefined;
    const object = data?.object as StripeObject | undefined;

    if (!eventType || !object) {
      return jsonResponse({ received: true, ignored: true });
    }

    const admin = createAdminClient();
    const order = await findOrderForStripeObject(admin, object);
    if (!order) {
      return jsonResponse({ received: true, ignored: true });
    }

    const orderId = Number(order.id);
    const currentPayload = order.payment_payload;
    const nextPayload = appendPaymentEvent(currentPayload, eventType, event);
    const reference = stripeReferenceForObject(object) ??
      stringValue(order.payment_reference);
    const extra = {
      payment_provider: "stripe",
      payment_reference: reference ?? null,
      stripe_session_id: stringValue(order.stripe_session_id) ??
        sessionIdForObject(object) ??
        null,
      payment_payload: nextPayload,
    };

    if (STRIPE_SUCCESS_EVENTS.has(eventType)) {
      if (isStripeObjectPaid(object, eventType)) {
        await markOrderPaid(admin, orderId, extra);
      } else {
        await updatePaymentStatusOnly(admin, orderId, "unpaid", extra);
      }
    } else if (STRIPE_FAILURE_EVENTS.has(eventType)) {
      await updatePaymentState(admin, orderId, "failed", extra);
    } else if (STRIPE_CANCELLED_EVENTS.has(eventType)) {
      await updatePaymentState(admin, orderId, "cancelled", extra);
    } else if (STRIPE_EXPIRED_EVENTS.has(eventType)) {
      await updatePaymentState(admin, orderId, "expired", extra);
    } else if (STRIPE_PENDING_EVENTS.has(eventType)) {
      await updatePaymentState(admin, orderId, "pending", extra);
    } else if (STRIPE_REFUND_EVENTS.has(eventType)) {
      await updatePaymentStatusOnly(admin, orderId, "refunded", extra);
    } else if (STRIPE_DISPUTE_EVENTS.has(eventType)) {
      await updatePaymentStatusOnly(admin, orderId, "disputed", extra);
    } else {
      await updatePaymentStatusOnly(
        admin,
        orderId,
        stringValue(order.payment_status) ?? "pending",
        extra,
      );
    }

    return jsonResponse({ received: true });
  } catch (error) {
    return errorResponse(error);
  }
});

async function findOrderForStripeObject(
  admin: ReturnType<typeof createAdminClient>,
  object: StripeObject,
): Promise<Record<string, unknown> | null> {
  const pedidoId = extractPedidoId(object);
  if (pedidoId) {
    const { data, error } = await admin
      .from("pedidos")
      .select("*")
      .eq("id", Number(pedidoId))
      .maybeSingle();

    if (error) {
      throw new HttpError(500, "Erro ao buscar pedido Stripe.", error);
    }
    if (data) return data;
  }

  const sessionId = sessionIdForObject(object);
  if (sessionId) {
    const { data, error } = await admin
      .from("pedidos")
      .select("*")
      .or(
        `payment_reference.eq.${sessionId},stripe_session_id.eq.${sessionId}`,
      )
      .maybeSingle();

    if (error) {
      throw new HttpError(500, "Erro ao buscar sessao Stripe.", error);
    }
    if (data) return data;
  }

  const paymentIntent = stringValue(object.payment_intent) ??
    stringValue(object.id);
  if (paymentIntent) {
    const { data, error } = await admin
      .from("pedidos")
      .select("*")
      .eq("payment_provider", "stripe")
      .filter("payment_payload", "cs", JSON.stringify({ payment_intent: paymentIntent }))
      .maybeSingle();

    if (error) {
      console.warn("Nao foi possivel buscar pedido por payment_intent", error);
    }
    if (data) return data;
  }

  return null;
}

function extractPedidoId(object: StripeObject): string | undefined {
  const metadata = object.metadata as Record<string, unknown> | undefined;
  const chargeMetadata =
    (object.charge as Record<string, unknown> | undefined)?.metadata as
      | Record<string, unknown>
      | undefined;

  return stringValue(metadata?.pedido_id) ??
    stringValue(metadata?.pedidoId) ??
    stringValue(chargeMetadata?.pedido_id) ??
    stringValue(chargeMetadata?.pedidoId) ??
    stringValue(object.client_reference_id);
}

function stripeReferenceForObject(object: StripeObject): string | undefined {
  return sessionIdForObject(object) ??
    stringValue(object.payment_intent) ??
    stringValue(object.charge) ??
    stringValue(object.id);
}

function sessionIdForObject(object: StripeObject): string | undefined {
  const id = stringValue(object.id);
  if (id?.startsWith("cs_")) return id;
  const session = stringValue(object.checkout_session);
  if (session?.startsWith("cs_")) return session;
  return undefined;
}

function isStripeObjectPaid(object: StripeObject, eventType: string): boolean {
  if (eventType.startsWith("charge.")) {
    return object.paid === true || stringValue(object.status) === "succeeded";
  }

  const paymentStatus = normalizeStripePaymentStatus(object.payment_status);
  const status = normalizeStripePaymentStatus(object.status);
  return paymentStatus === "paid" ||
    paymentStatus === "no_payment_required" ||
    status === "succeeded";
}

async function verifyStripeSignature(
  payload: string,
  headers: Headers,
): Promise<void> {
  const secret = requiredEnv("STRIPE_WEBHOOK_SECRET");
  const signatureHeader = headers.get("stripe-signature");
  if (!signatureHeader) {
    throw new HttpError(401, "Assinatura Stripe ausente.");
  }

  const signatures = signatureHeader.split(",").reduce(
    (acc, part) => {
      const [key, value] = part.split("=");
      if (key === "t" && value) acc.timestamp = value;
      if (key === "v1" && value) acc.signatures.push(value);
      return acc;
    },
    { timestamp: "", signatures: [] as string[] },
  );

  if (!signatures.timestamp || signatures.signatures.length === 0) {
    throw new HttpError(401, "Assinatura Stripe invalida.");
  }

  const signedPayload = `${signatures.timestamp}.${payload}`;
  const expected = await hmacSha256Hex(secret, signedPayload);
  const valid = signatures.signatures.some((signature) =>
    timingSafeEqual(expected, signature)
  );

  if (!valid) {
    throw new HttpError(401, "Assinatura Stripe nao confere.");
  }
}

async function hmacSha256Hex(secret: string, payload: string): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = await crypto.subtle.sign("HMAC", key, encoder.encode(payload));
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function timingSafeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let result = 0;
  for (let i = 0; i < left.length; i++) {
    result |= left.charCodeAt(i) ^ right.charCodeAt(i);
  }
  return result === 0;
}
