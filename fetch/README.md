# tunes-fetch — Cloudflare-native fetcher (PROOF, not live)

ORIGIN steps 2–3, proven 2026-09-09 against `wrangler dev` (local workerd) with
the isolated spike session. **No routes: this worker serves no traffic.**
Promotion needs an explicit decision (worker name, route, edge↔fetcher auth).

## What was proven

- MTProto handshake + `getMe` inside workerd (`nodejs_compat`), session DC 4
  fronted through `pluto.web.telegram.org` (bare DC IPs carry no SNI; venus
  404s). Bare-IP `wss://ip:443/apiws` fails; hostname rewrite fixes it.
- `getMessages` + full 1.5 MB media download with matching sha256, repeatedly.
- R2 round trip: miss → Telegram → `CACHE.put(sha)` → serve; second call is
  an R2 hit.
- The failure that shaped the design: a client cached in the front Worker
  works once, then stalls — promises resolve in the wrong request context.
  The connection lives in a singleton Durable Object (`Fetcher`, `getByName`),
  one context, stable across repeated fetches. Do not "simplify" this back
  into a global.

## What is not here yet

- Eviction (ORIGIN §4: ~3 GB budget, hysteresis, never evict mid-stream).
- Edge↔fetcher auth (which capability gates a fetch; accounting against caps).
- The sha→message map: the DO currently takes `(chat, msg)` from the caller.
  Production reads the 153 KB map — lives in the DO (storage) or D1.
- Route, custom hostname, production secrets (`TG_API_HASH`, `TG_SESSION`
  via `wrangler secret put`; the session is the revocable spike key).

## Local proof loop

```sh
npm install
cp .dev.vars.example .dev.vars   # fill TG_API_HASH + TG_SESSION, chmod 600
npm run dev                      # :8787
curl localhost:8787/ping
curl "localhost:8787/cached?chat=-5567140650&msg=8416&sha=<64hex>"
```

`compatibility_date` is pinned to 2026-05-01: the newest the local workerd
supports. Do not bump it without re-running this loop.
