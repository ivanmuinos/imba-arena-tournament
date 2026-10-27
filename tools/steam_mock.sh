#!/bin/sh
# Opens copies of the game with simulated Steam (--steam-mock): they see each other as Steam friends and can create,
# list and join lobbies and play over "Steam" without a Steam client. Names default to Ana and Beto.
#   tools/steam_mock.sh            two copies (Ana, Beto)
#   tools/steam_mock.sh Ana Beto Caro
cd "$(dirname "$0")/.."
[ $# -eq 0 ] && set -- Ana Beto
for name in "$@"; do
  godot --path . -- --steam-mock="$name" --steam-log &
  sleep 1
done
wait
