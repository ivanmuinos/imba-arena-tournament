#!/bin/sh
# Downloads and installs the official Godot export templates matching the installed `godot` (needed once).
set -e
V=$(godot --version | sed 's/\.official.*//')            # e.g. 4.7.2.stable
BASE=$(echo "$V" | sed 's/\.stable//')-stable            # e.g. 4.7.2-stable
case "$(uname)" in
  Darwin) DEST="$HOME/Library/Application Support/Godot/export_templates/$V" ;;
  MINGW*|MSYS*|CYGWIN*) DEST="$(cygpath -u "$APPDATA")/Godot/export_templates/$V" ;;
  *) DEST="$HOME/.local/share/godot/export_templates/$V" ;;
esac
if [ -f "$DEST/version.txt" ]; then echo "Plantillas $V ya instaladas en $DEST"; exit 0; fi
TMP=$(mktemp -d)
curl -L -o "$TMP/t.tpz" "https://github.com/godotengine/godot/releases/download/$BASE/Godot_v${BASE}_export_templates.tpz"
unzip -q "$TMP/t.tpz" -d "$TMP"
mkdir -p "$DEST"
cp -R "$TMP"/templates/* "$DEST"/
rm -rf "$TMP"
echo "Plantillas instaladas en $DEST"
