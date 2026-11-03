# Sourced by local_check.sh after team_flow.sh: groups, the normal queue, lobby id, result reporting and a concurrent
# pairing run over REST with tokens minted by auth-steam. Verification reads the database as its owner (docker exec psql):
# the hidden skill is exactly what clients can never read.
sql() { docker exec -i "supabase_db_${PROJECT_ID:-imba-arena}" psql -U postgres -d postgres -tA -c "$1" 2>&1; }
jq1() { python3 -c 'import json,sys; d=json.loads(sys.argv[1].split(" ",1)[1]); print(eval(sys.argv[2], {"d": d}))' "$1" "$2"; }
jqv() { python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(eval(sys.argv[2], {"d": d}))' "$1" "$2"; }

echo "== queue flow over HTTP"
sql "delete from public.online_matches; delete from public.queue_tickets; delete from public.play_groups; delete from public.player_skill; delete from public.rate_limits;" >/dev/null
P1=76561199100000001; P2=76561199100000002; P3=76561199100000003; P4=76561199100000004
Q1=$(tok $P1); Q2=$(tok $P2); Q3=$(tok $P3); Q4=$(tok $P4)
for n in 1 2 3 4; do eval "t=\$Q$n"; rest "$t" touch_player "{\"p_name\":\"Jugador$n\"}" >/dev/null; done
VER='{"p_mode":1,"p_version":"0.7.0"}'
expect "anon key cannot read the queue status" "$(rest "$ANON_KEY" queue_status '{}')" "401"
expect "player cannot read player_skill"       "$(curl -s -o /dev/null -w '%{http_code}' "$API_URL/rest/v1/player_skill?select=*" -H "apikey: $ANON_KEY" -H "Authorization: Bearer $Q1")" "403"
expect "idle status"                            "$(rest "$Q1" queue_status '{}')" '"state": "idle"'
expect "P1 joins the 1v1 queue"                 "$(rest "$Q1" join_queue "$VER")" "204"
expect "joining twice is refused"               "$(rest "$Q1" join_queue "$VER")" '"message":"already_queued"'
expect "P1 is searching"                        "$(rest "$Q1" queue_status '{}')" '"state": "searching"'
expect "P2 joins and is matched at once"       "$(rest "$Q2" join_queue "$VER")" "204"
S1=$(rest "$Q1" queue_status '{}'); S2=$(rest "$Q2" queue_status '{}')
expect "P1 sees the match"                      "$S1" '"state": "matched"'
M1=$(jq1 "$S1" 'd["match"]["id"]'); M2=$(jq1 "$S2" 'd["match"]["id"]')
expect "both are in the same match"             "$M1" "$M2"
SIDE1=$(jq1 "$S1" 'd["match"]["side"]'); SIDE2=$(jq1 "$S2" 'd["match"]["side"]')
[ "$SIDE1" != "$SIDE2" ] && ok "sides differ ($SIDE1 / $SIDE2)" || bad "sides differ" "$SIDE1 $SIDE2"
case "$S1" in *skill*|*mmr*|*rating*) bad "status never mentions skill" "$S1";; *) ok "status never mentions skill";; esac
HOST1=$(jq1 "$S1" 'd["match"]["is_host"]')
if [ "$HOST1" = "True" ]; then HT=$Q1; GT=$Q2; GSIDE=$SIDE2; HSIDE=$SIDE1; else HT=$Q2; GT=$Q1; GSIDE=$SIDE1; HSIDE=$SIDE2; fi
expect "the guest cannot publish a lobby"       "$(rest "$GT" publish_lobby "{\"p_match\":\"$M1\",\"p_lobby\":\"109775241000000001\"}")" '"message":"not_host"'
expect "the host publishes a lobby (text id)"   "$(rest "$HT" publish_lobby "{\"p_match\":\"$M1\",\"p_lobby\":\"109775241000000001\"}")" "204"
expect "the guest reads the exact lobby id"     "$(rest "$GT" queue_status '{}')" '"lobby_id": "109775241000000001"'
expect "a stranger cannot report"               "$(rest "$Q3" report_result "{\"p_match\":\"$M1\",\"p_winner\":\"red\"}")" '"message":"not_in_match"'
expect "one side reports: nothing moves yet"    "$(rest "$HT" report_result "{\"p_match\":\"$M1\",\"p_winner\":\"$HSIDE\"}")" "204"
expect "skill still untouched with one report"  "$(sql "select count(*) from public.player_skill")" "0"
expect "the other side agrees"                  "$(rest "$GT" report_result "{\"p_match\":\"$M1\",\"p_winner\":\"$HSIDE\"}")" "204"
expect "match resolved"                         "$(sql "select status from public.online_matches where id = '$M1'")" "resolved"
expect "winner's hidden skill went up (server only)" "$(sql "select skill from public.player_skill where steam_id = $( [ "$HT" = "$Q1" ] && echo $P1 || echo $P2) and mode = 1")" "1524"
expect "loser's hidden skill went down"         "$(sql "select skill from public.player_skill where steam_id = $( [ "$GT" = "$Q1" ] && echo $P1 || echo $P2) and mode = 1")" "1476"
expect "both are idle again"                    "$(rest "$Q1" queue_status '{}') $(rest "$Q2" queue_status '{}')" '"state": "idle"'

