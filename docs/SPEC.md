# TUNES

## Working codename — real name decided before M5 branding (package id `com.currentsuspect.tunes` is name-proof, rename-safe).

## Personal music library for one person, fed by Telegram

**Product thesis:** Tunes is a private, exceptionally fast music library + player that pulls from the Telegram channels Dylan already trusts, sorts it *seriously* (tagged, deduped, quality-ranked), plays it with gapless, properly-normalized audio, and downloads the good copies to the phone.

It should feel like a well-organized private record collection, not a chat client with a play button.

> **Tunes is not trying to know the world's music. Tunes is trying to know Dylan's channels.**

The product should make two things feel effortless: *"play something good"* and *"keep the best copy of everything"*.

---

# 1. Product principles

## 1.1 Personal before universal

Tunes learns Dylan's sources and Dylan's taste — not a catalog, not an algorithm, not a chart.

- Channel config is explicit: you point it at channels; everything else is curation.
- Sorting must be deterministic and explainable. Every track in a view got there for a stated reason (artist/tag/quality/deduped-with).
- Never manufacture certainty: "quality unknown" is a real state, shown honestly.

## 1.2 Serious sorting is the moat

Most TG music toys are folder browsers. Tunes is a library:

- Every file gets probed, tagged, and fingerprinted — no trusting filenames.
- Duplicates resolved to one canonical track with a five-dimension quality ranking (see §5). The best copy is the kept one; worse copies are marked dupes (and optionally GC'd).
- Canonical identity is a hierarchy, not a single key. **Recording identity** (what this actually is) → **verified content fingerprint** → **MusicBrainz relationship** (what it probably is) → **release metadata** (enrichment). MusicBrainz tells us what something probably is; it never decides whether two files are the same recording. Same recording at different quality = one canonical track. Different recordings sharing an MBID tie-in = separate tracks, always.
- Covers extracted from tags/captions or MusicBrainz; embedded into the library record, never scattered as loose art files.

## 1.3 Quality is bounded by source, and that's fine

Tunes cannot create quality the source lacks. "Premium" means:

- gapless playback
- R128 loudness normalization (EBU R128 measured by scanner, applied at playback edge — files never rewritten)
- no transcodes anywhere in the pipeline; the phone plays the original file
- correct resampling at the device edge only
- state-accurate seek and resume

The spec sets the bar at: *the phone sounds as good as the file the channel posted.*

## 1.4 Speed is part of the design

The app must feel instant on a mid-range Android phone.

Targets:

- launch to usable library: < 500 ms measured **warm** (measurement contexts defined in §12 — cold/warm/search are distinct targets, never one number)
- search response: < 100 ms (FTS5-backed)
- queue/track switch: < 80 ms perceived
- zero network dependency for anything already downloaded
- no blocking DB work on the UI thread
- precomputed library manifest; no on-open scans
- first sync after config is the only "waiting" moment ever

The user should never think: *"Wait for the app."*

## 1.5 Private by default

Amended 2026-09-08. The privacy posture is unchanged; what changed is that "private"
is now enforced by authentication rather than by being hard to reach.

- The Telegram session lives **on the box** (`tunesd`), never in the app.
- No advertising SDKs. No analytics. No third-party trackers. Unchanged.
- The app talks to two Tunes-operated destinations and no others: the auth service,
  and the media origin behind Cloudflare (§2.4).
- **Accounts exist to make access revocable, not to build a profile.** An account is an
  identity and a list of devices. It is not behavioural data, and there is nothing to
  sell in it.
- **Offline playback is never gated on authentication.** A downloaded track plays with
  no network and no valid token.
- Obscurity is not part of the security model. A hostname is published in Certificate
  Transparency logs the moment a certificate is issued for it, so "nobody knows the
  address" protects nothing and must never be relied on.

## 1.6 One user, one source of truth

The **box manifest** is the library. The phone is a synced, cached, downloadable view of it. Downloads to the phone are canonical local copies — the phone library must survive the box being off.

## 1.7 Files stay sacred

Original channel files are treated as sacred: never re-encoded, never rewritten, never touched for loudness or tags. The pipeline *records*; playback *interprets*.

This is why R128 gain lives at the playback edge, why dedupe is non-destructive, why the app always plays the original bytes, and why there is no transcode anywhere between the channel and the ear.

> **Original files stay sacred; playback can intelligently interpret them.**

## 1.8 Stream first, keep what you love

**Status, corrected 2026-09-08:** the on-demand fetch below was never built.
`serve.ts` answers a cache miss with a 404, so the object store is not a cache
in front of Telegram — it is a second complete copy of the library carrying the
whole availability burden. See `docs/ORIGIN.md` for what is actually
load-bearing (153 KB of session and sha→message map, against 11.97 GB of
re-downloadable objects) and the sequence for fixing it.

| State | Behavior |
|---|---|
| Not downloaded | **stream immediately** — tunesd fetches from Telegram on demand, serves original bytes |
| Downloaded | local file plays immediately |
| Network unavailable | downloaded library still works, fully |

Downloads remain the preferred path (data costs, offline, box-off survivability), but the first tap on a song must never dead-end into a download screen. Honest latency: a first tap on a never-fetched track can take 1–3 s to start while the box pulls it — shown, not hidden.
- Streamed bytes are cached on the phone (LRU, ~2 GB, separate from downloads): replaying a track reads from disk instead of fetching again. Eviction only costs a re-stream.

---

# 2. Architecture

Two zones, one daemon, one app.

```text
Telegram channels
      │  (MTProto, session on box)
      ▼
┌─────────────────────────────┐        LAN HTTP (+manifest)        ┌──────────────────────┐
│  tunesd (box daemon, TS)    │ ─────────────────────────────────► │  tunes app (Flutter) │
│  fetch → probe → tag →      │                                     │  library / search /  │
│  dedupe → manifest → serve  │ ◄─────────────────────────────────  │  queue / download /  │
│  R128 scan → cover store    │         sync + download requests    │  media_kit playback  │
└─────────────────────────────┘                                     └──────────────────────┘
```

## 2.1 tunesd (box)

TypeScript, sibling service to `tg-curator` — shares its MTProto/session/teleproto patterns but is a **separate service with a separate Telegram session** (ban isolation: a music crawl must never be able to nuke the curator's session, or vice versa).

Responsibilities:

1. **Fetch** — rate-limited, jittered, per-channel daily caps, resume-safe (interrupted download restarts, never re-downloads completed files; hash verified on completion). Two modes: bulk scan (jittered, cadence-limited) and **on-demand fetch** (user-initiated streaming — immediate, counts against the daily cap, never jittered: a human action, not a crawler pattern).
2. **Probe** — ffprobe every file: codec, bitrate, channels, sample rate, duration, tag completeness (all via child-process ffprobe; no hand-rolled parsers).
3. **Identity + normalize** — recording identity v1 = content sha256 + duration + normalized embedded tags + channel provenance. At this stage the only dedupe is exact-content (same sha, multiple channel sources → one object). Recording-level dedupe (different bytes, same song) is M4 work with a verified fingerprint — never claimed before it exists.
4. **Enrich** — MusicBrainz lookups (rate-limited, cached, offline-tolerant), cover extraction, caption/entity parsing for channels that post metadata in messages. Enrichment attaches relationships; it never changes identity (M2.5).
5. **Quality model** — multi-factor source-quality scoring from five recorded dimensions, not a codec table (see §5).
6. **Object store** — content-addressed storage: `objects/ab/abcdef…` keyed by sha256. Files reference objects; the concept of "local_path" as primary identity disappears. This buys corruption detection, interrupted-download resume, migrations, library moves, backups, and multiple channel sources pointing at the same bytes — for free, structurally.
7. **Manifest** — one JSON manifest per library state, checksummed, versioned. The app syncs the manifest, not the filesystem.
8. **R128 scan** — ebur128 measurement stored per track (scanner does it once; app applies gain at playback).
9. **Serve** — static file server for track bytes (stream + download) + manifest + art. LAN only, optional token auth (default: host-key pair shared at setup).

**Language note:** tunesd is TypeScript for M0–M4 — it borrows tg-curator's proven session/teleproto patterns and proves the architecture. It is a media-processing daemon and the long-lived source of truth, so a **Rust re-evaluation gate sits at M5**: only if filesystem/state/concurrency work earns it, never for speed's sake. The manifest JSON is the contract between daemon and app, so a future rewrite is isolated and app-invisible.

## 2.2 tunes app (Android, Flutter)

Mirrors Faye's stack patterns: drift/sqlite, Riverpod, strongly typed domain models, zero business logic in widgets.

- **media_kit (libmpv)** for playback — gapless, FLAC/Opus/MP3 native, resample at edge, correct sample-rate handling. (just_audio is the fallback if libmpv misbehaves on a device, but the spec target is media_kit.)
- Local sqlite mirrors the manifest: tracks/albums/artists/dupes + **FTS5** search index.
- Downloads write original bytes to app-owned storage (optional export to Music/ the user picks).
- All core flows work with the box offline if content is downloaded.

## 2.3 Why not in-app Telegram?

- TG session on the phone = phone owns ban risk + a 2nd session to babysit.
- The metadata moat (MusicBrainz, quality model, R128) is heavyweight infra that belongs on the box where tooling already exists (TS + ffprobe + mutagen).
- Phone stays thin, fast, and fully offline-capable.
- tunesd's API surface is ~4 endpoints; the app stays a polished client.

## 2.4 The endpoint surface is the contract (thin-client rule)

The app knows these endpoints and nothing else:

```text
GET    /manifest        library state (checksummed, versioned)
GET    /art/*           cover bytes
GET    /track/*         track bytes — downloads, original bytes only
GET    /t/*             track bytes — streams (DO + R2 + Telegram), same grant
POST   /download        mark a track for device download

POST   /auth/redeem     invite code → device enrolment + refresh token
POST   /auth/token      refresh token → short-lived access token
DELETE /auth/device/*   revoke one device
```

Any new capability requires a new endpoint, which requires a spec change. The app must never grow into another backend: no crawling, no tagging, no Telegram knowledge inside the app process. This boundary is what keeps the phone fast, thin, and ban-safe.

**Authentication is layered on top of this contract, not woven into it** (added 2026-09-08). The API routes carry a bearer access token. Media and artwork are fetched with a signed URL instead, because those bytes are fetched by mpv and by Android's notification loader — neither of which is the app's own HTTP client, and the notification loader cannot set headers at all.

**Media grants are single-object capabilities, and are not "short-lived" in the sense an access token is.** Their TTL must accommodate the client's eager playlist construction: `player.open(Playlist(...))` builds a `Media` for the whole queue at once and mpv resolves each URL only when playback reaches that item, so a grant minted at queue-open may not be fetched for hours. The TTL is therefore longer than the access-token TTL by design — currently **4 hours against 10 minutes** — and that gap is a deliberate compatibility tradeoff, not an oversight.

What bounds the damage is the *scope*, not the lifetime: one grant fetches one object, cannot be exchanged for a token, and reveals nothing about the library. A revoked device stops being *issued* grants immediately, because minting reads the database; only already-issued grants outlive a revocation.

The better long-term answer is a lazy grant obtained close to playback, which requires `trackUriFor` to become asynchronous and the player's playlist-index contract to change (`playAt` calls `player.jump(index)` against the queue index, and repeat-all loops mpv's own playlist). That is a player architecture improvement, not part of this migration.

The validating edge must never learn where the bytes came from. Its contract stops at *authenticate → authorize → mint a signed media URL → hand off to a media origin*. Whether that origin served a local object, an R2 bucket, or a fresh Telegram fetch is not its concern — that opacity is what lets the storage layer change underneath without touching auth.

---

# 3. Data model (v1)

```text
channels        id, tg_username/id, title, enabled, daily_cap, joined_at
objects         sha256, size, store_path, state(complete|partial), verified_at
files           id, channel_id, tg_msg_id, object_id, state(downloaded|partial|failed|dupe)
                probe: codec, bitrate, sample_rate, channels, duration_ms
                tags: title, artist, album, track, disc, year, genre, cover_embedded
tracks          id, content_sha, duration_ms, title, artists[], album
                recording_identity: v1 = sha+duration+normalized tags (M4: fingerprint-verified)
                musicbrainz_id (nullable, enrichment only — never canonical)
                quality_rank, canonical_object_id, dupe_object_ids[], r128_lufs, r128_peak
                added_at (v3: server-stamped on first-seen, sticky across re-syncs; clients sort Library by this)
albums          id, musicbrainz_release_id (nullable), title, artist, year, cover_id
sync_state      schema_version, last_manifest_sha, last_sync_at
downloads       track_id, status, local_path, added_at, size
```

Invariants:

- A `tracks` row has exactly one canonical object; dupes reference it, never the reverse.
- `musicbrainz_id` is a relationship, not an identity — same MBID ≠ same track.
- Quality rank is a single int derived from the five quality dimensions — deterministic, audit-explainable (see §5).
- Everything the app displays comes from the manifest or its mirror; the app never reads tags from raw files.

---

# 4. The fetch discipline (ban safety)

Telegram bans userbots that hammer. Non-negotiable:

- Dedicated session for tunesd (separate from tg-curator's).
- Per-channel rate limit + inter-download jitter (defaults: ~1 file / 8–15 s, cap ~1500 files/day across channels, all configurable).
- Download via MTProto media API with resume; never poll for new messages faster than the channel's natural cadence (default: incremental scan every 5–10 min).
- Daily cap enforced in-process AND by a health probe that can shut the service down (mirror tg-curator's health-monitor pattern: if the session throws transport errors, stop and report, never retry-hot).
- On-demand fetch (streaming) is exempt from jitter but **counts against the daily cap** — a human tapping play is low-frequency by nature; the cap still bounds the worst case.
- All fetch state persists; restarts resume, never duplicate.

---

# 5. Source-quality model (deterministic, multi-factor)

Rank computed once per file at probe time, stored, never re-derived. **One rank, five recorded dimensions** — no codec table masquerading as a quality judgement:

```text
D1 losslessness          codec is lossless AND bit-depth/sample-rate sane.
                         Does NOT imply the source was lossless.
D2 codec efficiency      family ranking only: FLAC/ALAC 95 · Opus 90 · AAC 85 · MP3 80 · other 70
D3 measured bitrate      ffprobe average over the whole file — never header claims
D4 provenance confidence low/medium/high: caption/entity claims, container claims vs measured
                         reality, release-era sanity, known channel behavior
D5 authenticity          suspected lossy→lossless transcode flag (spectral-cutoff heuristics
                         at scan: a FLAC with an abrupt ~16 kHz cutoff is "suspected MP3
                         source" and is marked, never silently promoted)
```

Ranking = versioned scoring table in tunesd (weight shape: losslessness bonus, efficiency + bitrate tier, provenance ±, authenticity malus). The spec fixes the dimensions and the invariants; exact weights live in a tested tuning table, versioned with the manifest.

Spec-mandated example outcome:

```text
FLAC 16/44.1, authenticity unknown, provenance low        → LOSES
320k MP3, known digital release, provenance high          → WINS
```

Lossless proves nothing. Every rank is audit-explainable: the app can show a track's dimension breakdown in one tap.

Two equal ranks resolving to the same recording: keep the lower sha256 (deterministic tiebreak — "trust nothing, verify everything").

Dedupe is **never destructive by default**. Marking, yes. Deleting dupe files only via explicit user action in the app ("keep best copy" flow, M4).

---

# 6. R128 loudness

Mechanics of principle §1.7 (files stay sacred):

- Scanner measures each canonical track once (ffmpeg `ebur128` filter, full-length scan: `-filter_complex ebur128`), stores `r128_lufs` + `r128_peak` (true peak).
- App applies gain at the playback edge: `target_lufs − track_lufs`, capped ±6 dB, no clipping (peak-aware).
- No files are ever rewritten for loudness. This is the difference between "premium" and "normalizing apps that re-encode."

---

# 7. App product surfaces (v1 flow)

Bottom navigation, music-player first:

### Library
The primary screen. Tabs: **Tracks / Albums / Artists / Channels**.

- Tracks sorted by added-to-library (newest first) — the collection grows, and growth should be visible.
- Search is FTS5, instant (typing filters the current tab; a search query can surface across tabs).
- Every list item shows: title, artist, album, quality badge (FLAC/320/etc.), availability (local / streamable), download state.

### Now Playing
- Full-screen ambient player: large art, seek (accurate), queue (up next / history), gapless stitching already handled by media_kit.
- Loudness-normalized by default with a plain "Flat" toggle in settings.
- Resume: playback position + queue survive restarts and app kills. Closing the
  app halts audio but keeps the queue; only an explicit stop abandons it.
- Radio: when the queue runs out with repeat off, the engine in `docs/RADIO.md`
  picks what follows from the listener's own history, on the device. The pick
  is appended after the queue, never mixed into it; a `Keep playing with radio`
  toggle turns it off, and offline it draws from downloads only.

### Queue
Persistent, reorderable, editable. "Play next", "add to queue", long-press → context menu on everything.

### Channels (settings area)
Source of truth list: which channels feed the library, caps, paused state. Not a social feed — a config screen.

### Downloads
Per-track and per-collection download to device; offline badge; storage usage; "remove downloaded copy" (original stays in library via manifest).

### Play semantics
Three-state model from §1.8: tap play on a downloaded track → plays instantly from device. Tap play on a streamable track → tunesd serves original bytes on demand; the box fetches from Telegram first if it doesn't hold the object yet (honest 1–3 s first-tap latency shown, never hidden). "Download this" is a background action from the same menus — it never blocks playback, and playback never requires a download decision.

---

# 8. Motion & visual direction (provisional — M5 branding)

- Dark, ambient, tonal scheme — music players live in the dark. Direction: deep neutral surfaces, one accent hue, Material You tonal spread (picker-derived), consistent with Dylan's existing taste (no earthy defaults, no pastel noise).
- Motion: calm, weighty, no gratuitous spring everywhere. Follow Faye's motion vocabulary thinking (micro 90–140 ms, transitions 220–320 ms).
- Typography: strong display for album/artist names; tabular numerals for durations.
- Now Playing is the visual identity anchor — it should look like a deliberate object, not a list row stretched full-screen.
- Final palette/type/motion spec lands with the real name at M5. Codename era = functional UI, no branding debt.

---

# 9. Testing strategy

Tests are a product feature here because a music library that lies about quality or duplicates is worthless.

## tunesd (vitest — mirror tg-curator)

- quality model: all five dimensions, weight-table paths, tiebreak determinism; identity: same-MBID-different-recordings stays separate
- dedupe: same MBID different quality → canonical kept; unknown-quality never silently promoted
- probe parse: real fixtures (FLAC/320/128/VBR Opus), no hand-rolled parser claims
- manifest: schema versioning, checksum integrity, resume semantics
- fetch: rate-limit math, daily cap enforcement, restart-without-dupes (state replay)
- ban-safety: transport-error → stop, probe verdicts

## app (dart test + widget + golden)

- manifest application: sync applies, idempotent re-sync, schema migration forward
- quality/identity display logic (pure Dart, zero Flutter imports)
- FTS5 query building, sorting determinism
- widget tests: Library tabs, search, Now Playing controls, queue reorder
- golden: Library, Now Playing, Album detail

## E2E (real, not simulated)

- `scripts/e2e-fetch.ts`: real channel fetch (synthetic-test channel, not a live piracy channel) → real files → manifest → sync into app → play 10 s → verify. Run before any M-release.
- App E2E on the real phone via wireless adb (`deploy.sh` loop below).

---

# 10. Build & release (Faye-style loop)

- This repo's dev box has 3.7 GB RAM: **APK/AAB builds run on GitHub Actions**, not locally. Gradle capped if local build is ever unavoidable.
- Debug signing: shared committed debug keystore (Faye pattern) so every CI runner + agent signs identically. Release signing in Actions secrets.
- CI per PR: format → analyze → unit tests → integration tests → build debug APK artifact.
- `tools/deploy.sh`: downloads newest CI debug APK → wireless adb install (`~/dev/platform-tools/platform-tools/adb`, mdns pairing, port changes per session) → launch.
- Channels: dev → beta → stable. Tags on `main` only, annotated `v0.x.y`. Versioning 0.x.y until 1.0.
- Every build exposes: version, build number, git commit, channel, schema version (debug screen).

Branches: `main` (always releasable) + `feat/*`, `fix/*`, `docs/*`, `chore/*`. Conventional commits. PRs merged by human. No Aestra-style ceremony here — loose, release-focused (fedha style).

---

# 11. Milestones

## M0 — Scaffold + foundations
- Repo layout: `tunesd/` (TS) + `app/` (Flutter) skeleton
- CI pipeline (analyze + tests + APK artifact), debug keystore, `tools/deploy.sh`
- Design tokens + motion vocabulary (provisional dark scheme)
- Done when: CI green on an empty-but-real app, deploy.sh installs it on the phone via wireless adb, a "hello library" screen renders

## M1 — tunesd fetch core
- Session + channel config, incremental scan, rate-limited resume-safe download, sha256 verify
- Health probe + transport-stop behavior (borrowed pattern from tg-curator's incident playbook)
- Done when: `scripts/e2e-fetch.ts` pulls a real synthetic channel end-to-end and a restart reproduces zero duplicate downloads

## M2 — Core pipeline (playable library, no enrichment debt)
- Probe → normalize → identity v1 (content sha + duration + normalized tags) → quality model → manifest v1 + integrity checks
- R128 scan
- Exact-content dedupe only (same sha, many sources → one object). **No recording-level dedupe claims at this stage** — that is M4 and it is not skipped.
- Done when: a mixed-quality fixture set ranks correctly per the five dimensions, manifest deterministic (same input → same manifest hash), and the result is *playable* — this is the milestone where the library becomes real

## M2.5 — Metadata enrichment
- MusicBrainz lookups (rate-limited, cached, offline-tolerant), covers, relationship recording, suspected-transcode flags surfaced
- Enrichment attaches; it never changes identity or rank
- Done when: enrichment applied to the same fixture set produces zero identity/rank changes, and offline runs are clean no-ops

## M3 — App v1 (play + stream + download)
- Sync manifest → drift mirror + FTS5 → Library tabs + instant search → queue → media_kit playback (gapless, R128 gain) → resume
- **Stream-first playback** (§1.8): tap play on an undownloaded track → tunesd on-demand fetch + stream of original bytes
- Per-track download to device; **launch-target measurement harness** (cold / warm / search p95, recorded on the real phone)
- Done when: E2E on the real phone via wireless adb — real library, first-tap streaming works, search < 100 ms p95, gapless across tracks, playback works with the box powered off (downloaded content), and the three launch numbers are recorded in the milestone report

## M4 — Deep identity + collections
- Recording-level dedupe with a verified content fingerprint (different bytes, same song → one canonical track); provisional identities from M2 get re-derived — same recording identity at v1 and v2 semantics
- "Keep best copy" explicit GC flow
- Smart collections (quality-filtered, dupe-management, channel mixes), playlist persistence, storage management UI
- Done when: a 2000+ track real library browses honestly at target speeds and every dupe/identity decision is explainable in UI

## M5 — Branding + 1.0 + Rust gate
- Real name, final palette/type/motion, icon, launcher polish
- Backup/export (library JSON + downloaded files), optional remote endpoint
- **Rust re-evaluation gate for tunesd**: rewrite only if filesystem/state/concurrency work earns it (manifest contract isolates the app either way)
- Done when: acceptance criteria below, and it feels like "my app" not "a script with a UI"

---

# 12. Acceptance criteria (1.0 gate)

- A real Telegram channel library syncs start-to-finish: fetch → probe → identity → quality → manifest → app, with a real E2E run logged
- Restarting tunesd mid-library never downloads a duplicate file (state replay proven)
- **Corruption detection**: a flipped byte in any stored object is detected at sync and repaired by re-fetch — library keeps playing
- Two files of the same recording at different quality resolve to one canonical track; the app shows *why* (dimension breakdown, one tap)
- **Streaming**: first tap on an undownloaded track plays without a download step; latency is honest, not hidden (real E2E run logged)
- Gapless playback across contiguous tracks; R128 keeps albums level; no file rewritten for loudness — ever
- Launch targets **measured, not assumed**: cold start < 1500 ms to first usable frame, warm start < 500 ms to usable library, search < 100 ms p95 — recorded on the M3 E2E phone, box on and box off
- Library fully usable with the box off (downloaded content)
- No analytics, no ads, no third-party trackers; the app talks to exactly two Tunes-operated destinations (auth service, media origin behind Cloudflare — §2.4) and never to Telegram
- Every device that can reach the library is one someone deliberately enrolled, and revoking it takes effect without touching any other device
- All quality-model and identity logic has deterministic unit tests
- CI green on every PR; `main` always produces a releasable build; `deploy.sh` installs on the phone
- Migrations are typed and tested; library data survives upgrades
- Sensitive/private path: no channel content, message IDs, or filenames in logs or crash output

The standard is not **"Does it work?"**

The standard is: **"Would Dylan keep this on his phone and open it before anything else when he wants music?"**

---

# 13. Non-goals (until they earn their way in)

- No public publishing, no store listing, no open "share by link". Sharing with a
  *named, enrolled* person is in scope as of 2026-09-08 — that is what the device
  registry and revocation exist for. What stays out of scope is anyone reaching the
  library without an account someone deliberately created for them.
- **No direct phone↔Telegram connection, ever** — "live pull" is always via tunesd; the phone cannot reach Telegram by construction
- No charts, no popularity ranking, no "listeners also enjoyed". Sequencing
  is allowed and specified in `docs/RADIO.md` (decision recorded 2026-09-08,
  superseding the blanket "no recommendation engine" this replaced) — but it
  runs on the listener's own play history, on their own device, and nothing
  about it leaves the phone. An explicit queue is never reordered by it.
- No podcasting, no video, no lyrics-first features
- No re-encoding anywhere in the default pipeline