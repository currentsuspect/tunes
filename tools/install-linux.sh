#!/usr/bin/env bash
# Installs the tunes Linux release bundle + launcher entry.
# Usage: ./tools/install-linux.sh   (run from repo root, after `flutter build linux --release`)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/app/build/linux/x64/release/bundle/tunes"
DEST="$HOME/.local/share/tunes"
DESKTOP="$HOME/.local/share/applications/tunes.desktop"

if [ ! -x "$SRC" ]; then
  echo "no release bundle at $SRC -- run this first:" >&2
  echo "  cd app && flutter build linux --release" >&2
  exit 1
fi

mkdir -p "$DEST" "$HOME/.local/share/icons" "$HOME/.local/share/applications"
cp -a "$ROOT/app/build/linux/x64/release/bundle/." "$DEST/"
cp -a "$ROOT/app/assets/icon.png" "$HOME/.local/share/icons/tunes.png"

cat > "$DESKTOP" << 'ENTRY'
[Desktop Entry]
Name=Tunes
Comment=Private music library fed by Telegram
Exec=/home/currentsuspect/.local/share/tunes/tunes
Icon=tunes
Terminal=false
Type=Application
Categories=AudioVideo;Audio;Player;Music;
StartupNotify=true
StartupWMClass=com.currentsuspect.tunes
ENTRY

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
fi

echo "installed: $DEST/tunes + tunes.desktop"