echo "== falsified report: the sides disagree"
sql "delete from public.rate_limits;" >/dev/null
rest "$Q3" join_queue "$VER" >/dev/null; rest "$Q4" join_queue "$VER" >/dev/null
S3=$(rest "$Q3" queue_status '{}'); S4=$(rest "$Q4" queue_status '{}')
M3=$(jq1 "$S3" 'd["match"]["id"]'); SIDE3=$(jq1 "$S3" 'd["match"]["side"]'); SIDE4=$(jq1 "$S4" 'd["match"]["side"]')
BEFORE=$(sql "select string_agg(steam_id || ':' || skill || ':' || games, ',' order by steam_id) from public.player_skill")
expect "P3 says its own side won"               "$(rest "$Q3" report_result "{\"p_match\":\"$M3\",\"p_winner\":\"$SIDE3\"}")" "204"
expect "P4 says ITS side won (falsified)"       "$(rest "$Q4" report_result "{\"p_match\":\"$M3\",\"p_winner\":\"$SIDE4\"}")" "204"
expect "match is void"                          "$(sql "select status from public.online_matches where id = '$M3'")" "void"
expect "no skill changed"                       "$(sql "select string_agg(steam_id || ':' || skill || ':' || games, ',' order by steam_id) from public.player_skill")" "$BEFORE"
expect "a void match cannot be reopened"        "$(rest "$Q3" report_result "{\"p_match\":\"$M3\",\"p_winner\":\"$SIDE3\"}")" '"message":"match_closed"'

