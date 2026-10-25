#!/usr/bin/env bash
# Turn a BYOB box off (docs/BYOB.md, phase 2). The account goes back to the owner's box.
#
#   scripts/byob/disable-box.sh cedric-box                  # shows what it would do
#   scripts/byob/disable-box.sh cedric-box --yes            # disables routing (the row is kept)
#   scripts/byob/disable-box.sh cedric-box --yes --delete-tunnel
#
# Routing stops within one access-token lifetime (10 minutes); signed /track and /art URLs already handed out keep
# pointing at the box until they expire (4 hours). --delete-tunnel also deletes the box's tunnel, so the box can no
# longer connect at all. Its DNS record is left in place: it points at a tunnel that no longer exists, and the Worker
# refuses that hostname anyway. Remove it from the Cloudflare dashboard if you want it gone.
set -euo pipefail

usage() { echo "usage: $0 <box-id> [--yes] [--delete-tunnel]" >&2; exit 2; }
[[ $# -ge 1 ]] || usage
BOX_ID="$1"; shift
APPLY=0
DELETE_TUNNEL=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) APPLY=1; shift ;;
    --delete-tunnel) DELETE_TUNNEL=1; shift ;;
    *) usage ;;
  esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EDGE="${HERE}/../../edge"
die() { echo "disable-box: $*" >&2; exit 1; }
say() { echo "disable-box: $*"; }

[[ "$BOX_ID" =~ ^[a-z0-9]([a-z0-9-]{0,34}[a-z0-9])?-box$ ]] || die "not a box id (name-box): '$BOX_ID'"
d1() { (cd "$EDGE" && npx wrangler d1 execute tunes-auth --remote --json --command "$1" 2>/dev/null); }

ROW="$(d1 "SELECT account_id, status FROM box WHERE id = '${BOX_ID}'" \
  | python3 -c '
import json, sys
try:
    r = json.load(sys.stdin)[0]["results"]
    print(r[0]["account_id"], r[0]["status"]) if r else print("")
except Exception:
    print("")  # no box table yet (migration 0006), or D1 unreachable
' || true)"
[[ -n "$ROW" ]] || die "no box ${BOX_ID} (or no box table yet: edge migration 0006)"
read -r ACCOUNT STATUS <<<"$ROW"
say "box ${BOX_ID} for ${ACCOUNT}: ${STATUS}"

if [[ "$APPLY" != "1" ]]; then
  say "would set it disabled$([[ $DELETE_TUNNEL == 1 ]] && echo " and delete tunnel tunes-${BOX_ID}"). Run again with --yes."
  exit 0
fi

d1 "UPDATE box SET status = 'disabled' WHERE id = '${BOX_ID}'" >/dev/null || die "could not update the box row"
say "disabled: ${ACCOUNT} is served by the owner's box from its next access token"

if [[ "$DELETE_TUNNEL" == "1" ]]; then
  cloudflared tunnel delete -f "tunes-${BOX_ID}" >/dev/null 2>&1 && say "tunnel tunes-${BOX_ID} deleted" \
    || say "tunnel tunes-${BOX_ID} not deleted (already gone, or still connected: stop it on the box, then retry)"
fi
