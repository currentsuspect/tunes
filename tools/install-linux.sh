#!/usr/bin/env bash
# Installs the tunes Linux release bundle, its logo and its launcher entry.
# Usage: ./tools/install-linux.sh   (run from repo root, after `flutter build linux --release`)
#
# The window's app id is com.currentsuspect.tunes (linux/CMakeLists.txt). On
# Wayland a dock or bar finds a window's icon through the desktop entry of
# the same name, so the entry and the icon are both installed under the app
# id; a "tunes.desktop" and a loose ~/.local/share/icons/tunes.png left the
# window without a logo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/app/build/linux/x64/release/bundle"
DEST="$HOME/.local/share/tunes"
APP_ID="com.currentsuspect.tunes"
APPS="$HOME/.local/share/applications"
ICONS="$HOME/.local/share/icons/hicolor"

if [ ! -x "$SRC/tunes" ]; then
  echo "no release bundle at $SRC -- run this first:" >&2
  echo "  cd app && flutter build linux --release" >&2
  exit 1
fi

# Into a fresh folder, then swapped in: a running copy keeps its files.
mkdir -p "$(dirname "$DEST")" "$APPS"
rm -rf "$DEST.new"
cp -a "$SRC/." "$DEST.new/"
if [ -d "$DEST" ]; then
  rm -rf "$DEST.prev"
  mv "$DEST" "$DEST.prev"
fi
mv "$DEST.new" "$DEST"

# The logo at the sizes launchers ask for, in the icon theme (the window
# names it, see linux/runner/my_application.cc). The launcher entry points
# at the file itself: a launcher that indexed the theme before this ran
# (Quickshell's, here) would not find a new name until it restarted.
for size in 32 48 64 128 256 512; do
  mkdir -p "$ICONS/${size}x${size}/apps"
  magick "$ROOT/app/assets/icon.png" -resize "${size}x${size}" \
    "$ICONS/${size}x${size}/apps/$APP_ID.png"
done
rm -f "$HOME/.local/share/icons/tunes.png" "$APPS/tunes.desktop"

cat > "$APPS/$APP_ID.desktop" << ENTRY
[Desktop Entry]
Name=Tunes
Comment=Private music library fed by Telegram
Exec=$DEST/tunes
Icon=$ICONS/256x256/apps/$APP_ID.png
Terminal=false
Type=Application
Categories=AudioVideo;Audio;Player;Music;
StartupNotify=true
StartupWMClass=$APP_ID
ENTRY

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t "$ICONS" >/dev/null 2>&1 || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APPS" >/dev/null 2>&1 || true
fi

echo "installed: $DEST/tunes (previous kept at $DEST.prev) + $APP_ID.desktop + logo"
