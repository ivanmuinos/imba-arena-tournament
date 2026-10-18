#!/bin/sh
# Runs balance_sim.gd in parallel (one process per mode x map) and merges the JSON into docs/balance.md via tools/balance_report.py.
# Usage: tools/balance_run.sh [matches_per_combo=150] [tag=baseline]
cd "$(dirname "$0")/.."
N=${1:-150}; TAG=${2:-baseline}; OUT=/tmp/balance_$TAG; rm -rf "$OUT"; mkdir -p "$OUT"
for mode in 2 3; do for map in bridge pillars tomb living; do
  (godot --headless --path . --script res://tools/balance_sim.gd -- --n=$N --modes=$mode --maps=$map --seed=$((mode*100+${#map}*7+N)) 2>&1 | grep '^RESULT ' | sed 's/^RESULT //' > "$OUT/${mode}_$map.json") &
done; done
wait
python3 tools/balance_report.py "$OUT" "$TAG"
