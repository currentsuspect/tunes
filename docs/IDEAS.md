# Ideas

Things worth building that are not built. Not a roadmap: nothing here is
promised, and each needs a spec change (SPEC §2.4) before it is code if it
touches the endpoint surface. Ordered roughly by how soon they pay back.

Recorded 2026-10-05, after the redesign and Birthday Pack.

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
