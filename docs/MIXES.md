# Mixes — playlists the app makes, and records you have not opened

Owner's direction, 2026-10-05. Recorded in `docs/SPEC.md` §13, which it extends
(the radio decision of 2026-09-08 allowed on-device sequencing; this allows
on-device playlists on the same terms).

## What it is for

Tunes is a mirror of how you listen, not a showcase. It should notice what you
play on a Friday, what you play after midnight, which artists you love and have
not finished, and which records you own and never opened, and say so plainly. The
library is yours; the point is to find more of it.

## Rules that do not bend

- **Your own data only.** The library, the listening history, your likes, and the
  artist tags the box already fetched. No charts, no popularity, nobody else's
  listening, nothing sent anywhere. It runs on the phone.
- **Hide when thin.** A mix with fewer than 15 songs, or a rail with fewer than 3
  records, is not drawn. Nothing is invented to fill a shelf.
- **Say why.** Every mix carries one sentence naming what it was built from
  ("What you play on Fridays, and the songs you love"). When the history for the
  day is thin it says it fell back to what you play and love most.
- **Stable, then fresh.** A mix is the same list all day (time-of-day mixes) or all
  week (weekday and genre mixes), and a different order next time. Opening it twice
  never changes it under you.
- **Yours to keep.** A mix is read-only because it is rebuilt from how you listen.
  *Save as playlist* copies its songs into a real playlist you can change.
- **Never touches the queue.** Nothing here reorders something you queued.

## Phase 1 (built)

Pure rules in `app/lib/domain/mixes.dart`, tested at fixed times in
`app/test/mixes_test.dart`.

| Mix | Shown | Built from |
| --- | --- | --- |
| Feel Good Friday, Saturday Night, Sunday Sessions, Monday Reset, Tuesday/Wednesday/Thursday Mix | on that weekday | plays on that weekday ×3, total plays, hearted ×4 |
| Late Night | 21:00–04:00 | plays between 22:00 and 04:00 |
| Morning | 05:00–12:00 | plays between 05:00 and 11:00 |
| Deep Cuts | always, if there is enough | never-played songs by your six most-played artists |
| One lane per kind of music (up to two) | always, if there is enough | the box's crowd tags on your artists; spellings of one tag are one lane; vague tags ("seen live", "american") are ignored |

At most three songs from one artist in a mix, 30 songs long.

**Albums you have not heard** (Home, "Unheard in your library"): records with at
least three songs and no play of any of them, ranked by how recently added, how much
you play that artist, whether a song on it is hearted, and a daily shuffle so it is
not the same shelf every day. Each says why ("Added 3 days ago, not played").

Artist tags travel in the manifest (`artists[].tags`) and are kept on the phone
(drift schema 10, `Artists.tagsJson`). Play times come from
`PlayHistory.playStamps`.

## Phase 2 (not built): sound

The library has no audio analysis yet. The plan is for the box to measure each file
once, keyed by its sha, and send the numbers in the manifest:

- loudness and dynamics (ffmpeg `ebur128`, `astats`)
- brightness and noisiness (`aspectralstats`: centroid, rolloff, flatness)
- tempo, probably through aubio, if it can be installed on the box

Mixes then use them ("Feel Good" can lean upbeat and bright, "Late Night" quiet and
dark). Measuring sound says a song is fast and bright, not that it makes you feel
good; the better signal for mood stays your own behaviour. This also feeds the
"music DNA" in `docs/RADIO.md`.

## Phase 3 (not built): how you listen

A page that shows it back to you: hours and days you listen, the kinds of music,
how much of what you play is new against familiar.
