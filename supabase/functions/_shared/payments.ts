import {
  createClient,
  type SupabaseClient,
  type User,
} from "npm:@supabase/supabase-js@2";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, stripe-signature, x-webhook-signature, x-abacatepay-signature",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

export type OrderRecord = Record<string, unknown> & {
  id: number;
  user_id?: string | null;
  total: number | string;
  metodo_pagamento?: string | null;
  cliente_nome?: string | null;
  cliente_telefone?: string | null;
  payment_reference?: string | null;
};

export class HttpError extends Error {
  status: number;
  details?: unknown;

  constructor(status: number, message: string, details?: unknown) {
    super(message);
    this.status = status;
    this.details = details;
  }
}

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

export function errorResponse(error: unknown): Response {
  if (error instanceof HttpError) {
    return jsonResponse(
      {
        success: false,
        message: error.message,
        details: error.details,
      },
      error.status,
    );
  }

  console.error(error);
  return jsonResponse(
    { success: false, message: "Erro interno ao processar pagamento." },
    500,
  );
}

export async function readJson(req: Request): Promise<Record<string, unknown>> {
  try {
    const body = await req.json();
    if (body && typeof body === "object" && !Array.isArray(body)) {
      return body as Record<string, unknown>;
    }
  } catch (_) {
    // Handled below.
  }

  throw new HttpError(400, "JSON invalido.");
}

export function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new HttpError(500, `${name} nao configurada.`);
  }
  return value;
}

export function createAdminClient(): SupabaseClient {
  return createClient(
    requiredEnv("SUPABASE_URL"),
    requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
    {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
    },
  );
}

export async function requireAuthenticatedUser(req: Request): Promise<User> {
  const authorization = req.headers.get("Authorization");
  if (!authorization) {
    throw new HttpError(401, "Usuario nao autenticado.");
  }

  const client = createClient(
    requiredEnv("SUPABASE_URL"),
    requiredEnv("SUPABASE_ANON_KEY"),
    {
      global: { headers: { Authorization: authorization } },
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
    },
  );

  const { data, error } = await client.auth.getUser();
  if (error || !data.user) {
    throw new HttpError(401, "Sessao invalida ou expirada.", error);
  }

  return data.user;
}

export async function userCanAccessOrder(
  admin: SupabaseClient,
  userId: string,
  order: OrderRecord,
): Promise<boolean> {
  if (order.user_id === userId) return true;

  const { data, error } = await admin
    .from("profiles")
    .select("role")
    .eq("id", userId)
    .maybeSingle();

  if (error) {
    throw new HttpError(500, "Erro ao validar permissao do usuario.", error);
  }

  return data?.role === "admin";
}

export async function fetchOrderForUser(
  admin: SupabaseClient,
  user: User,
  orderId: unknown,
): Promise<OrderRecord> {
  const parsedOrderId = parseOrderId(orderId);

  const { data, error } = await admin
    .from("pedidos")
    .select("*")
    .eq("id", parsedOrderId)
    .maybeSingle();

  if (error) {
    throw new HttpError(500, "Erro ao buscar pedido.", error);
  }
  if (!data) {
    throw new HttpError(404, "Pedido nao encontrado.");
  }

  const order = data as OrderRecord;
  if (!(await userCanAccessOrder(admin, user.id, order))) {
    throw new HttpError(403, "Voce nao tem permissao para este pedido.");
  }

  return order;
}

export async function fetchOrderByReferenceForUser(
  admin: SupabaseClient,
  user: User,
  reference: string,
  provider: string,
): Promise<OrderRecord> {
  const { data, error } = await admin
    .from("pedidos")
    .select("*")
    .eq("payment_reference", reference)
    .eq("payment_provider", provider)
    .maybeSingle();

  if (error) {
    throw new HttpError(500, "Erro ao buscar pedido.", error);
  }
  if (!data) {
    throw new HttpError(404, "Pedido nao encontrado para este pagamento.");
  }

  const order = data as OrderRecord;
  if (!(await userCanAccessOrder(admin, user.id, order))) {
    throw new HttpError(403, "Voce nao tem permissao para este pedido.");
  }

  return order;
}

export function parseOrderId(value: unknown): number {
  const parsed = typeof value === "number" ? value : Number(String(value ?? ""));
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new HttpError(400, "pedido_id invalido.");
  }
  return parsed;
}

export function parsePositiveAmountInCents(value: unknown): number {
  const total = Number(value);
  if (!Number.isFinite(total) || total <= 0) {
    throw new HttpError(400, "Total do pedido invalido.");
  }
  return Math.round(total * 100);
}

export function stringValue(value: unknown): string | undefined {
  if (value === null || value === undefined) return undefined;
  const text = String(value).trim();
  return text.length > 0 ? text : undefined;
}

export function digitsOnly(value: unknown): string | undefined {
  const text = stringValue(value)?.replace(/\D/g, "");
  return text && text.length > 0 ? text : undefined;
}

