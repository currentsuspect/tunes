/**
 * Lyrics, fetched once by the daemon and served to every phone.
 *
 * Until now `lyrics` was hardcoded null in the manifest and the only way a
 * lyric existed was somebody typing it into their own phone — where it stayed,
 * because the app stores edits locally. Two people with the same library saw
 * different lyrics, and a reinstall lost them.
 *
 * LRCLIB is the source: free, no key, no account, and it answers on exactly
 * the fields a library already has.
 */

export interface LyricsResult {
  /** LRC text with line timestamps, or null when only plain text exists. */
  synced: string | null;
  /** Untimed words. Worth having: it is the difference between "no lyrics" and "lyrics you cannot follow". */
  plain: string | null;
  /** The LRCLIB record this came from, so a bad match can be re-picked rather than re-guessed. */
  id: number | null;
}

export interface LyricsCandidate {
  id: number;
  trackName: string;
  artistName: string;
  albumName: string;
  /** Seconds, as LRCLIB reports it. */
  duration: number;
  instrumental: boolean;
  plainLyrics: string | null;
  syncedLyrics: string | null;
}

/** How far a candidate's duration may sit from ours and still be the same recording. */
export const kDurationToleranceSec = 3;

function norm(s: string): string {
  return s
    .toLowerCase()
    .replace(/\(.*?\)|\[.*?\]/g, " ")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

/**
 * Picks the best candidate for a track we hold.
 *
 * Duration is the discriminator, not title and artist. A search for one track
 * returns many rows — twenty for a popular single — whose album names do not
 * separate them ("Instrumentals", "[Physical version CD]", "Test Pressing"),
 * and whose timings genuinely differ. Picking by name alone lands on a version
 * whose lyrics run half a second early for the whole song, which is worse than
 * having none: it looks like the app is broken rather than like the data is
 * wrong.
 *
 * Preference order, once inside the duration window:
 *   1. synced lyrics over plain — the whole point is following along
 *   2. closest duration — the recording we actually hold
 *
 * Instrumentals are rejected outright. An instrumental with "lyrics" attached
 * is a mismatch by definition.
 */
export function bestLyricsMatch(
  candidates: LyricsCandidate[],
  ours: { title: string; artist: string; durationMs: number | null },
): LyricsCandidate | null {
  if (!Array.isArray(candidates) || candidates.length === 0) return null;
  const ourTitle = norm(ours.title);
  const ourSec = ours.durationMs === null ? null : ours.durationMs / 1000;

  const viable = candidates.filter((c) => {
    if (!c || c.instrumental) return false;
    if (!c.syncedLyrics && !c.plainLyrics) return false;
    // Title has to be recognisably the same song. LRCLIB search is fuzzy
    // enough to return neighbours, and a neighbour with a matching duration
    // would otherwise win on the tie-break below.
    const t = norm(c.trackName ?? "");
    if (t !== ourTitle && !t.includes(ourTitle) && !ourTitle.includes(t)) {
      return false;
    }
    if (ourSec === null) return true;
    return Math.abs((c.duration ?? 0) - ourSec) <= kDurationToleranceSec;
  });
  if (viable.length === 0) return null;

  viable.sort((a, b) => {
    const aSynced = a.syncedLyrics ? 0 : 1;
    const bSynced = b.syncedLyrics ? 0 : 1;
    if (aSynced !== bSynced) return aSynced - bSynced;
    if (ourSec === null) return 0;
    return (
      Math.abs((a.duration ?? 0) - ourSec) - Math.abs((b.duration ?? 0) - ourSec)
    );
  });
  return viable[0] ?? null;
}

/** Turns a chosen candidate into what the manifest stores. */
export function toResult(c: LyricsCandidate | null): LyricsResult | null {
  if (!c) return null;
  const synced = c.syncedLyrics?.trim() || null;
  const plain = c.plainLyrics?.trim() || null;
  if (!synced && !plain) return null;
  return { synced, plain, id: c.id ?? null };
}

export class LyricsUnavailable extends Error {}

export class LrclibClient {
  constructor(
    private readonly fetcher: typeof fetch = fetch,
    private readonly userAgent = "tunesd (https://github.com/currentsuspect/tunes)",
  ) {}

  /**
   * Looks a track up. Returns null when nothing matches, and throws
   * [LyricsUnavailable] when LRCLIB itself is unreachable.
   *
   * The distinction matters to the caller: "no lyrics exist" should be
   * remembered so the track is not asked about again for a while, while "the
   * service was down" should not be, or an outage permanently marks a library
   * as lyric-less.
   */
  async find(ours: {
    title: string;
    artist: string;
    album: string;
    durationMs: number | null;
  }): Promise<LyricsResult | null> {
    const params = new URLSearchParams({
      track_name: ours.title,
      artist_name: ours.artist,
    });
    let res: Response;
    try {
      res = await this.fetcher(`https://lrclib.net/api/search?${params}`, {
        headers: { "User-Agent": this.userAgent },
      });
    } catch (e) {
      throw new LyricsUnavailable(String(e));
    }
    if (res.status === 404) return null;
    if (!res.ok) throw new LyricsUnavailable(`lrclib ${res.status}`);
    const rows = (await res.json()) as LyricsCandidate[];
    return toResult(bestLyricsMatch(rows, ours));
  }
}
