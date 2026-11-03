#!/bin/bash
# Real end-to-end run of the online queue on the LOCAL Supabase stack (never a cloud project) with headless game copies
# and the simulated Steam (--steam-mock): sign-in (auth-steam dev tickets), queue, pairing, Steam lobby, a match played by
# bots driving the human units, result reporting and the hidden skill updated server-side.
#   supabase start && supabase db reset && tools/online_e2e.sh [1|2]     (1: two copies in 1v1, 2: four copies in 2v2)
# Scenarios (all against the same stack): normal, falsified (one side reports the opposite via REST), quit (a copy is
# killed mid-match). Needs docker, python3 and godot on the PATH. Nothing is written inside the repo.
set -u
cd "$(dirname "$0")/.."
MODE=${1:-1}
SCENARIO=${2:-normal}   # normal | falsified | quit
eval "$(supabase status -o env 2>/dev/null)" || { echo "supabase no esta corriendo (supabase start)"; exit 2; }
TMP=$(mktemp -d)
PIDS=()
cleanup() { for p in "${PIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done; wait 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT
sql() { docker exec "supabase_db_imba-arena" psql -U postgres -d postgres -tA -c "$1" 2>&1 </dev/null; }
sql "delete from public.online_matches; delete from public.queue_tickets; delete from public.play_groups; delete from public.player_skill; delete from public.rate_limits; delete from public.players;" >/dev/null

printf '%s\n' "STEAM_AUTH_JWT_SECRET=$JWT_SECRET" "STEAM_AUTH_ALLOW_DEV=true" > "$TMP/env"
supabase functions serve --env-file "$TMP/env" > "$TMP/serve.log" 2>&1 & PIDS+=($!)
for i in $(seq 1 60); do grep -q "Serving functions" "$TMP/serve.log" 2>/dev/null && break; sleep 1; done
sleep 2

if [ "$MODE" = 1 ]; then NAMES=(Ana Beto); else NAMES=(Ana Beto Caro Dani); fi
export IMBA_ONLINE_URL="$API_URL" IMBA_ONLINE_ANON_KEY="$ANON_KEY"
CLASSES=(warrior rogue warrior rogue)   # melee fights end; four mages in 2v2 draw round after round
i=0
for n in "${NAMES[@]}"; do
  mkdir -p "$TMP/$n"
  godot --headless --path . -- --online --steam-mock="$n" --queue="$MODE" --cls="${CLASSES[$i]}" --autopilot --rounds=1 --time-scale=6 --no-capture \
    --save-dir="$TMP/$n" --log > "$TMP/$n.log" 2>&1 &
  PIDS+=($!)
  i=$((i+1))
  sleep 1
done

want=${#NAMES[@]}
echo "== waiting for $want players to be matched"
for i in $(seq 1 90); do
  n=$(sql "select count(*) from public.online_match_players")
  [ "$n" = "$want" ] && break
  sleep 1
done
echo "players in a match: $n"
MATCH=$(sql "select id from public.online_matches order by created_at desc limit 1")

dev_token() { curl -s -m 20 -X POST "$API_URL/functions/v1/auth-steam" -H "Authorization: Bearer $ANON_KEY" -H "apikey: $ANON_KEY" \
  -H 'Content-Type: application/json' -d "$(printf '{"ticket":"dev:%s"}' "$1")" | sed -E 's/.*"token":"([^"]+)".*/\1/'; }
rpc() { curl -s -m 20 -X POST "$API_URL/rest/v1/rpc/$2" -H "apikey: $ANON_KEY" -H "Authorization: Bearer $1" -H 'Content-Type: application/json' -d "$3" -w ' [%{http_code}]'; echo; }
HOST=$(sql "select host from public.online_matches where id = '$MATCH'")
GUEST=$(sql "select steam_id from public.online_match_players where match_id = '$MATCH' and steam_id <> $HOST limit 1")
GNAME=$(sql "select name from public.players where steam_id = $GUEST")
GPID=""
for k in "${!NAMES[@]}"; do [ "${NAMES[$k]}" = "$GNAME" ] && GPID=${PIDS[$((k+1))]}; done
echo "host=$HOST guest=$GUEST ($GNAME, pid $GPID)"

if [ "$SCENARIO" = "quit" ]; then
  sleep 10   # a few seconds into the match
  kill -9 "$GPID" 2>/dev/null
  echo "== killed $GNAME (SIGKILL) mid-match"
fi
if [ "$SCENARIO" = "falsified" ]; then
  sleep 8
  kill -STOP "$GPID"   # the guest's own client can no longer report: we speak for it
  echo "== froze $GNAME; waiting for the host to report the real winner"
  for i in $(seq 1 300); do
    TRUTH=$(sql "select reported from public.online_match_players where match_id = '$MATCH' and steam_id = $HOST")
    [ -n "$TRUTH" ] && break
    sleep 1
  done
  LIE=$([ "$TRUTH" = "red" ] && echo blue || echo red)
  echo "host reported: $TRUTH ; the guest (falsified) reports: $LIE"
  rpc "$(dev_token "$GUEST")" report_result "$(printf '{"p_match":"%s","p_winner":"%s"}' "$MATCH" "$LIE")"
  kill -CONT "$GPID"
fi

echo "== waiting for the match to resolve (or time out)"
for i in $(seq 1 ${E2E_WAIT:-400}); do
  st=$(sql "select status from public.online_matches where id = '$MATCH'")
  [ "$st" != "open" ] && break
  sleep 1
done
echo "match status: $st"
sql "select steam_id, side, reported, active from public.online_match_players where match_id = '$MATCH' order by side, steam_id"
echo "-- hidden skill (read by the DB owner; no client can read this):"
sql "select steam_id, mode, skill, games from public.player_skill order by steam_id"
echo "-- history (matches):"
sql "select status, winner from public.online_matches"
for n in "${NAMES[@]}"; do echo "-- log $n"; grep -E "^\[(online|cola|cliente|servidor)\]" "$TMP/$n.log" | cut -c1-160 | tail -12; grep -E "SCRIPT ERROR|ERROR" "$TMP/$n.log" | head -3; done

if [ "$SCENARIO" = "quit" ]; then
  echo "== two minutes of silence from the killed player, then any poll sweeps (the host's copy has already left the queue)"
  sleep 125
  rpc "$(dev_token "$GUEST")" queue_status '{}' | cut -c1-120
  echo "killed player still active in the match: $(sql "select active from public.online_match_players where match_id = '$MATCH' and steam_id = $GUEST")"
  echo "killed player can search again: $(rpc "$(dev_token "$GUEST")" join_queue '{"p_mode":1,"p_version":"0.7.0"}')"
fi
