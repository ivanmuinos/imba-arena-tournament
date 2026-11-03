#!/bin/bash
# End-to-end check of the online backend on the LOCAL Supabase stack (never a cloud project):
#   supabase start && supabase db reset && ./supabase/local_check.sh
# Serves auth-steam with `supabase functions serve` (Docker; no Deno install needed) under several server configs and
# calls it over HTTP: dev login with the flag off / mis-spelled / on, real login against a fake Steam Web API,
# missing secrets, then drives a team flow over REST with the token it minted.
# Keys come from `supabase status` at run time; nothing is written inside the repo.
set -u
cd "$(dirname "$0")/.."
command -v python3 >/dev/null || { echo "needs python3"; exit 2; }
eval "$(supabase status -o env 2>/dev/null)" || { echo "supabase no esta corriendo (supabase start)"; exit 2; }
TMP=$(mktemp -d)
FAKE_PORT=${FAKE_STEAM_PORT:-47999}
pass=0; failn=0
SERVE_PID=""; FAKE_PID=""
cleanup() {
  [ -n "$SERVE_PID" ] && kill "$SERVE_PID" 2>/dev/null
  [ -n "$FAKE_PID" ] && kill "$FAKE_PID" 2>/dev/null
  wait 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT

ok() { pass=$((pass+1)); echo "  ok   $1"; if [ -n "${DEBUG:-}" ]; then echo "       $LAST" | cut -c1-200; fi; }
bad() { failn=$((failn+1)); echo "  FAIL $1 -- $2"; }
expect() { LAST="$2"; # name, actual, expected: an HTTP status ("200") must be the status itself; anything else is a substring
  case "$3" in
    [0-9][0-9][0-9]) if [ "${2%% *}" = "$3" ]; then ok "$1"; else bad "$1" "got: $2"; fi;;
    *) case "$2" in *"$3"*) ok "$1";; *) bad "$1" "got: $2";; esac;;
  esac
}

# A stand-in for the Steam Web API: ticket aa.. is steam id 76561198000000001, bb.. is rejected, cc.. is a Steam outage.
cat > "$TMP/fake_steam.py" <<'PY'
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        u = urlparse(self.path); q = parse_qs(u.query)
        t = q.get("ticket", [""])[0]
        good = q.get("key") == ["fakekey"] and q.get("appid") == ["480"] and q.get("identity") == ["imba-arena-online"]
        if not good: code, body = 403, {}
        elif t.startswith("cc"): code, body = 503, {}
        elif t.startswith("aa"): code, body = 200, {"response": {"params": {"result": "OK", "steamid": "76561198000000001", "ownersteamid": "76561198000000001", "vacbanned": False, "publisherbanned": False}}}
        elif t.startswith("dd"): code, body = 200, {"response": {"params": {"result": "OK", "steamid": "76561198000000002", "vacbanned": False, "publisherbanned": True}}}
        else: code, body = 200, {"response": {"error": {"errorcode": 3, "errordesc": "Invalid ticket"}}}
        data = json.dumps(body).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
HTTPServer(("0.0.0.0", int(sys.argv[1])), H).serve_forever()
PY
python3 "$TMP/fake_steam.py" "$FAKE_PORT" & FAKE_PID=$!

serve() { # env lines as arguments; restarts the function runtime with exactly this environment
  [ -n "$SERVE_PID" ] && { kill "$SERVE_PID" 2>/dev/null; wait "$SERVE_PID" 2>/dev/null; SERVE_PID=""; }
  printf '%s\n' "$@" > "$TMP/env"
  supabase functions serve --env-file "$TMP/env" > "$TMP/serve.log" 2>&1 & SERVE_PID=$!
  for i in $(seq 1 60); do
    grep -q "Serving functions" "$TMP/serve.log" 2>/dev/null && break
    sleep 1
  done
  sleep 2
}
login() { # json body -> "<status> <body>"
  curl -s -m 20 -o "$TMP/out" -w '%{http_code}' -X POST "$API_URL/functions/v1/auth-steam" \
    -H "Authorization: Bearer $ANON_KEY" -H "apikey: $ANON_KEY" -H 'Content-Type: application/json' -d "$1" > "$TMP/code"
  echo "$(cat "$TMP/code") $(cat "$TMP/out")"
}
STEAM_ENV=("STEAM_WEB_API_KEY=fakekey" "STEAM_APP_ID=480" "STEAM_API_BASE=http://host.docker.internal:$FAKE_PORT")

