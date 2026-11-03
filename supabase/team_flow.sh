# Sourced by local_check.sh after the dev-login server is up: a team flow over REST with tokens minted by auth-steam.
# Steam ids are real-sized (17 digits) on purpose: they must survive as text end to end.
jget() { python3 -c 'import json,sys; d=json.loads(sys.argv[1].split(" ",1)[1]); print(eval(sys.argv[2], {"d": d}))' "$1" "$2"; }

# JSON bodies built with printf: nested quotes inside "$(...)" are mangled by bash 3.2 (macOS).
jts() { printf '{"p_team":"%s","p_steam_id":"%s"}' "$1" "$2"; }
jt() { printf '{"p_team":"%s"}' "$1"; }
ji() { printf '{"p_invite":"%s"}' "$1"; }

echo "== team flow over HTTP"
ANA=76561199000000001; BETO=76561199000000002; CARO=76561199000000003
TA=$(tok $ANA); TB=$(tok $BETO); TC=$(tok $CARO)
rest "$TA" touch_player '{"p_name":"Ana"}' >/dev/null
rest "$TB" touch_player '{"p_name":"Beto"}' >/dev/null

R=$(rest "$TA" create_team '{"p_mode":2,"p_name":"Los Lobos"}')
expect "create_team returns 200 and an id" "$R" "200"
TEAM=$(jget "$R" 'd')
expect "second 2v2 refused" "$(rest "$TA" create_team '{"p_mode":2,"p_name":"Otro"}')" '"message":"already_in_team"'
expect "1v1 refused"        "$(rest "$TA" create_team '{"p_mode":1,"p_name":"Solos"}')" '"message":"invalid_mode"'
expect "duplicate name refused" "$(rest "$TB" create_team '{"p_mode":2,"p_name":"los lobos"}')" '"message":"name_taken"'

expect "invite by Steam id as text" "$(rest "$TA" invite_to_team "$(jts "$TEAM" "$BETO")")" "200"
expect "non-captain cannot invite"  "$(rest "$TB" invite_to_team "$(jts "$TEAM" "$CARO")")" '"message":"not_captain"'
INV=$(rest "$TB" my_invites '{}')
expect "Beto sees the invite from Ana (id intact)" "$INV" "\"from\": \"$ANA\""
INVID=$(jget "$INV" 'd[0]["id"]')
expect "Caro cannot accept Beto's invite" "$(rest "$TC" accept_invite "$(ji "$INVID")")" '"message":"invite_not_found"'
expect "Beto accepts"                      "$(rest "$TB" accept_invite "$(ji "$INVID")")" "200"
MY=$(rest "$TB" my_teams '{}')
expect "my_teams lists both members"       "$(jget "$MY" 'len(d[0]["members"])')" "2"
expect "captain is Ana, as exact text"     "$(jget "$MY" 'd[0]["captain"]')" "$ANA"
expect "captain cannot leave"              "$(rest "$TA" leave_team "$(jt "$TEAM")")" '"message":"captain_must_transfer_or_disband"'
expect "Beto cannot kick Ana"              "$(rest "$TB" kick_member "$(jts "$TEAM" "$ANA")")" '"message":"not_captain"'
expect "Ana hands over the captaincy"      "$(rest "$TA" transfer_captain "$(jts "$TEAM" "$BETO")")" "204"
expect "Ana leaves"                        "$(rest "$TA" leave_team "$(jt "$TEAM")")" "204"
expect "Beto disbands"                     "$(rest "$TB" disband_team "$(jt "$TEAM")")" "204"
expect "team gone"                         "$(rest "$TB" my_teams '{}')" "[]"

echo "== direct table access is closed to a signed-in player too"
for tbl in teams team_members team_invites players; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$API_URL/rest/v1/$tbl?select=*" -H "apikey: $ANON_KEY" -H "Authorization: Bearer $TA")
  expect "GET $tbl denied" "$code" "403"
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API_URL/rest/v1/$tbl" -H "apikey: $ANON_KEY" -H "Authorization: Bearer $TA" -H 'Content-Type: application/json' -d '{}')
  expect "POST $tbl denied" "$code" "403"
  code=$(curl -s -o /dev/null -w '%{http_code}' "$API_URL/rest/v1/$tbl?select=*" -H "apikey: $ANON_KEY")
  expect "anon GET $tbl denied" "$code" "401"
done
