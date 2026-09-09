# Radio — session-aware sequencing

Owner's spec, 2026-09-07. Imported into the repo 2026-09-08; it previously
existed only in an agent memory file, where `git grep` could not find it and
two separate sessions failed to locate it.

Supersedes the SPEC §13 non-goal "No recommendation engine, no charts, no
'because you listened to'" — see §5 below for what that non-goal was
protecting and why the replacement keeps it.

---

## 1. The reframe

Not `track → recommended track`. **`session → next track`.**

Two things that are not the same, and the whole design turns on separating
them:

- **Recommendation relevance** — "would Dylan like this?"
- **Sequence relevance** — "would Dylan want this *right now*?"

A 10/10 song can be a terrible next song. That gap is the difference between a
recommender and a DJ.

## 2. Session state

Small, real-time, held in memory:

last 20 tracks · last 10 artists · last 5 genres · current energy · mood ·
current album · recent skips · recent completions · recent discoveries ·
**exploration level**

## 3. Track "music DNA"

Precomputed over the whole library:

audio embedding · genre vector · artist · producers · era · bpm · key · energy
· danceability · valence · acousticness · instrumentation · vocal character ·
production style · similarity neighbours

The audio embedding matters most: it finds relationships metadata cannot
(A$AP Rocky → Clams Casino production texture → Kid Cudi → Tame Impala — not
the same genre, adjacent musical territory).

## 4. Three candidate generators

1. **Sound similarity** — audio embeddings, nearest neighbours
2. **Relationship graph** — artist, producer, label, genre, era, collaborators,
   samples, features
3. **Listening behaviour** — played / completed / skipped / replayed / queued,
   and "played after X" co-occurrence

### Ranking

```
score = musical_fit + session_fit + taste_fit + transition_quality
      + novelty + relationship_strength
      - repetition_penalty - recent_artist_penalty
      - recent_track_penalty - overfamiliarity_penalty
```

**Weights shift with position in the session.** After three tracks by one act:
artist-similarity down, sound-similarity up, related-artist up, novelty up.
After drifting across five artists: artist-similarity back up. That shift is
what makes the wander feel deliberate.

### The wander

Sample near at first. Each accepted transition widens the radius; a skip
narrows it. Let a far track play to completion and the next session may go
further.

**Deliberately don't always take the top score.** Given 0.94 / 0.93 / 0.92 /
0.91, sometimes take 0.91 — otherwise the system converges on one loop and
starts feeling algorithmic.

### Album integrity

Album finishing is a *state*, not another signal. When it ends, choose a
**departure**: same artist / same producer / same sound / same genre / related
artist / controlled wildcard, weighted by session state. The first track after
an album should read as the next chapter.

### One radio, not radio modes

No "Radio: Similar / Artist / Genre" picker. One intelligent radio. Internally
it knows the mix (42% sonic, 21% producer, 17% history, 11% artist, 6% genre,
3% exploration); the listener only experiences "this is exactly what I wanted
next".

## 5. What the old non-goal was protecting, and how this keeps it

SPEC §13 ruled out a recommendation engine. That was never about the maths —
it was about three things worth keeping:

- **Nothing leaves the device.** Sequencing runs on the listener's own play
  history, on the phone. No profile is uploaded, nothing is shared across
  accounts, and there is no "listeners also enjoyed".
- **No charts, no popularity.** The library is one person's. Ranking by what
  is popular anywhere else is meaningless here and is not implemented.
- **The listener stays in charge.** Radio is a thing you start, not a thing
  that happens to your queue. An explicit queue is never reordered by it.

A design that breaks any of those is out of scope regardless of how well it
sequences.

## 6. Honest gaps

Measured against the real library, not assumed:

- **Play history exists** (schema `PlayEvents`, since 2026-09-06: sha,
  startedAt, listenedMs, durationMs, completed) with `recentShas`, `topShas`,
  `listenAgainShas`, `playCounts`, `skipCounts` already derived. This is the
  one generator with substrate today.
- **No audio embeddings exist.** Nothing computes or stores them. This is the
  largest single piece of work and it needs server-side compute.
- **Producer / label / collaborator data does not exist.** 483 files carry only
  title/artist/album/year/track/disc, genre on 471, albumArtist on 345. The
  relationship graph has no edges to walk until daemon-side tag extraction and
  MusicBrainz enrichment fill them in.

## 7. Build order

1. **Behaviour-only sequencing, pure Dart, on device.** Generator 3 alone,
   against the existing play history and manifest metadata, with the scoring
   function shaped to accept the other two later. Ships without any new
   infrastructure.
2. **Relationship graph.** Daemon-side extraction populates producers, labels
   and collaborators; generator 2 becomes possible.
3. **Audio embeddings.** Server-side compute, stored per track; generator 1
   becomes possible and the weights start meaning what §4 describes.

Sequencing quality at step 1 will not match §4. That is expected: the point of
step 1 is the session model and the ranking seam, not the final mix.
