# Origin — where the bytes actually come from

Decision recorded 2026-09-08, after the Cloudflare migration (SPEC §2.4,
`docs/` history). Describes the target for retiring the home box, and the one
component that has to exist first.

---

## 1. The correction this document exists to make

SPEC §1.8 and §2.1 describe tunesd's object store as a cache in front of
Telegram, with on-demand fetch filling it. Measured on the live box, that is
not what it is:

- **637 of 637 tracks are held locally**, permanently. Nothing is evicted.
- **`serve.ts` has no Telegram call at all.** A cache miss is a `stat` failure
  and a 404, not a fetch. The on-demand mode in §2.1 was never built.

So the box is not caching Telegram. It is a **second complete copy of the
library, carrying the entire availability burden**. Calling it a cache made it
sound like a performance layer that could be dropped; it could not, because
nothing else could serve a miss.

That is the real reason the box cannot simply be switched off, and it is a
different problem from "where do we put 12 GB".

## 2. What is actually load-bearing

Measured, not estimated:

| Thing | Size | Needed to serve a miss? |
| --- | ---: | --- |
| `data/objects` | 11.97 GB | No — it is a copy of what Telegram already has |
| `data/covers` | 50 MB | No — same |
| `data/state.json` (sha → Telegram message) | 152 KB | **Yes** |
| `data/session` (StringSession) | 369 B | **Yes** |

**The irreplaceable state is 153 KB.** Everything else is 11.97 GB of
re-downloadable bytes. The ratio is roughly 1 : 76,800.

`state.json` maps `channelId:messageId → {sha, caption, fileName}` for 747
entries. Checked against the manifest: **every one of the 637 tracks resolves
back to a Telegram message.** That coverage is what makes any of this possible;
without it a missing object would be unrecoverable and the box could never
leave.

## 3. Target

```text
Telegram            canonical library, full
   ↓  cache miss
fetcher             MTProto session + sha→message map, tiny, persistent
   ↓
R2                  bounded shared cache, ~3 GB
   ↓
Worker              auth, capability checks, routing — stateless
   ↓
phone               personal hot cache and downloads
```

### The defining property

**A cache miss must still play.** If R2 does not hold an object, the request
resolves through the fetcher to Telegram and succeeds — slower, but it
succeeds. Any design where a miss is a failure has reproduced the current
situation under a new name.

### R2 is the cache, not the fetcher

R2 stores bytes. It cannot speak MTProto. Something persistent must hold the
Telegram session and the sha→message map, and that is the one piece of
always-on infrastructure this architecture needs. It does **not** need the
library: it fetches an object, writes it to R2, and can discard its local copy.

## 4. Eviction

Budget ~3 GB, enforced at the R2 layer, independent of the fetcher.

Not sequential. Insertion order says nothing about value — a track played
yesterday by both listeners should outrank one played once six months ago that
happens to have been added later.

```
score = recency + frequency + active_listeners + pinned
```

Rules that matter more than the exact weights:

- **Never evict an object being streamed.**
- **Evict with hysteresis**: cross 3 GB, evict down to ~2.7 GB. Trimming to
  exactly the limit churns on every write.
- **Prefer retaining what is played often**, not what arrived recently.

Eviction is cheap to get wrong here, and that is the point: an evicted object
is re-fetchable from Telegram, and if a phone already holds it the listener
never notices. Cache policy is an optimisation, not a correctness concern.

## 5. Storage economics, measured

Library is 12.02 GB today (11.97 GB audio + 50 MB art) and grows — it was 623
tracks in the morning and 637 by evening.

| | Free tier | Egress |
| --- | --- | --- |
| Cloudflare R2 | 10 GB | **$0, always** |
| Backblaze B2 | 10 GB | free to 3× stored, then $0.01/GB |

Neither free tier fits the whole library, and it does not matter, because under
this architecture **R2 never holds the whole library** — it holds ~3 GB. That
fits inside the free tier with room to spare.

