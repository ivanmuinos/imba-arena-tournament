// auth-steam: trades a Steam ticket for a session JWT whose subject is the player's Steam id.
//
// POST { "ticket": "<hex>" }                      real login: the ticket is verified with the Steam Web API
// POST { "ticket": "dev:<steam id>" }             dev login: only when STEAM_AUTH_ALLOW_DEV is exactly "true"
//   -> 200 { token, expires_in, steam_id (text), dev }
//   -> 4xx { error: "<code>" }  (codes the game maps: invalid_request, invalid_ticket, ticket_rejected, banned,
//                                dev_login_disabled)  /  5xx when the server is not configured or Steam is down.
//
// Secrets come ONLY from the environment (supabase secrets set ... / functions/.env locally, never committed):
//   STEAM_AUTH_JWT_SECRET   HS256 secret of the project's JWT (>= 32 chars); required, missing = fail closed
//   STEAM_WEB_API_KEY       Steam Web API key; required for real logins
//   STEAM_APP_ID            the game's App ID; required for real logins
//   STEAM_AUTH_IDENTITY     must match the identity the client asked the ticket for (default imba-arena-online)
//   STEAM_API_BASE          override of https://api.steampowered.com (tests only)
//   STEAM_AUTH_ALLOW_DEV    "true" to accept dev tickets. Anything else, or unset, means off. NEVER set in production.

import { handle } from "./core.ts";

Deno.serve((req) => handle(req, Deno.env.toObject(), fetch, () => Math.floor(Date.now() / 1000)));
