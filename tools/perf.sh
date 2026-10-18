#!/bin/sh
# Frame-time profile in a REAL window (not headless): 3v3 bots fighting, per map and quality level.
# Usage: tools/perf.sh [maps="bridge pillars tomb living"] [levels="alta media baja"] [seconds=8] [WxH=1600x900]
cd "$(dirname "$0")/.."
MAPS=${1:-"bridge pillars tomb living"}; LEVELS=${2:-"alta media baja"}; SEC=${3:-8}; RES=${4:-1600x900}; EXTRA=${5:-}
for m in $MAPS; do for l in $LEVELS; do
  out=$(perl -e 'alarm 120; exec @ARGV' godot --path . --resolution $RES -- --offline --autopilot --mode=3 --map=$m --gfx=$l $EXTRA --time-scale=4 --rounds=999 --perf=$SEC --no-capture 2>&1 | grep '^PERF ')
  echo "$out" | awk -v m=$m -v l=$l '{for(i=2;i<=NF;i++){split($i,kv,"="); if(kv[1]=="fps"||kv[1]=="frame"||kv[1]=="cpu"||kv[1]=="gpu"||kv[1]=="script"||kv[1]=="draws"||kv[1]=="objs"||kv[1]=="prims"){s[kv[1]]+=kv[2]}} n++} END{if(n>0) printf "%-8s %-6s fps=%.0f frame=%.1fms cpu=%.1f gpu=%.1f script=%.1f draws=%.0f objs=%.0f prims=%.0fk (n=%d)\n", m, l, s["fps"]/n, s["frame"]/n, s["cpu"]/n, s["gpu"]/n, s["script"]/n, s["draws"]/n, s["objs"]/n, s["prims"]/n/1000, n; else print m, l, "sin datos"}'
done; done
