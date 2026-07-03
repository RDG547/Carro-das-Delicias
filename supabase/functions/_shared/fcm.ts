import { type SupabaseClient } from "npm:@supabase/supabase-js@2";

export type NotificationRecord = {
  id?: number | string;
  user_id?: string;
  title?: string;
  message?: string;
  type?: string;
  data?: Record<string, unknown> | null;
};

type FcmServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

type PushResult = {
  attempted: number;
  sent: number;
  failed: number;
  skipped: boolean;
  reason?: string;
};

let cachedAccessToken: { token: string; expiresAt: number } | null = null;

export async function sendPushForNotification(
  admin: SupabaseClient,
  notification: NotificationRecord,
): Promise<PushResult> {
  const serviceAccount = readServiceAccount();
  if (!serviceAccount) {
    console.warn("FIREBASE_SERVICE_ACCOUNT_JSON nao configurado; push ignorado.");
    return {
      attempted: 0,
      sent: 0,
      failed: 0,
      skipped: true,
      reason: "missing_firebase_service_account",
    };
  }

  const userId = notification.user_id;
  if (!userId) {
    return {
      attempted: 0,
      sent: 0,
      failed: 0,
      skipped: true,
      reason: "missing_user_id",
    };
  }

  const { data: tokens, error } = await admin
    .from("user_push_tokens")
    .select("id, token")
    .eq("user_id", userId)
    .eq("is_active", true);

  if (error) {
    console.warn("Nao foi possivel buscar tokens FCM", error);
    return { attempted: 0, sent: 0, failed: 0, skipped: true, reason: "token_query_failed" };
  }

  if (!tokens || tokens.length === 0) {
    return { attempted: 0, sent: 0, failed: 0, skipped: true, reason: "no_tokens" };
  }

  const accessToken = await getAccessToken(serviceAccount);
  let sent = 0;
  let failed = 0;

  for (const tokenRow of tokens) {
    const token = tokenRow.token?.toString();
    if (!token) continue;

    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token,
            notification: {
              title: notification.title ?? "Carro das Delicias",
              body: notification.message ?? "Nova notificacao",
            },
            data: stringifyData({
              ...(notification.data ?? {}),
              notification_id: notification.id,
              notification_type: notification.type,
            }),
            android: {
              priority: "HIGH",
              notification: {
                channel_id: "carrodasdelicias_channel",
                icon: "ic_stat_car",
                color: "#000000",
                sound: "default",
                notification_priority: "PRIORITY_HIGH",
              },
            },
            apns: {
              payload: {
                aps: {
                  sound: "default",
                },
              },
            },
          },
        }),
      },
    );

    if (response.ok) {
      sent++;
      continue;
    }

    failed++;
    const errorPayload = await safeJson(response);
    console.warn("Erro ao enviar FCM", response.status, errorPayload);

    if (isInvalidTokenResponse(response.status, errorPayload)) {
      await admin
        .from("user_push_tokens")
        .update({ is_active: false, updated_at: new Date().toISOString() })
        .eq("token", token);
    }
  }

  return {
    attempted: tokens.length,
    sent,
    failed,
    skipped: false,
  };
}

function readServiceAccount(): FcmServiceAccount | null {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!raw) return null;

  try {
    const parsed = JSON.parse(raw) as Partial<FcmServiceAccount>;
    if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
      return null;
    }

    return {
      project_id: parsed.project_id,
      client_email: parsed.client_email,
      private_key: parsed.private_key,
    };
  } catch (error) {
    console.warn("FIREBASE_SERVICE_ACCOUNT_JSON invalido", error);
    return null;
  }
}

async function getAccessToken(serviceAccount: FcmServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedAccessToken && cachedAccessToken.expiresAt - 60 > now) {
    return cachedAccessToken.token;
  }

  const assertion = await createJwtAssertion(serviceAccount, now);
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  const payload = await safeJson(response);
  if (!response.ok) {
    throw new Error(`Erro OAuth FCM: ${response.status} ${JSON.stringify(payload)}`);
  }

  const accessToken = payload.access_token?.toString();
  const expiresIn = Number(payload.expires_in ?? 3600);
  if (!accessToken) {
    throw new Error("OAuth FCM nao retornou access_token.");
  }

  cachedAccessToken = {
    token: accessToken,
    expiresAt: now + expiresIn,
  };

  return accessToken;
}

async function createJwtAssertion(
  serviceAccount: FcmServiceAccount,
  issuedAt: number,
): Promise<string> {
  const header = base64UrlJson({ alg: "RS256", typ: "JWT" });
  const claimSet = base64UrlJson({
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: issuedAt,
    exp: issuedAt + 3600,
  });
  const unsignedJwt = `${header}.${claimSet}`;
  const key = await importPrivateKey(serviceAccount.private_key);
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsignedJwt),
  );

  return `${unsignedJwt}.${base64UrlBytes(new Uint8Array(signature))}`;
}

async function importPrivateKey(privateKeyPem: string): Promise<CryptoKey> {
  const pemBody = privateKeyPem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const binary = Uint8Array.from(atob(pemBody), (char) => char.charCodeAt(0));

  return await crypto.subtle.importKey(
    "pkcs8",
    binary,
    {
      name: "RSASSA-PKCS1-v1_5",
      hash: "SHA-256",
    },
    false,
    ["sign"],
  );
}

function stringifyData(data: Record<string, unknown>): Record<string, string> {
  return Object.fromEntries(
    Object.entries(data)
      .filter(([, value]) => value !== null && value !== undefined)
      .map(([key, value]) => [key, String(value)]),
  );
}

async function safeJson(response: Response): Promise<Record<string, unknown>> {
  try {
    const payload = await response.json();
    if (payload && typeof payload === "object" && !Array.isArray(payload)) {
      return payload as Record<string, unknown>;
    }
  } catch (_) {
    // Ignored.
  }
  return {};
}

function isInvalidTokenResponse(
  status: number,
  payload: Record<string, unknown>,
): boolean {
  const text = JSON.stringify(payload).toLowerCase();
  return status === 404 ||
    text.includes("unregistered") ||
    text.includes("registration-token-not-registered") ||
    text.includes("invalid_argument");
}

function base64UrlJson(value: Record<string, unknown>): string {
  return base64UrlBytes(new TextEncoder().encode(JSON.stringify(value)));
}

function base64UrlBytes(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
