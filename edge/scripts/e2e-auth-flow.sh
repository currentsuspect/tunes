#!/usr/bin/env bash
# Exercises the whole credential chain against a local wrangler dev + local D1.
#
# Named e2e-* and never run in CI, per AGENTS.md §6: it binds a port and drives
# a real Worker runtime rather than pure functions.
#
#   invite -> enrol -> refresh -> access token -> media grant -> revoke
#
# Asserts the negative cases too, because "it issued a token" is not the
# interesting part; "it stopped issuing one after revocation" is.
set -euo pipefail

PORT="${PORT:-8799}"
BASE="http://127.0.0.1:$PORT"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"

pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; exit 1; }

CODE="e2e-invite-$(date +%s)"
CODE_HASH=$(printf '%s' "$CODE" | sha256sum | cut -d' ' -f1)
NOW=$(date +%s)

echo "→ seeding account + invite"
# OR IGNORE so the script is re-runnable against a local D1 that already has
# the account from a previous run. The invite code is unique per run (it is
# derived from the clock), so only the account can collide.
npx wrangler d1 execute tunes-auth --local --command \
  "INSERT OR IGNORE INTO account (id, label, status, created_at) VALUES ('acct-e2e', 'E2E', 'active', $NOW);
   INSERT INTO invite (code_hash, account_id, expires_at) VALUES ('$CODE_HASH', 'acct-e2e', $((NOW + 3600)));" \
  >/dev/null

echo "→ starting wrangler dev"
npx wrangler dev --local --port "$PORT" --var ACCESS_SECRET:e2e-access --var MEDIA_SECRET:e2e-media \
  >/tmp/e2e-wrangler.log 2>&1 &
DEV_PID=$!
trap 'kill $DEV_PID 2>/dev/null || true' EXIT

# Readiness, not success: the Worker answers /nope with 404 by design, so
# `curl -f` would treat a perfectly healthy server as still starting. Any HTTP
# response at all means the runtime is up.
for _ in $(seq 1 60); do
  [ -n "$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$BASE/nope" 2>/dev/null | grep -v '^000$')" ] && break
  sleep 1
done

echo "→ flow"
REDEEM=$(curl -s -X POST "$BASE/auth/redeem" -H 'content-type: application/json' \
  -d "{\"code\":\"$CODE\",\"label\":\"E2E device\"}")
REFRESH=$(echo "$REDEEM" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("refresh_token",""))')
DEVICE=$(echo "$REDEEM" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("device_id",""))')
[ -n "$REFRESH" ] || fail "redeem returned no refresh token: $REDEEM"
pass "invite redeemed, device $DEVICE enrolled"

AGAIN=$(curl -s -X POST "$BASE/auth/redeem" -H 'content-type: application/json' \
  -d "{\"code\":\"$CODE\",\"label\":\"replay\"}")
echo "$AGAIN" | grep -q '"error"' || fail "invite was redeemable twice: $AGAIN"
pass "invite is single-use"

TOKEN=$(curl -s -X POST "$BASE/auth/token" -H 'content-type: application/json' \
  -d "{\"refresh_token\":\"$REFRESH\"}" \
  | python3 -c 'import json,sys;print(json.load(sys.stdin).get("access_token",""))')
[ -n "$TOKEN" ] || fail "no access token issued"
pass "access token minted from refresh token"

SHA=$(printf 'a%.0s' $(seq 1 64))
GRANT=$(curl -s -X POST "$BASE/auth/media/grant" -H "authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' -d "{\"path\":\"/track/$SHA\"}")
echo "$GRANT" | grep -q '"url"' || fail "no media grant: $GRANT"
pass "media grant minted"

TRAVERSE=$(curl -s -X POST "$BASE/auth/media/grant" -H "authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' -d '{"path":"/../../etc/passwd"}')
echo "$TRAVERSE" | grep -q '"error"' || fail "signed an arbitrary path: $TRAVERSE"
pass "refuses to sign a path outside /track and /art"

NOAUTH=$(curl -s -X POST "$BASE/auth/media/grant" -H 'content-type: application/json' \
  -d "{\"path\":\"/track/$SHA\"}")
echo "$NOAUTH" | grep -q '"error"' || fail "granted media without a token: $NOAUTH"
pass "media grant requires a bearer token"

curl -s -X DELETE "$BASE/auth/device/$DEVICE" -H "authorization: Bearer $TOKEN" | grep -q '"revoked":true' \
  || fail "revoke did not report success"
pass "device revoked"

AFTER=$(curl -s -X POST "$BASE/auth/token" -H 'content-type: application/json' \
  -d "{\"refresh_token\":\"$REFRESH\"}")
echo "$AFTER" | grep -q '"error"' || fail "revoked device still gets tokens: $AFTER"
pass "revoked device can no longer mint access tokens"

STALE=$(curl -s -X POST "$BASE/auth/media/grant" -H "authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' -d "{\"path\":\"/track/$SHA\"}")
echo "$STALE" | grep -q '"error"' || fail "revoked device still granted media on an unexpired token: $STALE"
pass "revoked device is refused media even with an unexpired access token"

echo "✓ all assertions passed"