R2 over B2 for one reason: streaming a music library *is* egress. B2's free
egress caps at 3× stored bytes; at a 3 GB cache that is ~9 GB/month, which two
listeners on FLAC would exhaust in a few hundred tracks. R2 charges nothing for
egress at any volume.

## 6. Sequence

1. **On-demand fetch, on the box.** Wire the miss path that SPEC §2.1 already
   specifies: `serve.ts` asks the fetcher instead of returning 404. Changes
   nothing externally, and is the prerequisite for every step after it.
2. **Prove eviction is survivable.** Delete cold objects from the box and
   confirm playback still works via the miss path. Until this holds, nothing
   should be deleted anywhere.
3. **Move the fetcher off the box.** A small persistent service carrying the
   153 KB of state. This is the step that ends the home box's role.
4. **R2 as the shared cache**, with the budget and eviction above.
5. **Retire the box's object store.**

Steps 1 and 2 are where the risk is. Steps 3–5 are logistics once a miss can be
served.

## 7. Can the fetcher run on Cloudflare? — measured, 2026-09-08

The assumption was that a persistent MTProto session needs a VM, because a
Worker is request-scoped and cannot hold one. Tested rather than assumed, by
running the real client inside the Workers runtime with `nodejs_compat`:

```json
{ "import extensions": "ok", "import TelegramClient": "ok",
  "websocket to telegram DC": "ok" }
```

All three pass. What makes it work:

- **The transport is injectable.** `telegramBaseClient.js:172` reads
  `clientParams.networkSocket || PromisedNetSockets`, so a different transport
  is a constructor argument, not a fork.
- **A WebSocket transport already ships** and needs no Node at all.
  `extensions/PromisedWebSockets.js` contains zero `require()` calls; it uses
  `globalThis.WebSocket`, which Workers provide, with a `webSocketImpl`
  override hook.
- **The Node built-ins are confined.** `node:net` appears only in the TCP
  transport being replaced. `fs`/`path` appear only in `downloads.js` and
  `uploads.js`, on the optional `outputFile` branch. `os` supplies device
  strings; `zlib` decompresses MTProto payloads and has a Workers equivalent.

### Two things the transport gets wrong outside a browser

Both cost a failed attempt each, so they are written down rather than
rediscovered:

- **`Sec-WebSocket-Protocol: binary` is mandatory.** `PromisedWebSockets.js:95`
  does `new WebSocket(url, "binary")`. Without the subprotocol Telegram
  answers **404**, which reads like a wrong path and is not.
- **A hostname is required, not the DC IP.** The library builds
  `wss://{ip}:443/apiws` (`PromisedWebSockets.js:94`). That works in a browser,
  where the IP is a fronted web endpoint, and fails elsewhere because TLS to a
  bare address carries no SNI. A DC-id → hostname map is needed.

The endpoint is also host-specific, so the map has to be right rather than
guessed:

| host | `/apiws` upgrade |
| --- | --- |
| `venus.web.telegram.org` | 404 |
| `pluto.web.telegram.org` | **101** |
| `flora.web.telegram.org` | **101** |

### Consequence

The fetcher does not need a VM. A Durable Object can hold the session, and the
target in §3 becomes Cloudflare-native end to end:

```text
Telegram  →  Durable Object (MTProto session)  →  R2 (~3 GB)  →  Worker  →  phone
```

### Still unproven

A live WebSocket is not an authenticated MTProto session. The handshake, the
auth key exchange and a real media download are untested, and they need a
**second Telegram session** — authorising one requires a phone number and a
login code, which is a human step. The production session must not be used:
tunesd serves the phone from it right now, and a concurrent connection on the
same auth key risks taking it down.

## 8. What is deliberately not decided here

- **Eviction is out of scope for the next proof.** Establish reliable
  cache-miss retrieval first, then add the bounded cache and its policy
  separately, so the two failure domains stay distinct.
- **Whether the phone cache changes.** It already holds downloads and works
  offline; nothing above requires touching it.
