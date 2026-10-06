# Ideas

Things worth building that are not built. Not a roadmap: nothing here is
promised, and each needs a spec change (SPEC §2.4) before it is code if it
touches the endpoint surface. Ordered roughly by how soon they pay back.

Recorded 2026-10-05, after the redesign and Birthday Pack.

## What is next (updated 2026-10-07)

**Done since this was first written (2026-10-05):** account sync, built on the
edge (D1) rather than the daemon, so it works for any new device and with the box
off. Likes, playlists, title edits, name, listening history (switchable), where
the music is, live view and remote control between devices. See `docs/SYNC.md`.
The desktop app now has its own layout (sidebar, bottom player, keyboard).

**In this order:**

1. **Firebase push**, so the phone can be controlled when its app is closed. A
   Firebase project, `google-services.json`, and a service-account key kept as a
   Worker secret. The Worker sends a high-priority message when a command is not
   answered; Android wakes the app to run it. Cannot wake an app the user has
   force-stopped.
2. **Soulseek as a provider** (slskd, not Navidrome): search, rank, download to
   staging, tag and de-duplicate (tag-normalizer), upload to Telegram, manifest.
   A one-tap "get this" on Discover's missing-albums rail. Search benchmark on
   the real library (2026-10-07, `docs/soulseek-bench-2026-10-07.jsonl`): a full
   copy for 66% of 50 albums, 91% of the regional/Afrobeats ones; nearly every
   miss was a SoundCloud-scale artist. The network filters some exact phrases and
   searches are flaky, so the provider retries with name variants. Download speed
   is not measured yet. Soulseek is peer to peer and shares by default.
3. **A model on our own data**: a pretrained audio encoder run once per track on
   the box, plus a small per-listener head trained on plays and skips. For radio,
   mixes, skip prediction and mis-tag detection; judged on the real history with a
   simulator first. Nothing generative or trained from scratch (too little data).
   Reuses the audio analysis the Soulseek ingest step produces.

**Still wanted:**

- **A radio that stays out of the echo chamber.** Gaps: the genre lane makes it
  stickier, taste counts all-time plays so favourites lock in, discovery is not
  guaranteed at low reach, the dial is buried on Discover, and "further out" does
  not mean a neighbouring genre. Plan, about 1.5 to 2 days: three quick modes in
  the player (Stay close, Drift, Surprise me), a reserved stretch slot of about
  one pick in five from outside the lane, fading old taste, then neighbouring
  genres from tag co-occurrence. Measure it with a simulator over the real
  manifest.
- **A web version at tunes.aestra.studio** (about 1 to 1.5 weeks). The Worker
  owns the hostname and signed media URLs work from a browser. The app has native
  audio (mpv), local SQLite and dart:io in 14 files, so it needs a browser audio
  backend and a web database. Sync now exists, so it would not be read-only.
- **Desktop polish:** hover states on cards, right-click beyond track rows.

## Before wide release

- **Crash and log reporting.** An opt-in "send log" in Settings that shares the
  app's own diagnostic log (`DiagLog`). When it breaks on someone else's phone,
  the owner currently hears about it second-hand.
- **Storage view.** What the cache and downloads take, with a clear button, so
  nobody needs a settings hunt to free space.

## How it feels to listen

- **How you listen** (mixes phase 3, `docs/MIXES.md`). Hours and days, kinds of
  music, new against familiar, top artists, shown back to the listener. The
  data is already on the phone.
- **Sound analysis for mixes** (mixes phase 2). Loudness, brightness and tempo
  from the box, so "Late Night" and "Feel Good" use the sound as well as the
  listening. Needs the analysis service in tunesd.
- **A radio that explains itself.** The familiar-to-further-out dial gives
  control; a single line ("because you played X twice this week") would make the
  choices feel personal and not random.
- **Per-tab back stacks.** Switching tab currently drops that tab's history.

## Together

- **Collaborative playlists.** A playlist several enrolled people can add to.
  This needs playlists to live somewhere shared; today they are on the phone.
- **Share a snippet.** Send a link that opens in the app and plays a chosen
  slice of a song, with the start and end picked on the waveform, so a
  listener can pass on exactly the part that carries the vibe. Pairs with
  pinning a lyric line.
- **Share to.** Hand a track, album or snippet to another app through the
  system share sheet, as a link that works for an enrolled friend.
- **Pin a line.** Pin and share a lyric line, with a card.

## Look

- **Theming.** Beyond the cover-lit default: a few named rooms (ink, paper,
  ember) and an option to hold one colour instead of following the record.