echo "== group of two + two solos in 2v2 (same side), rate limit"
sql "delete from public.rate_limits;" >/dev/null
P5=76561199100000005; P6=76561199100000006; Q5=$(tok $P5); Q6=$(tok $P6)
for n in 5 6; do eval "t=\$Q$n"; rest "$t" touch_player "{\"p_name\":\"Jugador$n\"}" >/dev/null; done
G=$(rest "$Q1" create_group '{"p_mode":2}'); GID=$(jq1 "$G" 'd')
expect "create_group returns an id"             "$G" "200"
expect "invite P2 (id as text)"                 "$(rest "$Q1" group_add "{\"p_group\":\"$GID\",\"p_steam_id\":\"$P2\"}")" "204"
expect "cannot queue before P2 confirms"        "$(rest "$Q1" join_queue "{\"p_mode\":2,\"p_version\":\"0.7.0\",\"p_group\":\"$GID\"}")" '"message":"not_confirmed"'
INV=$(rest "$Q2" my_group_invites '{}')
expect "P2 sees the group invite"               "$INV" "\"from\": \"$P1\""
expect "P2 confirms"                            "$(rest "$Q2" group_confirm "{\"p_group\":\"$(jq1 "$INV" 'd[0]["id"]')\"}")" "204"
expect "the group searches"                     "$(rest "$Q1" join_queue "{\"p_mode\":2,\"p_version\":\"0.7.0\",\"p_group\":\"$GID\"}")" "204"
expect "P2 is searching too (same ticket)"      "$(rest "$Q2" queue_status '{}')" '"state": "searching"'
rest "$Q3" join_queue '{"p_mode":2,"p_version":"0.7.0"}' >/dev/null
rest "$Q4" join_queue '{"p_mode":2,"p_version":"0.7.0"}' >/dev/null
GS1=$(rest "$Q1" queue_status '{}'); GS2=$(rest "$Q2" queue_status '{}'); GS3=$(rest "$Q3" queue_status '{}'); GS4=$(rest "$Q4" queue_status '{}')
expect "group + 2 solos: matched"               "$GS1" '"state": "matched"'
A=$(jq1 "$GS1" 'd["match"]["side"]'); B=$(jq1 "$GS2" 'd["match"]["side"]'); C=$(jq1 "$GS3" 'd["match"]["side"]'); D=$(jq1 "$GS4" 'd["match"]["side"]')
[ "$A" = "$B" ] && [ "$C" = "$D" ] && [ "$A" != "$C" ] && ok "group together, solos together, opposed ($A/$C)" || bad "sides" "$A $B $C $D"
for t in $Q1 $Q2 $Q3 $Q4; do rest "$t" leave_queue '{}' >/dev/null; done
rest "$Q1" leave_group "{\"p_group\":\"$GID\"}" >/dev/null
sql "delete from public.rate_limits;" >/dev/null
n=0; for i in 1 2 3 4 5 6 7 8 9 10; do rest "$Q5" join_queue '{"p_mode":1,"p_version":"0.7.0"}' >/dev/null; rest "$Q5" leave_queue '{}' >/dev/null; done
expect "the 11th join_queue is rate limited"    "$(rest "$Q5" join_queue '{"p_mode":1,"p_version":"0.7.0"}')" '"message":"rate_limited"'
expect "another player is not affected"         "$(rest "$Q6" join_queue '{"p_mode":1,"p_version":"0.7.0"}')" "204"
rest "$Q6" leave_queue '{}' >/dev/null

echo "== concurrency: 8 players join and poll at the same time; nobody is matched twice"
sql "delete from public.online_matches; delete from public.queue_tickets; delete from public.rate_limits;" >/dev/null
CT=()
for n in 1 2 3 4 5 6 7 8; do
  id=$((76561199200000000 + n)); t=$(tok $id); CT+=("$t"); rest "$t" touch_player "{\"p_name\":\"Conc$n\"}" >/dev/null
done
for t in "${CT[@]}"; do
  ( rest "$t" join_queue '{"p_mode":1,"p_version":"0.7.0"}' >/dev/null
    for k in 1 2 3 4; do rest "$t" queue_status '{}' >/dev/null; done ) &
done
wait
for k in 1 2 3; do for t in "${CT[@]}"; do ( rest "$t" queue_status '{}' >/dev/null ) & done; wait; done
expect "all 8 players ended up in a match"      "$(sql "select count(*) from public.online_match_players where active")" "8"
expect "four 1v1 matches"                       "$(sql "select count(*) from public.online_matches")" "4"
expect "nobody is in two active matches"        "$(sql "select coalesce(max(c),0) from (select count(*) c from public.online_match_players where active group by steam_id) q")" "1"
expect "every match has one player per side"    "$(sql "select count(*) from (select match_id from public.online_match_players group by match_id having count(*) filter (where side='red') = 1 and count(*) filter (where side='blue') = 1) q")" "4"
for t in "${CT[@]}"; do rest "$t" leave_queue '{}' >/dev/null; done
sql "delete from public.online_matches; delete from public.queue_tickets; delete from public.play_groups; delete from public.rate_limits;" >/dev/null
