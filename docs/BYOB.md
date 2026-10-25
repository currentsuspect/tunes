# Bring your own box (BYOB)

Status: proposed, 25 Oct 2026. Idea from Cedric; owner's call: own-only libraries to start.

## Why

Every account's searches and gets run on one machine, the owner's laptop. Soulseek gets therefore form a single queue,
and every friend's listening costs that laptop's disk, bandwidth and Soulseek account.

People who have their own machine run their own box instead:

- their gets and searches run on it, with no queue behind anyone else;
- under their own Soulseek account;
- into their own library, on their own disk.

People without a machine (Angel) keep using the owner's box, which stays the default.

## What stays the same

- **One front door.** `tunes.aestra.studio`, the `tunes-auth` Worker: sign-in, devices, sync, lyrics, the app's
  update check. Nobody else needs a Cloudflare account or a domain.
- **The app.** Same server address for everyone. It cannot tell which box answers.
- **Accounts and invites.** As today: an account in D1, one invite per device.
- **The cloud byte path** (`tunes-fetch`, R2 + Telegram) for songs that are in the shared archive.

## How it works

```
phone ──► tunes.aestra.studio (Worker: auth, then route by account)
             ├─ acct-angel, acct-dylan ──► owner's box   (tunnel: tunes.aestra.studio)
             ├─ acct-cedric            ──► Cedric's box  (tunnel: <name>-box.aestra.studio)
             └─ /t/<sha> (cloud path)  ──► tunes-fetch   (R2, else the shared Telegram archive)
```

### 1. A box is a tunnel the owner hands out

Each box gets a Cloudflare Tunnel created **in the owner's Cloudflare account**, with its own hostname
`<name>-box.aestra.studio`. One level under the zone, because the zone's free certificate covers `*.aestra.studio` only;
a `box.aestra.studio` level had no certificate, which the dry run found (25 Oct).

- The box owner receives one tunnel token and runs `cloudflared` with it.
- The box only dials out: no Cloudflare account, no domain, no open ports on their side.
- The owner can revoke a box by deleting its tunnel.

The Worker is also routed on `*-box.aestra.studio/*`, and it denies every direct request there. That is how the main
origin is protected today: the Worker owns the hostname, so the tunnel is never reached without a valid device token.
The Worker's own subrequests to a box hostname go through to the tunnel, as `fetch(req)` to `tunes.aestra.studio`
does today. *To verify in the dry run (phase 4) before any real box.*

### 2. The Worker routes by account

New D1 table:

```sql
CREATE TABLE box (
  id               TEXT PRIMARY KEY,           -- "cedric-box"
  account_id       TEXT NOT NULL UNIQUE REFERENCES account(id),
  publish_key_hash TEXT NOT NULL UNIQUE,       -- sha256 of the box's publish key
  status           TEXT NOT NULL DEFAULT 'active',
  created_at       INTEGER NOT NULL,
  last_publish_at  INTEGER
);
```

After the device token is verified, the account in its claims picks the origin:

- **Account has an active box:** the request goes to `https://<name>-box.aestra.studio`. The hostname is derived from the
  id, never stored, so no row can point a request at an arbitrary host. This covers everything the box answers
  today: the library (`/manifest`, `/changes`, `/search`, …), Soulseek (`/soulseek/*`), `/about/*`, `/tracklist`,
  `/discography`, and track bytes from the origin.
- **No box, or a disabled box:** the owner's box, exactly as today.
- **Never routed to a box:** `/auth/*`, `/sync/*`, `/lyrics*`, `/update*` and `/internal/*`. These stay central.

The box is looked up once, when the device gets its access token (`/auth/token`, which already reads the database),
and carried in the token's `box` claim. Signed `/track` and `/art` URLs carry it too, bound into the signature, so the
gate routes without a database read. `/t/` URLs never carry it: the cloud path is shared, and `tunes-fetch` verifies
those itself. A disabled box stops being used within one token lifetime (10 minutes), and within one media grant
(4 hours) for signed URLs already handed out.

