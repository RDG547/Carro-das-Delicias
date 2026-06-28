import "@supabase/functions-js/edge-runtime.d.ts";
import {
  corsHeaders,
  createAdminClient,
  errorResponse,
  fetchOrderByReferenceForUser,
  fetchOrderForUser,
  HttpError,
  jsonResponse,
  markOrderPaid,
  normalizeStripePaymentStatus,
  parsePositiveAmountInCents,
  readJson,
  requireAuthenticatedUser,
  requiredEnv,
  stringValue,
  updatePaymentPending,
  updatePaymentState,
} from "../_shared/payments.ts";

const STRIPE_BASE_URL = "https://api.stripe.com/v1";
const SUCCESS_URL = "https://carrodasdelicias.com/success";
const CANCEL_URL = "https://carrodasdelicias.com/cancel";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      throw new HttpError(405, "Metodo nao permitido.");
    }

    const body = await readJson(req);
    const action = stringValue(body.action);

    if (action === "check_status") {
      return await checkCheckoutStatus(req, body);
    }

    const user = await requireAuthenticatedUser(req);
    const admin = createAdminClient();
    const order = await fetchOrderForUser(admin, user, body.pedido_id);

    if (stringValue(order.metodo_pagamento)?.toLowerCase() !== "credito") {
      throw new HttpError(400, "Pedido nao usa pagamento com cartao.");
    }

    const orderId = Number(order.id);
    const amount = parsePositiveAmountInCents(order.total);
    if (amount < 50) {
      throw new HttpError(400, "Valor minimo para cartao e R$ 0,50.");
    }

    const description = stringValue(body.description) ??
      `Pedido #${orderId} - Carro das Delicias`;
    const customerEmail = stringValue(body.customer_email) ??
      stringValue(user.email);

    const params = new URLSearchParams();
    params.set("payment_method_types[0]", "card");
    params.set("line_items[0][price_data][currency]", "brl");
    params.set(
      "line_items[0][price_data][product_data][name]",
      description,
    );
    params.set("line_items[0][price_data][unit_amount]", String(amount));
    params.set("line_items[0][quantity]", "1");
    params.set("mode", "payment");
    params.set("success_url", SUCCESS_URL);
    params.set("cancel_url", CANCEL_URL);
    params.set("metadata[pedido_id]", String(orderId));
    params.set("metadata[user_id]", user.id);
    params.set("client_reference_id", String(orderId));
    params.set("payment_intent_data[metadata][pedido_id]", String(orderId));
    params.set("payment_intent_data[metadata][user_id]", user.id);
    if (customerEmail) {
      params.set("customer_email", customerEmail);
    }

    const session = await stripeRequest(
      "/checkout/sessions",
      "POST",
      params,
    );

    const sessionId = stringValue(session.id);
    const checkoutUrl = stringValue(session.url);
    if (!sessionId || !checkoutUrl) {
      throw new HttpError(502, "Stripe nao retornou checkout valido.", session);
    }

    await updatePaymentPending(admin, orderId, {
      payment_provider: "stripe",
      payment_reference: sessionId,
      payment_url: checkoutUrl,
      payment_status: normalizeStripePaymentStatus(session.payment_status) ===
          "paid"
        ? "paid"
        : "unpaid",
      payment_payload: {
        session_id: sessionId,
        checkout_url: checkoutUrl,
        raw: session,
      },
      extra_updates: {
        stripe_session_id: sessionId,
      },
    });

    return jsonResponse({
      success: true,
      session_id: sessionId,
      url: checkoutUrl,
    });
  } catch (error) {
    return errorResponse(error);
  }
});

async function checkCheckoutStatus(
  req: Request,
  body: Record<string, unknown>,
): Promise<Response> {
  const user = await requireAuthenticatedUser(req);
  const admin = createAdminClient();
  const sessionId = stringValue(body.session_id ?? body.payment_reference);
  if (!sessionId) {
    throw new HttpError(400, "session_id obrigatorio.");
  }

  const order = await fetchOrderByReferenceForUser(
    admin,
    user,
    sessionId,
    "stripe",
  );
  const session = await stripeRequest(
    `/checkout/sessions/${encodeURIComponent(sessionId)}`,
    "GET",
  );
  const paymentStatus = normalizeStripePaymentStatus(session.payment_status);
  const sessionStatus = normalizeStripePaymentStatus(session.status);

  if (paymentStatus === "paid") {
    await markOrderPaid(admin, order.id, {
      payment_payload: {
        ...(order.payment_payload as Record<string, unknown> | undefined ??
          {}),
        raw_status: session,
      },
    });
  } else if (sessionStatus === "expired") {
    await updatePaymentState(admin, order.id, "expired");
  } else if (paymentStatus === "unpaid") {
    await updatePaymentState(admin, order.id, "unpaid", {
      payment_url: stringValue(session.url) ?? order.payment_url ?? null,
    });
  }

  return jsonResponse({
    status: paymentStatus,
    payment_intent: session.payment_intent,
  });
}

async function stripeRequest(
  path: string,
  method: "GET" | "POST",
  body?: URLSearchParams,
): Promise<Record<string, unknown>> {
  const response = await fetch(`${STRIPE_BASE_URL}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${requiredEnv("STRIPE_SECRET_KEY")}`,
      ...(body ? { "Content-Type": "application/x-www-form-urlencoded" } : {}),
    },
    body,
  });

  const rawBody = await response.text();
  let payload: Record<string, unknown> | null = null;
  try {
    const decoded = JSON.parse(rawBody);
    if (decoded && typeof decoded === "object" && !Array.isArray(decoded)) {
      payload = decoded as Record<string, unknown>;
    }
  } catch (_) {
    // Handled below.
  }

  if (response.status < 200 || response.status >= 300 || !payload) {
    throw new HttpError(
      502,
      "Stripe recusou a operacao.",
      payload ?? rawBody,
    );
  }

  return payload;
}
