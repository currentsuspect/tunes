import { appendFile, mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import type { ChainAnswer, FetchedSource, FoundLyrics, LyricTiming, Ours } from "./lyricsources.js";

/**
 * Where lyrics live, so that one person adding them is everyone having them.
 *
 * Until now a lyric existed only because somebody typed it into their own
 * phone, where it stayed. Two people with the same library saw different
 * lyrics and a reinstall lost them. The matcher in lyrics.ts was merged but
 * never connected to anything, and the manifest emitted `lyrics: null` for
 * every track.
 *
 * One record per track:
 *   - `user`   typed or pasted by a listener. Wins over everything, and is
 *              never replaced by a fetch.
 *   - `lrclib` found by the daemon, matched on duration.
 *   - `none`   LRCLIB had nothing. Remembered for a while so the track is not
 *              asked about every pass, and asked again later: a song can be
 *              added to LRCLIB tomorrow.
 *
 * "Nothing exists" and "the service was down" are different outcomes. Only the
 * first is recorded: an outage must not mark a library as lyric-less.
 */
export type LyricSource = "user" | FetchedSource | "none";

/** Which set of sources a record was looked up with. Raised when sources are
 * added, so songs that had nothing, or only line timing, are asked again. 2:
 * NetEase (word-timed YRC) and Genius joined LRCLIB, 24 Oct. */
export const kLyricChain = 2;

export interface LyricRecord {
  /** The words, with timestamps when LRCLIB had them. Null for `none`. */
  text: string | null;
  source: LyricSource;
  /** The LRCLIB row this came from, so a wrong match can be excluded. */
  lrclibId: number | null;
  /** When the words last changed. What /changes reports against. */
  updatedAt: string;
  /** When LRCLIB was last asked. */
  checkedAt: string | null;
  /** How finely the words are timed. Absent on records from before 24 Oct. */
  timing?: LyricTiming;
  /** The source's own id for the song (any source; lrclibId predates it). */
  sourceId?: string | null;
  /** [kLyricChain] at the last lookup; absent means 1, LRCLIB alone. */
  chain?: number;
}

interface LyricFile {
  schema: 1;
  tracks: Record<string, LyricRecord>;
}

/** A song LRCLIB had nothing for is asked about again after this long. */
export const kRetryNoneAfterMs = 7 * 24 * 60 * 60 * 1000;

/** Larger than any real lyric by a wide margin; a bound, not a target. */
export const kMaxLyricChars = 64 * 1024;

export class LyricStore {
  private data: LyricFile = { schema: 1, tracks: {} };
  private writing: Promise<void> = Promise.resolve();

  constructor(private readonly path: string) {}

  async load(): Promise<LyricStore> {
    try {
      const raw = JSON.parse(await readFile(this.path, "utf8")) as LyricFile;
      if (raw.schema === 1 && raw.tracks && typeof raw.tracks === "object") {
        this.data = raw;
      }
    } catch {
      // A fresh store. A corrupt file is not repaired here: it is replaced on
      // the next write, and what it held is re-fetched.
    }
    return this;
  }

  get(sha: string): LyricRecord | null {
    return this.data.tracks[sha] ?? null;
  }

  /** sha -> the words and where they came from, for the manifest. */
  forManifest(): Map<string, { lyrics: string; source: Exclude<LyricSource, "none"> }> {
    const out = new Map<string, { lyrics: string; source: Exclude<LyricSource, "none"> }>();
    for (const [sha, r] of Object.entries(this.data.tracks)) {
      if (r.text && r.source !== "none") {
        out.set(sha, { lyrics: r.text, source: r.source });
      }
    }
    return out;
  }

  /** Shas whose words changed after [since], oldest first. */
  changedSince(since: number): string[] {
    return Object.entries(this.data.tracks)
      .filter(([, r]) => r.text !== null && Date.parse(r.updatedAt) > since)
      .sort((a, b) => a[1].updatedAt.localeCompare(b[1].updatedAt))
      .map(([sha]) => sha);
  }

  /**
   * A listener's lyrics. Empty text takes the listener's version away, so the
   * track goes back to whatever LRCLIB has (or nothing).
   */
  async setUser(sha: string, text: string, now = new Date()): Promise<void> {
    const clean = text.replace(/\r\n/g, "\n").trim();
    const stamp = now.toISOString();
    if (clean === "") {
      delete this.data.tracks[sha];
    } else {
      this.data.tracks[sha] = {
        text: clean,
        source: "user",
        lrclibId: null,
        updatedAt: stamp,
        checkedAt: null,
      };
    }
    await this.persist();
    // A listener's own timing is the best label a timing model can learn
    // from, so every save is kept, not only the latest.
    await this.archive(sha, { kind: "user", at: stamp, text: clean });
  }

  /** What a lookup found. Never replaces a listener's version, and never
   * swaps finer timing for coarser: an upgrade pass that finds only what the
   * song already has leaves it as it is. */
  async setFetched(sha: string, found: FoundLyrics | null, now = new Date()): Promise<void> {
    const have = this.data.tracks[sha];
    if (have?.source === "user") return;
    const stamp = now.toISOString();
    const rank = (t: LyricTiming | undefined) => (t === "word" ? 2 : t === "line" ? 1 : 0);
    const haveTiming = have?.timing ?? (have?.text ? (/^\[\d+:\d/m.test(have.text) ? "line" : "plain") : undefined);
    if (found && have?.text && rank(found.timing) < rank(haveTiming)) found = null;
    if (!found && have?.text) {
      this.data.tracks[sha] = { ...have, timing: haveTiming, checkedAt: stamp, chain: kLyricChain };
    } else if (found) {
      const same = have?.text === found.text;
      this.data.tracks[sha] = {
        text: found.text,
        source: found.source,
        lrclibId: found.source === "lrclib" && found.id ? Number(found.id) : null,
        sourceId: found.id,
        timing: found.timing,
        // Unchanged words are not a change for anyone.
        updatedAt: same && have ? have.updatedAt : stamp,
        checkedAt: stamp,
        chain: kLyricChain,
      };
      if (!same) await this.archive(sha, { kind: found.source, at: stamp, timing: found.timing, id: found.id, raw: found.raw });
    } else {
      this.data.tracks[sha] = {
        text: null,
        source: "none",
        lrclibId: null,
        // Nothing changed for anyone, so this is not a change.
        updatedAt: have?.updatedAt ?? stamp,
        checkedAt: stamp,
        chain: kLyricChain,
      };
    }
    await this.persist();
  }

  /**
   * Whether to ask now, and how urgently: 0 for a song with no words, 1 for
   * one whose words could be timed more finely by sources added since it was
   * last asked, null for no.
   */
  lookupPriority(sha: string, now = Date.now()): 0 | 1 | null {
    const r = this.data.tracks[sha];
    if (!r) return 0;
    if (r.source === "user") return null;
    const older = (r.chain ?? 1) < kLyricChain;
    if (r.source === "none") {
      if (older) return 0;
      const at = r.checkedAt ? Date.parse(r.checkedAt) : 0;
      return now - at > kRetryNoneAfterMs ? 0 : null;
    }
    return older && r.timing !== "word" ? 1 : null;
  }

  /** Whether this track is worth asking about now. */
  needsLookup(sha: string, now = Date.now()): boolean {
    return this.lookupPriority(sha, now) !== null;
  }

  /**
   * Everything ever fetched or saved for a song, appended one JSON line at a
   * time to `lyrics-raw/<sha>.jsonl` beside the store: the training set for
   * the timing model. Never read by the app; a failure to write it is
   * logged by the caller's pass, never fatal to the lyrics themselves.
   */
  private async archive(sha: string, entry: Record<string, unknown>): Promise<void> {
    try {
      const dir = join(dirname(this.path), "lyrics-raw");
      await mkdir(dir, { recursive: true });
      await appendFile(join(dir, `${sha}.jsonl`), JSON.stringify(entry) + "\n");
    } catch {
      // The archive is a by-product; the store above is what matters.
    }
  }

  private persist(): Promise<void> {
    // Serialised: two writes at once would race on the temp file.
    this.writing = this.writing.then(async () => {
      await mkdir(dirname(this.path), { recursive: true });
      const tmp = `${this.path}.tmp`;
      await writeFile(tmp, JSON.stringify(this.data));
      await rename(tmp, this.path);
    });
    return this.writing;
  }
}

export interface LyricTarget {
  sha: string;
  title: string;
  artist: string;
  album: string;
  durationMs: number | null;
}

/**
 * One pass of fetching: up to [limit] songs, ones with no words before ones
 * whose words could be timed more finely, one at a time and [gapMs] apart
 * (these are free services, asked politely). Stops after two songs in a row
 * that no source could be asked about, rather than hammering an outage.
 *
 * "Nothing found" is only recorded when every source answered: a miss while
 * one was down would hide the song from the next pass for a week.
 */
export async function runLyricPass(opts: {
  tracks: LyricTarget[];
  store: LyricStore;
  client: { find(ours: Ours): Promise<ChainAnswer> };
  limit?: number;
  gapMs?: number;
  /** Tries per track before it counts as a failure. */
  attempts?: number;
  /** Wait before the second try; grows with each one. */
  retryGapMs?: number;
  sleep?: (ms: number) => Promise<void>;
  now?: () => number;
}): Promise<{ found: number; none: number; upgraded: number; stoppedEarly: boolean }> {
  const limit = opts.limit ?? 25;
  const gap = opts.gapMs ?? 1000;
  const attempts = opts.attempts ?? 3;
  const retryGap = opts.retryGapMs ?? 3000;
  const sleep = opts.sleep ?? ((ms) => new Promise((r) => setTimeout(r, ms)));
  const now = opts.now ?? Date.now;
  const queue = opts.tracks
    .map((t) => ({ t, p: opts.store.lookupPriority(t.sha, now()) }))
    .filter((x): x is { t: LyricTarget; p: 0 | 1 } => x.p !== null)
    .sort((a, b) => a.p - b.p)
    .slice(0, limit);
  let found = 0;
  let none = 0;
  let upgraded = 0;
  let failedInARow = 0;
  for (const [n, { t, p }] of queue.entries()) {
    if (n > 0) await sleep(gap);
    let answer: ChainAnswer = { found: null, complete: false };
    for (let attempt = 0; attempt < attempts; attempt++) {
      answer = await opts.client.find({
        title: t.title,
        artist: t.artist,
        album: t.album,
        durationMs: t.durationMs,
      });
      if (answer.found || answer.complete) break;
      // LRCLIB in particular answers "503, retry in a moment" now and then,
      // and the next request is fine.
      if (attempt < attempts - 1) await sleep(retryGap * (attempt + 1));
    }
    if (!answer.found && !answer.complete) {
      failedInARow += 1;
      if (failedInARow >= 2) return { found, none, upgraded, stoppedEarly: true };
      continue;
    }
    failedInARow = 0;
    const before = opts.store.get(t.sha)?.text ?? null;
    await opts.store.setFetched(t.sha, answer.found, new Date(now()));
    const after = opts.store.get(t.sha)?.text ?? null;
    if (p === 1) {
      if (after !== before) upgraded += 1;
    } else if (after) found += 1;
    else none += 1;
  }
  return { found, none, upgraded, stoppedEarly: false };
}