> The byte path is the only part of the Worker that must not touch the database today. A routed origin needs the
> account first. The route is resolved from the token's claims before the stateless section, so that rule still holds
> below that point.

### 3. A box publishes its own library

The box keeps using `/internal/publish` and `/internal/manifest`, with its own publish key.

- The Worker finds the box by the key's hash.
- It stores the manifest at `boxes/<box-id>/manifest.json.gz` (and `-lean`) in R2.
- `GET /manifest` for an account with a box serves that key instead of the shared one.
- The sha→message rows go into `fetch_map` as today: they say where a song sits in Telegram, whoever uploaded it.

### 4. The shared Telegram archive

Every box uploads to **the same archive group**, the owner's existing archive chat. It is a group and everyone is
already a member, so posting needs no extra rights. Each box owner logs into Telegram with their own account (an API ID
and hash from my.telegram.org, then a one-time phone login on their own machine).

What that gives:

- **Unlimited storage for everyone**, with the box's disk only a cache (`TUNESD_CACHE_MAX_BYTES`), as on the owner's
  box since 17 Oct.
- **Songs keep playing when a box is off.** The cloud path serves any song that is in R2 or in the group, using the
  owner's session, and the box's published `fetch_map` rows tell it where.
- **Duplicates are harmless.** A box's archive dedupe (`needsArchive`) only knows its own library. If two people get
  the same song, each box uploads it once: two messages with the same sha. Telegram storage costs nothing, and the
  cloud path can use either copy.

Own-only is kept by what a box *scans*, not by what it uploads. A box sets `TUNESD_ARCHIVE_CHAT` and **does not read
the group**: the group is the owner's main source channel (Tunes Stream, ~49k messages), and reading it would pull
everyone's music into the box. tunesd counts the archive chat's copies it uploaded itself as live, without scanning
the chat (`sightingChats`, found by the 25 Oct dry run). A box's `TUNESD_CHANNELS` is only the channels its owner wants
as sources, usually none.

### 5. Optional: another storage area

The store directory is any path (`TUNESD_DATA_DIR`). A box owner who wants their files somewhere else can mount it
there:

- a second disk or a NAS;
- or a cloud drive through rclone. Backblaze B2 is well supported. TeraBox has no reliable rclone backend that we
  know of; check before relying on it.

Nothing in Tunes needs to change for this. The archive in Telegram stays the copy that counts; anything else is the
box owner's own convenience.

## What the box owner's agent does (BYOB guide)

[`docs/byob/AGENT.md`](byob/AGENT.md) is written for the box owner's own coding agent (Claude Code or similar), on their machine.
It tells the agent what to ask, what to install and how to prove it works.

**Ask the person:**

1. Their OS, and whether the machine stays on, or at least isn't asleep when they listen.
2. Where music should live and how much disk it may use (default: a 20 GB cache).
3. Their Soulseek username and password, or help them make an account. Entered on their machine only.
4. Their Telegram API ID and hash (the guide walks them through my.telegram.org), then the login code Telegram sends
   them. Entered on their machine only.
5. Which Telegram channels they want as sources, if any.

**The owner provides** (one bundle per box, like an invite):

- the box id, tunnel token and publish key;
- an invite into the archive group;
- the archive group's id.

**Install and wire:** tunesd (Node), slskd, cloudflared with the token, as services that start on boot. Fill in
tunesd's `.env`:

- `TUNESD_API_ID`, `TUNESD_API_HASH`;
- `TUNESD_ARCHIVE_CHAT`, `TUNESD_CHANNELS`;
- `INTERNAL_PUBLISH_URL`, `INTERNAL_PUBLISH_KEY`;
- `TUNESD_CACHE_MAX_BYTES`;
- the slskd address and key.

**Prove it:**

