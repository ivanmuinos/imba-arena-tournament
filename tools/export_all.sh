#!/bin/sh
# Builds distributable zips in build/: ImbaArenaTournament-windows.zip, -macos.zip (universal), -linux.zip.
# Needs the export templates (tools/install_templates.sh). Usage: tools/export_all.sh [windows] [macos] [linux]
set -e
cd "$(dirname "$0")/.."
TARGETS=${*:-"windows macos"}
# Git Bash on Windows has no zip: fall back to PowerShell's Compress-Archive (`zip -q -r OUT .` zips the current directory).
if ! command -v zip >/dev/null; then
  zip() { powershell -NoProfile -Command "Compress-Archive -Force -Path * -DestinationPath '$(cygpath -w "$3")'"; }
fi
rm -rf build && mkdir -p build
godot --headless --path . --import >/dev/null 2>&1 || true
# Windows icon/version resources need rcedit (which needs wine outside Windows): enable them only when it is usable.
cp export_presets.cfg /tmp/imba_presets_backup.cfg
trap 'cp /tmp/imba_presets_backup.cfg export_presets.cfg' EXIT
RC=false
if [ -f tools/bin/rcedit-x64.exe ] && { [ "$(uname -s | cut -c1-5)" = "MINGW" ] || command -v wine64 >/dev/null || command -v wine >/dev/null; }; then RC=true; fi
sed -i.bak "s/^application\/modify_resources=.*/application\/modify_resources=$RC/" export_presets.cfg && rm -f export_presets.cfg.bak
[ "$RC" = true ] || echo "Aviso: sin rcedit+wine el .exe de Windows no lleva ícono ni info de versión embebidos (ver tools/install_rcedit.sh)."
for t in $TARGETS; do
  case "$t" in
    windows)
      mkdir -p build/windows
      cp steam_appid.txt build/windows/ 2>/dev/null || true
      godot --headless --path . --export-release "Windows Desktop" build/windows/ImbaArenaTournament.exe
      cp tools/LEEME.txt build/windows/
      (cd build/windows && zip -q -r ../ImbaArenaTournament-windows.zip .)
      ;;
    macos)
      mkdir -p build/macos
      godot --headless --path . --export-release "macOS" build/macos/ImbaArenaTournament.zip
      mkdir -p build/macos/stage
      ditto -x -k build/macos/ImbaArenaTournament.zip build/macos/stage
      cp tools/LEEME.txt build/macos/stage/
      (cd build/macos/stage && ditto -c -k --sequesterRsrc . ../../ImbaArenaTournament-macos.zip) 2>/dev/null || (cd build/macos/stage && zip -q -r -y ../../ImbaArenaTournament-macos.zip .)
      ;;
    linux)
      mkdir -p build/linux
      godot --headless --path . --export-release "Linux" build/linux/ImbaArenaTournament.x86_64
      cp tools/LEEME.txt build/linux/
      (cd build/linux && zip -q -r ../ImbaArenaTournament-linux.zip .)
      ;;
  esac
done
ls -la build/*.zip