export async function updatePaymentPending(
  admin: SupabaseClient,
  orderId: number,
  payload: Record<string, unknown>,
): Promise<void> {
  const extraUpdates =
    payload.extra_updates &&
      typeof payload.extra_updates === "object" &&
      !Array.isArray(payload.extra_updates)
      ? payload.extra_updates as Record<string, unknown>
      : {};

  const { error } = await admin
    .from("pedidos")
    .update({
      status: "pagamento_pendente",
      payment_status: payload.payment_status ?? "pending",
      payment_provider: payload.payment_provider,
      payment_reference: payload.payment_reference,
      payment_url: payload.payment_url ?? null,
      payment_payload: payload.payment_payload ?? {},
      payment_expires_at: payload.payment_expires_at ?? null,
      payment_confirmed_at: null,
      updated_at: new Date().toISOString(),
      ...extraUpdates,
    })
    .eq("id", orderId);

  if (error) {
    throw new HttpError(500, "Erro ao salvar pagamento pendente.", error);
  }
}

export async function markOrderPaid(
  admin: SupabaseClient,
  orderId: number,
  extraUpdates: Record<string, unknown> = {},
): Promise<void> {
  const { data: currentOrder, error: currentOrderError } = await admin
    .from("pedidos")
    .select("id, cliente_nome, total, status, payment_status")
    .eq("id", orderId)
    .maybeSingle();

  if (currentOrderError) {
    throw new HttpError(
      500,
      "Erro ao buscar pedido antes de confirmar pagamento.",
      currentOrderError,
    );
  }

  const wasAlreadyPaid =
    currentOrder?.status === "pago" || currentOrder?.payment_status === "paid";

  const { error } = await admin
    .from("pedidos")
    .update({
      status: "pago",
      payment_status: "paid",
      payment_confirmed_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      ...extraUpdates,
    })
    .eq("id", orderId);

  if (error) {
    throw new HttpError(500, "Erro ao confirmar pagamento.", error);
  }

  if (!wasAlreadyPaid && currentOrder) {
    await notifyAdminsNewOrder(admin, currentOrder);
  }
}

async function notifyAdminsNewOrder(
  admin: SupabaseClient,
  order: Record<string, unknown>,
): Promise<void> {
  const { data: admins, error: adminsError } = await admin
    .from("profiles")
    .select("id")
    .eq("role", "admin");

  if (adminsError) {
    console.warn("Nao foi possivel buscar admins para notificar", adminsError);
    return;
  }

  if (!admins || admins.length === 0) return;

  const orderId = Number(order.id);
  const customerName = stringValue(order.cliente_nome) ?? "Cliente";
  const total = Number(order.total ?? 0);
  const title = "🔔 Novo Pedido!";
  const message =
    `Pedido #${String(orderId).padStart(4, "0")} de ${customerName} - R$ ${
      total.toFixed(2)
    }`;

  const notifications = admins.map((adminProfile) => ({
    user_id: adminProfile.id,
    title,
    message,
    type: "order",
    data: {
      order_id: orderId,
      customer_name: customerName,
      total,
    },
  }));

  const { error } = await admin.from("notifications").insert(notifications);
  if (error) {
    console.warn("Nao foi possivel notificar admins sobre novo pedido", error);
  }
}

export async function updatePaymentState(
  admin: SupabaseClient,
  orderId: number,
  paymentStatus: string,
  extraUpdates: Record<string, unknown> = {},
): Promise<void> {
  const status = paymentStatus === "cancelled"
    ? "cancelado"
    : "pagamento_pendente";

  const { error } = await admin
    .from("pedidos")
    .update({
      status,
      payment_status: paymentStatus,
      updated_at: new Date().toISOString(),
      ...extraUpdates,
    })
    .eq("id", orderId);

  if (error) {
    throw new HttpError(500, "Erro ao atualizar status do pagamento.", error);
  }
}

export async function updatePaymentStatusOnly(
  admin: SupabaseClient,
  orderId: number,
  paymentStatus: string,
  extraUpdates: Record<string, unknown> = {},
): Promise<void> {
  const { error } = await admin
    .from("pedidos")
    .update({
      payment_status: paymentStatus,
      updated_at: new Date().toISOString(),
      ...extraUpdates,
    })
    .eq("id", orderId);

  if (error) {
    throw new HttpError(500, "Erro ao registrar evento de pagamento.", error);
  }
}

export function appendPaymentEvent(
  currentPayload: unknown,
  key: string,
  event: unknown,
): Record<string, unknown> {
  const payload = currentPayload &&
      typeof currentPayload === "object" &&
      !Array.isArray(currentPayload)
    ? { ...(currentPayload as Record<string, unknown>) }
    : {};

  const history = Array.isArray(payload.webhook_events)
    ? payload.webhook_events.slice(-9)
    : [];
  history.push({
    key,
    received_at: new Date().toISOString(),
    event,
  });

  payload.webhook_events = history;
  payload.last_webhook_event = event;
  return payload;
}

export function normalizeAbacateStatus(status: unknown): string {
  return stringValue(status)?.toUpperCase() ?? "PENDING";
}

export function normalizeStripePaymentStatus(status: unknown): string {
  return stringValue(status)?.toLowerCase() ?? "error";
}
