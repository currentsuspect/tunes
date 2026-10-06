# Account sync

What follows a listener from device to device, and how.

## What syncs

| Key | What it is | Notes |
| --- | --- | --- |
| `like:<sha>` | a heart | unliking is the document going away (a tombstone) |
| `playlist:<uuid>` | a playlist: name, creation time, ordered shas | one document per playlist; matched across devices by `playlists.sync_id` |
| `edit:<sha>:<field>` | a corrected title, artist, album or year | lyrics are **not** here, they are shared through the daemon |
| `profile` | the name in the greeting | |
| `now` | where the music is: sha, queue index, position, playing | read, not merged: the device that played last is "now playing" |
| `queue` | the shas queued on that device | pushed only when the queue changes |
| `plays:<device>:<yyyymmdd>` | that device's listens for one UTC day | written only by the device that listened; others store them marked by origin and never resend. Switchable per device (Settings > Share what I listen to) |

Not synced: settings, downloads (a device holds only what it downloaded), avatar.

## How

The Worker (`edge/src/sync.ts`) keeps one row per (account, key) in D1 table
`sync_doc`. Two routes, both behind the normal bearer token; the account is the
token's `sub` and nothing else:

- `POST /sync/push` `{docs:[{key,value,deleted,updatedAt}]}` keeps the newest
  write per key (by `updatedAt`) and numbers every accepted change with a
  per-account `seq`.
- `GET /sync/pull?after=<seq>` returns everything newer, 500 at a time, with
  the device names so "Playing on Laptop" needs no second call.

A device that was off for a month catches up in one request, and a new device
that enrols into the account pulls from `after=0`.

The app (`app/lib/core/sync/`) is **state-based**: nothing hooks into the
stores' write paths. Each round it snapshots what is on the device, compares it
with what the server last agreed to (marks kept in `sync_state`), pushes the
difference, then pulls and applies what other devices decided. Push comes
first so the server settles conflicts before anything is applied. Offline is
free: the difference is just bigger next time.

Rounds run on start, on returning to the foreground, when the network comes
back, a few seconds after a like or playlist change, and every 30 seconds
while open. While music plays the device reports `now` every 15 seconds.

## Live view and remote control

While anything is playing the devices behave as one listener:

- **Live view.** The playing device reports `now` on every play, pause, skip or
  seek and every 8 seconds, with `since` (when this stretch of playing began).
  A device that is silent while another is playing shows that music in its
  player (`ConnectPlayer`): the track, a playhead that keeps moving, "playing
  on Phone", and nothing plays here. A paused session stays on screen for 3
  minutes so a pause from here can be undone from here.
- **Remote control.** Pause, play, seek, skip and jump-to in the queue become a
  `cmd` document addressed to the playing device (`{id, to, action, ...}`);
  that device polls, runs it once if it is under 20 seconds old, and reports
  its new state. The screen shows the new state at once (optimistic) until the
  report arrives.
- **One at a time.** Choosing music on a device plays it there, and the other
  device stops: when a device sees another playing with a later `since` than
  its own, it pauses itself. Tapping "playing on ... · play here" carries the
  music over from the same second.
- **The fast lane.** `GET /sync/pull?after=<n>&only=live` returns only `now`,
  `queue` and `cmd`. A device polls it every 1.5 s while music is in play (here
  or elsewhere) and every 5 s otherwise, only in the foreground. Expect about
  1-3 seconds between a button press and the other device reacting. A device
  whose app is closed cannot be commanded: the view stops after 45 seconds
  without a report.

History, resume position and the notification are about **this** device's own
listening and are attached to the local player underneath, never to the view.

## Clocks

`updatedAt` is the device's clock corrected by how far it was last found to be
from the server's (every response carries the server's time). The first push
from a device before it has learned the offset uses its own clock. The server
also clamps a time more than a minute in the future, so one wrong clock cannot
win every conflict for ever.

## Limits (on purpose)

- Two devices changing the **same playlist** within one sync interval keep the
  later change and lose the other. A whole playlist is one document; there is
  no merge.
- `now` is a display, not a remote control: nothing on one device makes
  another play.
- A document is at most 256 KB, a push at most 200 documents, a queue at most
  500 tracks.

## Deploy

The live Worker is the `deploy-edge` line (R2 audio), not `main`. The sync
routes are on branch `deploy/edge-sync` (worktree `~/Dev/tunes-edge-sync`).
The table is additive: apply `migrations/0005_sync.sql` to `tunes-auth`
first, then `npx wrangler deploy`. Rolling back the Worker leaves the table
unused and harmless.
