#!/usr/bin/env bash
# Make a BYOB box for an account (docs/BYOB.md, phase 2). Run by the Tunes owner, on the owner's machine.
#
#   scripts/byob/new-box.sh acct-cedric          # shows what it would do; changes nothing (box cedric-box)
#   scripts/byob/new-box.sh acct-cedric --yes    # does it
#
# It creates the box's Cloudflare Tunnel and DNS name in the owner's account, a publish key (only its hash is stored),
# and the `box` row that turns routing on for the account. Everything the box owner needs goes into one file,
# ~/.config/tunes/boxes/<box-id>.env (mode 600), to hand over privately. Nothing secret is printed.
#
# Needs: cloudflared logged in (~/.cloudflared/cert.pem), wrangler logged in, migration 0006 applied, and the edge
# deployed with the box routing (PR #36). If a step fails after the tunnel exists, the tunnel is deleted again.
set -euo pipefail

usage() {
  echo "usage: $0 <account-id> [--box-id name-box] [--archive-chat id] [--env path/to/tunesd/.env] [--yes]" >&2
  exit 2
}

[[ $# -ge 1 ]] || usage
ACCOUNT="$1"; shift
BOX_ID=""
ARCHIVE_CHAT="${BYOB_ARCHIVE_CHAT:-}"
OWNER_ENV="${HOME}/Dev/tunes/tunesd/.env"
APPLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --box-id) BOX_ID="${2:-}"; shift 2 ;;
    --archive-chat) ARCHIVE_CHAT="${2:-}"; shift 2 ;;
    --env) OWNER_ENV="${2:-}"; shift 2 ;;
    --yes) APPLY=1; shift ;;
    *) usage ;;
  esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EDGE="${HERE}/../../edge"
# One level under the zone: its certificate covers *.aestra.studio only (a box.aestra.studio level had none).
ZONE="aestra.studio"
PUBLISH_URL="https://tunes.aestra.studio/internal/publish"
OUT_DIR="${HOME}/.config/tunes/boxes"

die() { echo "new-box: $*" >&2; exit 1; }
say() { echo "new-box: $*"; }

# --- the box id: the hostname's first label, so its shape is fixed (edge/src/db.ts BOX_ID) ---------------------------
[[ "$ACCOUNT" =~ ^acct-[a-z0-9-]+$ ]] || die "account ids look like acct-name, got '$ACCOUNT'"
[[ -n "$BOX_ID" ]] || BOX_ID="${ACCOUNT#acct-}-box"
[[ "$BOX_ID" =~ ^[a-z0-9]([a-z0-9-]{0,34}[a-z0-9])?-box$ ]] || die "box id '$BOX_ID' must be a-z 0-9 - ending in -box, e.g. cedric-box"
HOST="${BOX_ID}.${ZONE}"
TUNNEL_NAME="tunes-${BOX_ID}"

# --- the archive group: the owner's, or the first channel the owner's box reads (tunesd's own default) -------------
if [[ -z "$ARCHIVE_CHAT" && -r "$OWNER_ENV" ]]; then
  ARCHIVE_CHAT="$(grep -E '^TUNESD_ARCHIVE_CHAT=' "$OWNER_ENV" | head -1 | cut -d= -f2- || true)"
  if [[ -z "$ARCHIVE_CHAT" ]]; then
    ARCHIVE_CHAT="$(grep -E '^TUNESD_CHANNELS=' "$OWNER_ENV" | head -1 | cut -d= -f2- | grep -oE -- '-?[0-9]{5,}' | head -1 || true)"
  fi
fi
[[ "$ARCHIVE_CHAT" =~ ^-?[0-9]+$ ]] || die "no archive group id: pass --archive-chat, or --env pointing at the owner's tunesd .env"

d1() { (cd "$EDGE" && npx wrangler d1 execute tunes-auth --remote --json --command "$1" 2>/dev/null); }
d1_count() { d1 "$1" | python3 -c 'import json,sys; r=json.load(sys.stdin)[0]["results"]; print(list(r[0].values())[0] if r else 0)'; }

# --- checks: read-only ------------------------------------------------------------------------------------------
command -v cloudflared >/dev/null || die "cloudflared not installed"
[[ -r "${HOME}/.cloudflared/cert.pem" ]] || die "cloudflared is not logged in (cloudflared tunnel login)"
[[ "$(d1_count "SELECT COUNT(*) FROM account WHERE id = '${ACCOUNT}' AND status = 'active'")" == "1" ]] \
  || die "no active account ${ACCOUNT} in D1"
