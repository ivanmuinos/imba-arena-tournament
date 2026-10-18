#!/bin/sh
# Real-input playtest in a real window (not --headless) for each class (or the ones given), against easy bots.
# Usage: tools/playtest.sh [class ...]   Screens go to /tmp/playtest_<class>_*.png
cd "$(dirname "$0")/.."
CLASSES=${*:-"mage mage:frost warlock hunter warrior priest rogue"}  # class or class:spec
fail=0
for token in $CLASSES; do
  c=${token%%:*}; sp=${token#*:}; [ "$sp" = "$token" ] && sp=""
  map=$(echo "bridge pillars tomb living" | tr ' ' '\n' | sed -n "$(( $(echo $c | cksum | cut -d' ' -f1) % 4 + 1 ))p")
  # The matches are live games against bots (units die, move off-screen, get stunned): one retry absorbs that noise.
  for attempt in 1 2; do
    out=$(perl -e 'alarm 240; exec @ARGV' godot --path . --resolution 1280x720 -- --playtest --offline --cls=$c --spec=$sp --map=$map --diff=easy --mode=2 --time-scale=2 --shot=/tmp/playtest_${c}_${sp:-base} 2>&1)
    echo "== $token ($map) intento $attempt"; echo "$out" | grep -E "PLAYTEST (FAIL|done|FAILED)|SCRIPT ERROR|ERROR:" | grep -v "resources still\|leaked\|RenderingServer"
    echo "$out" | grep -q "fails=0" && break
  done
  echo "$out" | grep -q "fails=0" || fail=1
done
exit $fail
