// Request handling for auth-steam, separate from the Deno.serve wiring so it can be driven with a fake env and fetch.

export const TOKEN_TTL = 3600;
const MAX_BODY = 4096;
const STEAM_ID = /^[0-9]{1,18}$/;
const HEX_TICKET = /^[0-9a-fA-F]{16,4096}$/;
const DEFAULT_IDENTITY = "imba-arena-online";
const DEFAULT_STEAM_BASE = "https://api.steampowered.com";

type Env = Record<string, string | undefined>;
type Fetch = typeof fetch;

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

const fail = (status: number, error: string) => json(status, { error });

/** The dev door is open only when the server says so, in exactly one spelling. Everything else is closed. */
export function devLoginAllowed(env: Env): boolean {
  return env.STEAM_AUTH_ALLOW_DEV === "true";
}

function b64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

const enc = new TextEncoder();

export async function signJwt(claims: Record<string, unknown>, secret: string): Promise<string> {
  const head = b64url(enc.encode(JSON.stringify({ alg: "HS256", typ: "JWT" })));
  const body = b64url(enc.encode(JSON.stringify(claims)));
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode(`${head}.${body}`)));
  return `${head}.${body}.${b64url(sig)}`;
}

/** Asks Steam who the ticket belongs to. Returns the Steam id, or a Response describing why not. */
async function verifyWithSteam(ticket: string, env: Env, doFetch: Fetch): Promise<string | Response> {
  const key = env.STEAM_WEB_API_KEY;
  const appId = env.STEAM_APP_ID;
  if (!key || !appId || !/^[0-9]+$/.test(appId)) return fail(503, "not_configured");
  const base = (env.STEAM_API_BASE || DEFAULT_STEAM_BASE).replace(/\/$/, "");
  const url = new URL(`${base}/ISteamUserAuth/AuthenticateUserTicket/v1/`);
  url.searchParams.set("key", key);
  url.searchParams.set("appid", appId);
  url.searchParams.set("ticket", ticket);
  url.searchParams.set("identity", env.STEAM_AUTH_IDENTITY || DEFAULT_IDENTITY);
  let res: Response;
  try {
    res = await doFetch(url, { signal: AbortSignal.timeout(5000) });
  } catch (_) {
    return fail(502, "steam_unavailable"); // never log the URL: it carries the key
  }
  if (res.status >= 500) return fail(502, "steam_unavailable");
  if (res.status === 401 || res.status === 403) return fail(503, "not_configured"); // our key was refused, not the player
  let data: any;
  try {
    data = await res.json();
  } catch (_) {
    return fail(502, "steam_unavailable");
  }
  const p = data?.response?.params;
  if (!res.ok || !p || p.result !== "OK" || typeof p.steamid !== "string" || !STEAM_ID.test(p.steamid)) {
    return fail(403, "ticket_rejected");
  }
  if (p.publisherbanned === true) return fail(403, "banned");
  return p.steamid;
}

export async function handle(req: Request, env: Env, doFetch: Fetch, now: () => number): Promise<Response> {
  if (req.method !== "POST") return fail(405, "invalid_request");
  const secret = env.STEAM_AUTH_JWT_SECRET;
  if (!secret || secret.length < 32) return fail(503, "not_configured");

  const text = await req.text();
  if (text.length > MAX_BODY) return fail(413, "invalid_request");
  let body: any;
  try {
    body = JSON.parse(text);
  } catch (_) {
    return fail(400, "invalid_request");
  }
  const ticket = body?.ticket;
  if (typeof ticket !== "string" || ticket.length === 0) return fail(400, "invalid_request");

  let steamId: string;
  let dev = false;
  if (ticket.startsWith("dev:")) {
    if (!devLoginAllowed(env)) return fail(403, "dev_login_disabled");
    steamId = ticket.slice(4);
    if (!STEAM_ID.test(steamId)) return fail(400, "invalid_ticket");
    dev = true;
  } else {
    if (!HEX_TICKET.test(ticket)) return fail(400, "invalid_ticket");
    const r = await verifyWithSteam(ticket, env, doFetch);
    if (r instanceof Response) return r;
    steamId = r;
  }

  const iat = now();
  const claims: Record<string, unknown> = {
    iss: "imba-arena-auth",
    aud: "authenticated",
    role: "authenticated",
    sub: steamId,
    iat,
    exp: iat + TOKEN_TTL,
  };
  if (dev) claims.dev = true;
  return json(200, { token: await signJwt(claims, secret), expires_in: TOKEN_TTL, steam_id: steamId, dev });
}
