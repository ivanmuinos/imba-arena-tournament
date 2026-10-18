#!/bin/sh
# Runs the headless test suite; fails on any test failure or GDScript error.
cd "$(dirname "$0")"
out=$(godot --headless --path . --script res://tests/run_tests.gd -- "$@" 2>&1)
status=$?
echo "$out" | grep -vE "^Godot Engine|^$"
if echo "$out" | grep -qE "SCRIPT ERROR|Parse Error|Compile Error"; then
  echo "✗ Hay errores de script"
  exit 1
fi
exit $status
