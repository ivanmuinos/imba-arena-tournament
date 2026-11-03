#!/bin/sh
# Tournament calibration with a bot as the player: win rate and match length per mode x tier (x round). One process per
# tier (4 in parallel at most). Usage: tools/tournament_run.sh [matches_per_cell=20] [player_skill=0.55] [seed=1]
# The player is a bot with that skill: it is a proxy, not a person (see tools/tournament_sim.gd).
cd "$(dirname "$0")/.."
N=${1:-20}; SKILL=${2:-0.55}; SEED=${3:-1}; OUT=/tmp/tournament_${N}_${SKILL}; rm -rf "$OUT"; mkdir -p "$OUT"
for tier in bronze silver gold gladiator; do
  (godot --headless --path . --script res://tools/tournament_sim.gd -- --n=$N --tiers=$tier --player-skill=$SKILL --seed=$SEED 2>&1 | grep '^RESULT ' | sed 's/^RESULT //' > "$OUT/$tier.json") &
done
wait
python3 tools/tournament_report.py "$OUT"
