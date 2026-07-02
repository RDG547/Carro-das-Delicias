import "@supabase/functions-js/edge-runtime.d.ts";
import {
  createAdminClient,
  errorResponse,
  HttpError,
  jsonResponse,
} from "../_shared/payments.ts";
import {
  sendPushForNotification,
  type NotificationRecord,
} from "../_shared/fcm.ts";

type WebhookPayload = {
  record?: Record<string, unknown>;
  notification_id?: number | string;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "content-type, x-push-webhook-secret",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
      },
    });
  }

  try {
    if (req.method !== "POST") {
      throw new HttpError(405, "Metodo nao permitido.");
    }

    verifyWebhookSecret(req);

    const body = await readBody(req);
    const admin = createAdminClient();
    const notification = await resolveNotification(admin, body);
    const result = await sendPushForNotification(admin, notification);

    return jsonResponse({ success: true, result });
  } catch (error) {
    return errorResponse(error);
  }
});

function verifyWebhookSecret(req: Request): void {
  const expectedSecret = Deno.env.get("PUSH_WEBHOOK_SECRET");
  if (!expectedSecret) {
    throw new HttpError(500, "PUSH_WEBHOOK_SECRET nao configurado.");
  }

  const providedSecret = req.headers.get("x-push-webhook-secret");
  if (providedSecret !== expectedSecret) {
    throw new HttpError(401, "Assinatura de push invalida.");
  }
}

async function readBody(req: Request): Promise<WebhookPayload> {
  try {
    const body = await req.json();
    if (body && typeof body === "object" && !Array.isArray(body)) {
      return body as WebhookPayload;
    }
  } catch (_) {
    // Handled below.
  }

  throw new HttpError(400, "Payload invalido.");
}

async function resolveNotification(
  admin: ReturnType<typeof createAdminClient>,
  body: WebhookPayload,
): Promise<NotificationRecord> {
  if (body.record && typeof body.record === "object") {
    return body.record as NotificationRecord;
  }

  if (!body.notification_id) {
    throw new HttpError(400, "notification_id ausente.");
  }

  const { data, error } = await admin
    .from("notifications")
    .select("*")
    .eq("id", body.notification_id)
    .maybeSingle();

  if (error) {
    throw new HttpError(500, "Erro ao buscar notificacao.", error);
  }

  if (!data) {
    throw new HttpError(404, "Notificacao nao encontrada.");
  }

  return data as NotificationRecord;
}
