#!/usr/bin/env bash
# Tunes fast-iteration deploy: newest CI debug APK → wireless adb → launch.
#
# One-time setup (phone + this box on the same Wi-Fi):
#   Phone: Settings → Developer options → Wireless debugging → ON,
#          then "Pair device with pairing code".
#   Box:   adb pair <ip:pairing-port> <6-digit-code>
#          adb connect <ip:debug-port>
#
# Usage:
#   tools/deploy.sh              # download newest artifact + install + launch
#   tools/deploy.sh --no-fetch   # reinstall the APK already in dist/
set -euo pipefail

REPO="${REPO:-currentsuspect/tunes}"
ARTIFACT="tunes-debug-apk"
ADB="${ADB:-$HOME/dev/platform-tools/platform-tools/adb}"
PKG="com.currentsuspect.tunes"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/tools/dist"

command -v gh >/dev/null || { echo "gh CLI required" >&2; exit 1; }
[ -x "$ADB" ] || { echo "adb not found at $ADB (see header for setup)" >&2; exit 1; }

if [ "${1:-}" != "--no-fetch" ]; then
  run_id=$(gh run list -R "$REPO" --workflow ci.yml --status success -L 1 \
    --json databaseId --jq '.[0].databaseId')
  echo "→ downloading artifact from run $run_id"
  rm -f "$ROOT/tools/dist/app-debug.apk"
  rm -rf "$ROOT/tools/dist/$ARTIFACT"
  gh run download "$run_id" -R "$REPO" -n "$ARTIFACT" -D "$ROOT/tools/dist/"
fi

APK=$(ls "$ROOT"/tools/dist/app-debug.apk 2>/dev/null || ls "$ROOT"/tools/dist/*/app-debug.apk | head -1)
echo "→ installing $(basename "$APK") ($(du -h "$APK" | cut -f1))"
"$ADB" install -r "$APK"

echo "→ launching"
"$ADB" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null
echo "✓ tunes is up on the phone"