#!/bin/sh
# 1v1 matchup matrix (rows = attacker class, columns = opponent) from bot duels. Usage: tools/duel_run.sh [duels_per_pair_per_map=3] [tag]
cd "$(dirname "$0")/.."
N=${1:-3}; TAG=${2:-duels}; OUT=/tmp/duel_$TAG; rm -rf "$OUT"; mkdir -p "$OUT"
for map in bridge pillars tomb living; do
  (godot --headless --path . --script res://tools/balance_sim.gd -- --duel --n=$N --maps=$map --seed=$((${#map}*13+N)) 2>&1 | grep '^RESULT ' | sed 's/^RESULT //' > "$OUT/$map.json") &
done
wait
python3 tools/duel_report.py "$OUT"