echo "== dev flag unset (production-like): dev tickets refused, real tickets work"
serve "STEAM_AUTH_JWT_SECRET=$JWT_SECRET" "${STEAM_ENV[@]}"
expect "dev ticket refused"                 "$(login '{"ticket":"dev:7001"}')" "403 {\"error\":\"dev_login_disabled\"}"
expect "real ticket accepted"               "$(login '{"ticket":"aa00112233445566778899"}')" '"steam_id":"76561198000000001"'
expect "real ticket: not a dev token"       "$(login '{"ticket":"aa00112233445566778899"}')" '"dev":false'
expect "rejected ticket"                    "$(login '{"ticket":"bb00112233445566778899"}')" "403 {\"error\":\"ticket_rejected\"}"
expect "publisher-banned account"           "$(login '{"ticket":"dd00112233445566778899"}')" "403 {\"error\":\"banned\"}"
expect "Steam outage is a 502"              "$(login '{"ticket":"cc00112233445566778899"}')" "502 {\"error\":\"steam_unavailable\"}"
expect "non-hex ticket"                     "$(login '{"ticket":"not-hex!!"}')" "400 {\"error\":\"invalid_ticket\"}"
expect "missing ticket"                     "$(login '{}')" "400"
expect "garbage body"                       "$(login 'nope')" "400"
expect "GET refused"                        "$(curl -s -o /dev/null -w '%{http_code}' "$API_URL/functions/v1/auth-steam" -H "Authorization: Bearer $ANON_KEY")" "405"
expect "no apikey: gateway refuses"         "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API_URL/functions/v1/auth-steam" -d '{}')" "401"

for v in "TRUE" "True" "1" "yes" "false" ""; do
  echo "== dev flag spelled '$v': still closed"
  serve "STEAM_AUTH_JWT_SECRET=$JWT_SECRET" "STEAM_AUTH_ALLOW_DEV=$v"
  expect "dev ticket refused with flag '$v'" "$(login '{"ticket":"dev:7001"}')" "dev_login_disabled"
done

echo "== no JWT secret: fail closed"
serve "STEAM_AUTH_ALLOW_DEV=true"
expect "503 without secret" "$(login '{"ticket":"dev:7001"}')" "503 {\"error\":\"not_configured\"}"
serve "STEAM_AUTH_JWT_SECRET=short" "STEAM_AUTH_ALLOW_DEV=true"
expect "503 with a weak secret" "$(login '{"ticket":"dev:7001"}')" "503"
serve "STEAM_AUTH_JWT_SECRET=$JWT_SECRET"
expect "503 real login without Steam key" "$(login '{"ticket":"aa00112233445566778899"}')" "503 {\"error\":\"not_configured\"}"

echo "== dev flag exactly 'true': dev login works"
serve "STEAM_AUTH_JWT_SECRET=$JWT_SECRET" "STEAM_AUTH_ALLOW_DEV=true"
expect "dev login"            "$(login '{"ticket":"dev:7001"}')" '"steam_id":"7001"'
expect "dev flag in the reply" "$(login '{"ticket":"dev:7001"}')" '"dev":true'
expect "bad dev id"           "$(login '{"ticket":"dev:abc"}')" "400"

tok() { login "{\"ticket\":\"dev:$1\"}" | sed -E 's/.*"token":"([^"]+)".*/\1/'; }
rest() { # token, function, json -> "<status> <body>"
  curl -s -m 20 -o "$TMP/out" -w '%{http_code}' -X POST "$API_URL/rest/v1/rpc/$2" \
    -H "apikey: $ANON_KEY" -H "Authorization: Bearer $1" -H 'Content-Type: application/json' -d "$3" > "$TMP/code"
  echo "$(cat "$TMP/code") $(cat "$TMP/out")"
}
T1=$(tok 7001)
expect "minted token accepted by PostgREST" "$(rest "$T1" touch_player '{"p_name":"Ana"}')" "204"
expect "anon key cannot call touch_player"  "$(rest "$ANON_KEY" touch_player '{"p_name":"Ana"}')" "401"
expect "a forged token is refused"          "$(rest "${T1%.*}.AAAA" touch_player '{"p_name":"Ana"}')" "401"

[ -f supabase/team_flow.sh ] && . supabase/team_flow.sh

echo
echo "passed: $pass  failed: $failn"
[ "$failn" -eq 0 ]
