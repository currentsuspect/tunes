#!/usr/bin/env bash
# Tunes fast-iteration deploy: newest CI release APK → wireless adb → launch.
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
ARTIFACT="tunes-apk"
ADB="${ADB:-$HOME/dev/platform-tools/platform-tools/adb}"
PKG="com.currentsuspect.tunes"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/tools/dist"

command -v gh >/dev/null || { echo "gh CLI required" >&2; exit 1; }
[ -x "$ADB" ] || { echo "adb not found at $ADB (see header for setup)" >&2; exit 1; }

if [ "${1:-}" != "--no-fetch" ]; then
  head_sha=$(git -C "$ROOT" rev-parse HEAD)
  run_id=$(gh run list -R "$REPO" --workflow ci.yml --commit "$head_sha" --status success -L 1 \
    --json databaseId --jq '.[0].databaseId')
  if [ -z "$run_id" ]; then
    echo "no green CI run for local HEAD $head_sha — push first" >&2
    exit 1
  fi
  echo "→ downloading artifact from run $run_id (commit $head_sha)"
  # Clear every stale APK, not just the one we are about to replace --
  # otherwise the picker below can find last week's build and install it
  # while reporting success.
  find "$ROOT/tools/dist" -name '*.apk' -delete
  rm -rf "$ROOT/tools/dist/$ARTIFACT"
  gh run download "$run_id" -R "$REPO" -n "$ARTIFACT" -D "$ROOT/tools/dist/"
fi

APK=$(find "$ROOT/tools/dist" -name '*.apk' -print -quit)
[ -n "$APK" ] || { echo "no APK in tools/dist — run without --no-fetch" >&2; exit 1; }
echo "→ installing $(basename "$APK") ($(du -h "$APK" | cut -f1))"
# Release and debug builds share the committed tunes-debug.keystore, so this
# upgrades in place instead of failing on a signature mismatch.
"$ADB" install -r "$APK"

echo "→ launching"
"$ADB" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null
echo "✓ tunes is up on the phone"

# The install landed, so the remote copy has served its purpose: delete it
# and the artifact quota stays near zero whatever CI uploads (the workflow
# overwrites one artifact per run; this removes even that one). Best effort --
# a failed delete must never fail a good install. Only in fetch mode, where
# a run_id names the artifact to remove.
if [ "${1:-}" != "--no-fetch" ] && [ -n "${run_id:-}" ]; then
  artifact_id=$(gh api "repos/$REPO/actions/runs/$run_id/artifacts" \
    --jq '.artifacts[] | select(.name=="'"$ARTIFACT"'") | .id' 2>/dev/null | head -n 1) || true
  if [ -n "${artifact_id:-}" ]; then
    gh api -X DELETE "repos/$REPO/actions/artifacts/$artifact_id" --silent 2>/dev/null \
      && echo "→ deleted remote artifact $artifact_id" || true
  fi
fi