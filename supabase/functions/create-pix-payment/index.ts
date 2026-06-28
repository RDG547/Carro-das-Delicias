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
  normalizeAbacateStatus,
  parsePositiveAmountInCents,
  readJson,
  requireAuthenticatedUser,
  requiredEnv,
  stringValue,
  updatePaymentPending,
  updatePaymentState,
} from "../_shared/payments.ts";

const ABACATE_BASE_URL = "https://api.abacatepay.com/v2";

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
      return await checkPixStatus(req, body);
    }

    const user = await requireAuthenticatedUser(req);
    const admin = createAdminClient();
    const order = await fetchOrderForUser(admin, user, body.pedido_id);

    if (stringValue(order.metodo_pagamento)?.toLowerCase() !== "pix") {
      throw new HttpError(400, "Pedido nao usa pagamento PIX.");
    }

    const amount = parsePositiveAmountInCents(order.total);
    const orderId = Number(order.id);
    const description = stringValue(body.description) ??
      `Pedido #${orderId} - Carro das Delicias`;

    const data: Record<string, unknown> = {
      amount,
      expiresIn: 3600,
      description,
      metadata: {
        pedidoId: String(orderId),
        userId: user.id,
      },
    };

    const pixData = await abacateRequest("/transparents/create", {
      method: "PIX",
      data,
    });

    const result = {
      success: true,
      id: pixData.id,
      qr_code_url: pixData.brCodeBase64,
      pix_code: pixData.brCode,
      expires_at: pixData.expiresAt,
      status: pixData.status,
      receipt_url: pixData.receiptUrl,
      raw: pixData,
    };

    await updatePaymentPending(admin, orderId, {
      payment_provider: "abacatepay",
      payment_reference: stringValue(pixData.id),
      payment_payload: {
        qr_code_url: result.qr_code_url,
        pix_code: result.pix_code,
        expires_at: result.expires_at,
        raw: pixData,
      },
      payment_expires_at: result.expires_at,
      extra_updates: {
        pix_id: stringValue(pixData.id) ?? null,
        pix_qr_code: result.pix_code ?? null,
      },
    });

    return jsonResponse(result);
  } catch (error) {
    return errorResponse(error);
  }
});

async function checkPixStatus(
  req: Request,
  body: Record<string, unknown>,
): Promise<Response> {
  const user = await requireAuthenticatedUser(req);
  const admin = createAdminClient();
  const chargeId = stringValue(body.charge_id ?? body.payment_reference);
  if (!chargeId) {
    throw new HttpError(400, "charge_id obrigatorio.");
  }

  const order = await fetchOrderByReferenceForUser(
    admin,
    user,
    chargeId,
    "abacatepay",
  );
  const pixData = await abacateGet("/transparents/check", { id: chargeId });
  const status = normalizeAbacateStatus(pixData.status);

  if (status === "PAID" || status === "CONFIRMED") {
    await markOrderPaid(admin, order.id, {
      payment_payload: {
        ...(order.payment_payload as Record<string, unknown> | undefined ??
          {}),
        raw_status: pixData,
      },
    });
  } else if (status === "EXPIRED") {
    await updatePaymentState(admin, order.id, "expired");
  } else if (status === "CANCELLED" || status === "CANCELED") {
    await updatePaymentState(admin, order.id, "cancelled");
  }

  return jsonResponse({
    status,
    paid_at: pixData.paidAt,
    expires_at: pixData.expiresAt,
  });
}

async function abacateRequest(
  path: string,
  body: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const response = await fetch(`${ABACATE_BASE_URL}${path}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${requiredEnv("ABACATEPAY_API_KEY")}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  return await parseAbacateResponse(response);
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

  return await parseAbacateResponse(response);
}

async function parseAbacateResponse(
  response: Response,
): Promise<Record<string, unknown>> {
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

  if (
    response.status < 200 ||
    response.status >= 300 ||
    !payload ||
    payload.success === false
  ) {
    throw new HttpError(
      502,
      "AbacatePay recusou a operacao.",
      payload ?? rawBody,
    );
  }

  const data = payload.data;
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new HttpError(502, "Resposta inesperada da AbacatePay.", payload);
  }

  return data as Record<string, unknown>;
}
