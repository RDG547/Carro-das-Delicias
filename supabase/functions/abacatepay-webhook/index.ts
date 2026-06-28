import "@supabase/functions-js/edge-runtime.d.ts";
import {
  appendPaymentEvent,
  corsHeaders,
  createAdminClient,
  errorResponse,
  HttpError,
  jsonResponse,
  markOrderPaid,
  normalizeAbacateStatus,
  readJson,
  requiredEnv,
  stringValue,
  updatePaymentState,
  updatePaymentStatusOnly,
} from "../_shared/payments.ts";

const ABACATE_BASE_URL = "https://api.abacatepay.com/v2";

const ABACATE_PAID_EVENTS = new Set([
  "checkout.completed",
  "transparent.completed",
]);

const ABACATE_REFUND_EVENTS = new Set([
  "checkout.refunded",
  "transparent.refunded",
]);

const ABACATE_DISPUTE_EVENTS = new Set([
  "checkout.disputed",
  "transparent.disputed",
]);

const ABACATE_LOST_EVENTS = new Set([
  "checkout.lost",
  "transparent.lost",
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
    await verifyAbacateSignature(rawBody, req.headers);

    const parsed = parseJsonBody(rawBody);
    const eventType = normalizeEventType(parsed);
    const chargeId = findFirstString(parsed, [
      "id",
      "chargeId",
      "pixId",
      "paymentId",
      "transparentId",
      "checkoutId",
    ]);
    const pedidoId = findNestedPedidoId(parsed);

    if (!chargeId && !pedidoId) {
      return jsonResponse({ received: true, ignored: true });
    }

    const shouldCheckTransparent = eventType?.startsWith("transparent.") &&
      chargeId;
    const pixData = shouldCheckTransparent
      ? await abacateGet("/transparents/check", { id: chargeId })
      : undefined;
    const status = normalizeAbacateStatus(
      pixData?.status ?? findFirstString(parsed, ["status", "state"]),
    );
    const admin = createAdminClient();
    const order = await findOrder(admin, chargeId, pedidoId);

    if (!order) {
      return jsonResponse({ received: true, ignored: true });
    }

    const orderId = Number(order.id);
    const nextPayload = appendPaymentEvent(
      order.payment_payload,
      eventType ?? "abacatepay.webhook",
      parsed,
    );
    const extra = {
      payment_provider: "abacatepay",
      payment_reference: chargeId ?? order.payment_reference ?? null,
      payment_payload: {
        ...nextPayload,
        raw_status: pixData ?? nextPayload.raw_status,
      },
    };

    if (
      (eventType && ABACATE_PAID_EVENTS.has(eventType)) ||
      status === "PAID" ||
      status === "CONFIRMED"
    ) {
      await markOrderPaid(admin, orderId, extra);
    } else if (eventType && ABACATE_REFUND_EVENTS.has(eventType)) {
      await updatePaymentStatusOnly(admin, orderId, "refunded", extra);
    } else if (eventType && ABACATE_DISPUTE_EVENTS.has(eventType)) {
      await updatePaymentStatusOnly(admin, orderId, "disputed", extra);
    } else if (eventType && ABACATE_LOST_EVENTS.has(eventType)) {
      await updatePaymentStatusOnly(admin, orderId, "lost", extra);
    } else if (status === "EXPIRED") {
      await updatePaymentState(admin, orderId, "expired", extra);
    } else if (status === "CANCELLED" || status === "CANCELED") {
      await updatePaymentState(admin, orderId, "cancelled", extra);
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

async function verifyAbacateSignature(
  rawBody: string,
  headers: Headers,
): Promise<void> {
  const secret = Deno.env.get("ABACATEPAY_WEBHOOK_SECRET");
  if (!secret) return;

  const signatureHeader = headers.get("x-webhook-signature") ??
    headers.get("x-abacatepay-signature") ??
    headers.get("signature");
  if (!signatureHeader) {
    throw new HttpError(401, "Assinatura AbacatePay ausente.");
  }

  const signature = signatureHeader.includes("=")
    ? signatureHeader.split("=").pop()?.trim()
    : signatureHeader.trim();
  if (!signature) {
    throw new HttpError(401, "Assinatura AbacatePay invalida.");
  }

  const expected = await hmacSha256Hex(secret, rawBody);
  if (!timingSafeEqual(expected, signature)) {
    throw new HttpError(401, "Assinatura AbacatePay nao confere.");
  }
}

async function abacateGet(
  path: string,
  query: Record<string, string>,
): Promise<Record<string, unknown>> {
  const url = new URL(`${ABACATE_BASE_URL}${path}`);
  for (const [key, value] of Object.entries(query)) {
    url.searchParams.set(key, value);
  }

  const response = await fetch(url, {
    headers: {
      Authorization: `Bearer ${requiredEnv("ABACATEPAY_API_KEY")}`,
    },
  });

  const rawBody = await response.text();
  const payload = parseJsonBody(rawBody);
  if (
    response.status < 200 ||
    response.status >= 300 ||
    payload.success === false
  ) {
    throw new HttpError(502, "AbacatePay recusou a consulta.", payload);
  }

  const data = payload.data;
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new HttpError(502, "Resposta inesperada da AbacatePay.", payload);
  }

  return data as Record<string, unknown>;
}

async function findOrder(
  admin: ReturnType<typeof createAdminClient>,
  chargeId: string | undefined,
  pedidoId: string | undefined,
): Promise<Record<string, unknown> | null> {
  if (pedidoId && Number.isFinite(Number(pedidoId))) {
    const { data, error } = await admin
      .from("pedidos")
      .select("*")
      .eq("id", Number(pedidoId))
      .maybeSingle();

    if (error) {
      throw new HttpError(500, "Erro ao buscar pedido AbacatePay.", error);
    }
    if (data) return data;
  }

  if (chargeId) {
    const { data, error } = await admin
      .from("pedidos")
      .select("*")
      .or(`payment_reference.eq.${chargeId},pix_id.eq.${chargeId}`)
      .maybeSingle();

    if (error) {
      throw new HttpError(500, "Erro ao buscar pagamento AbacatePay.", error);
    }
    if (data) return data;
  }

  return null;
}

function parseJsonBody(rawBody: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(rawBody);
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      return parsed as Record<string, unknown>;
    }
  } catch (_) {
    // Handled below.
  }

  throw new HttpError(400, "JSON invalido.");
}

function normalizeEventType(value: unknown): string | undefined {
  return findFirstString(value, [
    "event",
    "eventType",
    "type",
    "name",
  ])?.toLowerCase();
}

function findFirstString(
  value: unknown,
  keys: string[],
): string | undefined {
  if (!value || typeof value !== "object") return undefined;
  const record = value as Record<string, unknown>;

  for (const key of keys) {
    const direct = stringValue(record[key]);
    if (direct) return direct;
  }

  for (const child of Object.values(record)) {
    const nested = findFirstString(child, keys);
    if (nested) return nested;
  }

  return undefined;
}

function findNestedPedidoId(value: unknown): string | undefined {
  if (!value || typeof value !== "object") return undefined;
  const record = value as Record<string, unknown>;
  const metadata = record.metadata as Record<string, unknown> | undefined;

  return stringValue(metadata?.pedidoId) ??
    stringValue(metadata?.pedido_id) ??
    stringValue(record.pedidoId) ??
    stringValue(record.pedido_id) ??
    stringValue(record.externalId) ??
    stringValue(record.external_id);
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