TABLE="$(d1_count "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'box'")"
if [[ "$TABLE" == "1" ]]; then
  [[ "$(d1_count "SELECT COUNT(*) FROM box WHERE account_id = '${ACCOUNT}' AND status = 'active'")" == "0" ]] \
    || die "${ACCOUNT} already has an active box (scripts/byob/disable-box.sh first)"
  [[ "$(d1_count "SELECT COUNT(*) FROM box WHERE id = '${BOX_ID}'")" == "0" ]] || die "box id ${BOX_ID} is taken"
fi
if cloudflared tunnel list --name "$TUNNEL_NAME" 2>/dev/null | grep -q "$TUNNEL_NAME"; then
  die "a tunnel named ${TUNNEL_NAME} already exists"
fi

say "account      ${ACCOUNT}"
say "box          ${BOX_ID}  ->  https://${HOST}"
say "tunnel       ${TUNNEL_NAME} (created in the owner's Cloudflare account)"
say "archive      ${ARCHIVE_CHAT}"
say "bundle       ${OUT_DIR}/${BOX_ID}.env (mode 600)"

if [[ "$APPLY" != "1" ]]; then
  [[ "$TABLE" == "1" ]] || say "NOTE: the box table does not exist yet: apply migration 0006 before --yes"
  say "nothing changed. Run again with --yes to create it."
  exit 0
fi
[[ "$TABLE" == "1" ]] || die "the box table does not exist: apply edge migration 0006 first (npm run migrate:remote in edge/)"

# --- create, rolling the tunnel back if anything after it fails ------------------------------------------------------
TUNNEL_ID=""
cleanup() {
  local status=$?
  if [[ $status -ne 0 && -n "$TUNNEL_ID" ]]; then
    echo "new-box: failed; deleting tunnel ${TUNNEL_ID}" >&2
    cloudflared tunnel delete -f "$TUNNEL_ID" >/dev/null 2>&1 || echo "new-box: could not delete it; do it by hand" >&2
  fi
}
trap cleanup EXIT

TUNNEL_ID="$(cloudflared tunnel create "$TUNNEL_NAME" 2>&1 | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | tail -1)"
[[ -n "$TUNNEL_ID" ]] || die "tunnel was not created"
say "tunnel created: ${TUNNEL_ID}"

# By UUID, never by name: route dns resolves a name against whatever config cloudflared loads, and once pointed the
# owner's own hostname at the wrong tunnel (edge/wrangler.toml's tunnel notes).
cloudflared tunnel route dns "$TUNNEL_ID" "$HOST" >/dev/null 2>&1 || die "DNS for ${HOST} was not created"
say "dns: ${HOST}"

TOKEN="$(cloudflared tunnel token "$TUNNEL_ID")"
[[ -n "$TOKEN" ]] || die "could not read the tunnel token"

PUBLISH_KEY="$(openssl rand -hex 32)"
KEY_HASH="$(printf '%s' "$PUBLISH_KEY" | sha256sum | cut -d' ' -f1)"
NOW="$(date +%s)"
d1 "INSERT INTO box (id, account_id, publish_key_hash, status, created_at) VALUES ('${BOX_ID}', '${ACCOUNT}', '${KEY_HASH}', 'active', ${NOW})" >/dev/null \
  || die "could not write the box row"
[[ "$(d1_count "SELECT COUNT(*) FROM box WHERE id = '${BOX_ID}' AND status = 'active'")" == "1" ]] || die "box row not found after insert"
say "box row written: routing for ${ACCOUNT} goes to ${HOST} from its next access token (10 min at most)"

umask 077
mkdir -p "$OUT_DIR"
cat > "${OUT_DIR}/${BOX_ID}.env" <<EOF
# Tunes box ${BOX_ID} for ${ACCOUNT}, made $(date -u +%Y-%m-%dT%H:%MZ). Hand this file over privately.
# Its values go into the box's tunesd .env and cloudflared (docs/byob/AGENT.md).
TUNESD_BOX_ID=${BOX_ID}
TUNES_BOX_HOST=${HOST}
TUNNEL_TOKEN=${TOKEN}
INTERNAL_PUBLISH_URL=${PUBLISH_URL}
INTERNAL_PUBLISH_KEY=${PUBLISH_KEY}
TUNESD_ARCHIVE_CHAT=${ARCHIVE_CHAT}
EOF
chmod 600 "${OUT_DIR}/${BOX_ID}.env"
trap - EXIT
say "done. Bundle: ${OUT_DIR}/${BOX_ID}.env"
say "check it once the box runs: curl -H 'authorization: Bearer <owner key>' https://tunes.aestra.studio/internal/boxes/${BOX_ID}/health"