1. `GET localhost:4780/health` answers with the box's id, and the owner's `GET /internal/boxes/<id>/health` (service
   key, through the Worker) answers the same through the tunnel. Nothing else outside can reach a box.
2. The box's first publish lands (`last_publish_at` is set).
3. A test get from the person's phone arrives in their library.
4. The song is uploaded to the archive group.

**Report back** to the owner: box id, versions, and that all four checks passed.

**The agent never:**

- sends a password, API hash, session or key to the owner or into a chat;
- touches the owner's Cloudflare account;
- shares the person's music folder on Soulseek. slskd is set to download only, as on the owner's box.

## What the owner does per box

A script, `scripts/byob/new-box.sh <account-id>`, which:

1. creates the tunnel and its DNS name;
2. makes a publish key and stores only its hash in `box`;
3. prints the bundle (tunnel token, publish key, archive group id) to hand over.

`disable-box.sh <box-id>` turns routing back to the owner's box and deletes the tunnel.

## Failure and trust

- **Box offline:** that account's library requests fail and the app shows it as unreachable. Songs in R2 or the
  archive still play through the cloud path. No fallback to the owner's library: it isn't theirs, and showing it would
  be wrong.
- **What a box owner trusts:** the owner's Worker reaches their box. A bug there could reach it too, so they're trusting
  the owner as much as the owner's friends already do.
- **What the owner trusts:** a box can only publish its own manifest (keyed by its publish key) and can only post in the
  archive group. It can't touch D1 or other boxes.
- **Soulseek** runs under each box owner's own account and name, with their own exposure. Say so plainly before they
  start.

### 6. Spreading the load

The owner's box does everything today: fetching, Soulseek, lyrics, enrichment. With BYOB each box does that work for
its own library only:

- **Its own Telegram budget.** Each box has its own session, so its fetch limits (`TUNESD_FETCH_DELAY_MS`,
  `TUNESD_FETCH_DAILY_CAP`) are its own and can be set higher than the owner's box uses, since no single session
  carries everyone's library any more.
- **Its own lyrics and metadata.** The box sources lyrics for its own songs. Lyrics land in the shared D1 `lyrics`
  table as today, so a lyric one box finds serves everyone. Metadata: the box owner's own Last.fm key
  (`TUNESD_LASTFM_KEY`, free from last.fm/api) or none. Discogs and Spotify stay on the owner's box.

## Phases

1. **Worker and box:** tunesd's `/health`, the `box` table and migration, routing by account, the `*-box.aestra.studio` deny route, per-box
   publish and the per-box `/manifest`. Tests with a fake second origin.
2. **Owner tooling:** `new-box.sh`, `disable-box.sh`.
3. **The agent guide** `docs/byob/AGENT.md`, for Linux and macOS: Dennis is on Linux (and Windows) and Cedric on macOS.
   On macOS that means launchd services instead of systemd. tunesd and slskd themselves run there unchanged
   (Node, .NET). Windows comes after.
4. **Dry run on this machine:** a throwaway account and a second tunesd on another port, behind a second tunnel.
   Prove the routing, the deny on the box hostname, publish, a get and an archive upload, then disable it. Done
   following the guide, with an agent, as a box owner would.
5. **First real box:** Cedric.

## Not now

- **Merged libraries** (seeing other boxes' songs). The routing table and the per-box manifests leave room for a merged
  manifest later; nothing here blocks it.
- **Friends with their own Cloudflare.** One account with many tunnels is simpler and free at this size.
- **Moving the owner's own box** into the `box` table. It stays the default origin.

## Decided (25 Oct)

- **Platforms:** Cedric is on macOS; Dennis is on Linux and Windows. The guide covers Linux and macOS first.
- **Archive:** it is a group, and everyone is already a member.
- **Rates:** per-box fetch limits may be raised, since the load is spread.
- **Metadata:** each box uses its owner's own Last.fm key, or none.
