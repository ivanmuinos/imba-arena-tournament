#!/bin/sh
# Headless smoke checks of the real game: menu, an offline match, and a dedicated server with a
# remote client over ENet. Fails on any engine/script error. Needs no window (--headless).
cd "$(dirname "$0")/.."
fail=0
# Time limit for a command: coreutils `timeout` when present (Linux, Git Bash on Windows: perl's alarm there cannot stop the
# native Godot process, which left dedicated servers holding the port), else perl's alarm (macOS has no `timeout`).
limit() {
  secs=$1; shift
  if command -v timeout >/dev/null; then timeout "$secs" "$@"; else perl -e "alarm $secs; exec @ARGV" "$@"; fi
}
check() { # name, output
  if echo "$2" | grep -vE "ObjectDB instances were leaked|resources still in use|^   at: (cleanup|clear)|^Godot Engine|^$" | grep -E "ERROR|SCRIPT|WARNING" >/dev/null; then
    echo "✗ $1"; echo "$2" | grep -E "ERROR|SCRIPT|WARNING" | head -10; fail=1
  else
    echo "✓ $1"
  fi
}
godot --headless --path . --import >/dev/null 2>&1
out=$(limit 60 godot --headless --path . --quit-after 120 2>&1)
check "menú principal" "$out"
out=$(limit 90 godot --headless --path . --quit-after 1500 -- --offline --autopilot --log 2>&1)
check "partida offline (1500 cuadros)" "$out"
echo "$out" | grep -q "snapshot #1 " || { echo "✗ la partida offline no produjo snapshots"; fail=1; }
out=$(limit 90 godot --headless --path . --quit-after 2500 -- --offline --drive --cls=priest --map=tomb --mode=3 --log 2>&1)
check "jugador con entradas simuladas (priest, tomb, 3v3)" "$out"
out=$(limit 90 godot --headless --path . --quit-after 2500 -- --offline --drive --cls=rogue --map=living --log 2>&1)
check "jugador con entradas simuladas (rogue, living, 2v2)" "$out"
out=$(limit 90 godot --headless --path . --quit-after 2500 -- --practice --drive --cls=mage --log 2>&1)
check "arena de práctica con entradas simuladas" "$out"
echo "$out" | grep -q "snapshot #1 " || { echo "✗ la arena de práctica no produjo snapshots"; fail=1; }
out=$(limit 90 godot --headless --path . --quit-after 2500 -- --practice=tutorial --drive --cls=warrior --log 2>&1)
check "tutorial con entradas simuladas" "$out"
(limit 45 godot --headless --path . -- --server --port=7791 --wait=2 --autopilot > /tmp/magma_smoke_server.txt 2>&1 &)
sleep 3
out=$(limit 40 godot --headless --path . --quit-after 1200 -- --join=127.0.0.1:7791 --name=Smoke --log 2>&1)
check "cliente ENet contra servidor dedicado" "$out"
echo "$out" | grep -q "partida: yo=" || { echo "✗ el cliente no entró a la partida"; fail=1; }
echo "$out" | grep -q "snapshot #" || { echo "✗ el cliente no recibió snapshots"; fail=1; }
sleep 1
check "servidor dedicado" "$(cat /tmp/magma_smoke_server.txt)"
grep -q "empezó una partida" /tmp/magma_smoke_server.txt || { echo "✗ el servidor no empezó la partida"; fail=1; }
exit $fail
