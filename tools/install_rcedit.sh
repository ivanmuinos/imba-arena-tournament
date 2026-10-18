#!/bin/sh
# Downloads rcedit (official electron/rcedit release, pinned) into tools/bin/ and, when it can run (Windows, or macOS/Linux with
# wine), registers it in Godot's editor settings so Windows exports embed the .exe icon and version info.
# On macOS WITHOUT wine this only downloads the file: rcedit is a Windows program and cannot run there (tools/export_all.sh
# then exports the .exe without icon/version resources and says so; the window and taskbar icon still come from the project icon).
set -e
cd "$(dirname "$0")"
VER=v2.0.0
SHA=3e7801db1a5edbec91b49a24a094aad776cb4515488ea5a4ca2289c400eade2a
mkdir -p bin
F=bin/rcedit-x64.exe
if [ ! -f "$F" ]; then
  curl -L -o "$F" "https://github.com/electron/rcedit/releases/download/$VER/rcedit-x64.exe"
fi
GOT=$(shasum -a 256 "$F" | cut -d' ' -f1)
[ "$GOT" = "$SHA" ] || { echo "rcedit: SHA-256 inesperado ($GOT)"; rm -f "$F"; exit 1; }
echo "rcedit $VER verificado: $(pwd)/$F"
WINE=$(command -v wine64 || command -v wine || true)
case "$(uname)" in
  Darwin) SETTINGS="$HOME/Library/Application Support/Godot/editor_settings-4.7.tres" ;;
  *) SETTINGS="$HOME/.config/godot/editor_settings-4.7.tres" ;;
esac
if [ -z "$WINE" ]; then
  echo "No hay wine: no se puede ejecutar rcedit en este sistema. El .exe se exporta sin ícono/versión embebidos."
  echo "Para tenerlos: usá una máquina Windows, o instalá wine (brew install --cask wine-stable ya no existe en Homebrew; probá un wine de otra fuente) y repetí."
  exit 0
fi
[ -f "$SETTINGS" ] || { echo "Abrí el editor de Godot una vez para crear $SETTINGS y repetí."; exit 0; }
python3 - "$SETTINGS" "$(pwd)/$F" "$WINE" <<'PY'
import sys, re
path, rcedit, wine = sys.argv[1:4]
s = open(path).read()
for key, val in (("export/windows/rcedit", rcedit), ("export/windows/wine", wine)):
    line = f'{key} = "{val}"'
    if re.search(r'^' + re.escape(key) + r' = .*$', s, re.M):
        s = re.sub(r'^' + re.escape(key) + r' = .*$', line, s, flags=re.M)
    else:
        s = s.replace("[resource]\n", "[resource]\n" + line + "\n", 1)
open(path, "w").write(s)
print("Ajustes del editor actualizados:", path)
PY
