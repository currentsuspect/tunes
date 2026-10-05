import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import type { LrclibClient } from "./lyrics.js";
import { LyricsUnavailable } from "./lyrics.js";

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
export type LyricSource = "user" | "lrclib" | "none";

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
  forManifest(): Map<string, { lyrics: string; source: "user" | "lrclib" }> {
    const out = new Map<string, { lyrics: string; source: "user" | "lrclib" }>();
    for (const [sha, r] of Object.entries(this.data.tracks)) {
      if (r.text && (r.source === "user" || r.source === "lrclib")) {
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
  }

  /** What a lookup found. Never replaces a listener's version. */
  async setFetched(
    sha: string,
    found: { text: string; id: number | null } | null,
    now = new Date(),
  ): Promise<void> {
    const have = this.data.tracks[sha];
    if (have?.source === "user") return;
    const stamp = now.toISOString();
    this.data.tracks[sha] = found
      ? {
          text: found.text,
          source: "lrclib",
          lrclibId: found.id,
          updatedAt: stamp,
          checkedAt: stamp,
        }
      : {
          text: null,
          source: "none",
          lrclibId: null,
          // Nothing changed for anyone, so this is not a change.
          updatedAt: have?.updatedAt ?? stamp,
          checkedAt: stamp,
        };
    await this.persist();
  }

  /** Whether this track is worth asking LRCLIB about now. */
  needsLookup(sha: string, now = Date.now()): boolean {
    const r = this.data.tracks[sha];
    if (!r) return true;
    if (r.source === "none") {
      const at = r.checkedAt ? Date.parse(r.checkedAt) : 0;
      return now - at > kRetryNoneAfterMs;
    }
    return false;
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
 * One pass of fetching: up to [limit] tracks that need it, one at a time and
 * [gapMs] apart (LRCLIB is a free service and is asked politely). Stops at the
 * first outage rather than hammering a service that is down.
 *
 * Returns how many were found, how many LRCLIB had nothing for, and whether it
 * stopped early.
 */
export async function runLyricPass(opts: {
  tracks: LyricTarget[];
  store: LyricStore;
  client: Pick<LrclibClient, "find">;
  limit?: number;
  gapMs?: number;
  sleep?: (ms: number) => Promise<void>;
  now?: () => number;
}): Promise<{ found: number; none: number; stoppedEarly: boolean }> {
  const limit = opts.limit ?? 25;
  const gap = opts.gapMs ?? 1000;
  const sleep = opts.sleep ?? ((ms) => new Promise((r) => setTimeout(r, ms)));
  const now = opts.now ?? Date.now;
  let found = 0;
  let none = 0;
  let asked = 0;
  for (const t of opts.tracks) {
    if (asked >= limit) break;
    if (!opts.store.needsLookup(t.sha, now())) continue;
    if (asked > 0) await sleep(gap);
    asked += 1;
    try {
      const r = await opts.client.find({
        title: t.title,
        artist: t.artist,
        album: t.album,
        durationMs: t.durationMs,
      });
      const text = r?.synced ?? r?.plain ?? null;
      await opts.store.setFetched(
        t.sha,
        text ? { text, id: r?.id ?? null } : null,
        new Date(now()),
      );
      if (text) found += 1;
      else none += 1;
    } catch (e) {
      if (e instanceof LyricsUnavailable) {
        return { found, none, stoppedEarly: true };
      }
      throw e;
    }
  }
  return { found, none, stoppedEarly: false };
}
