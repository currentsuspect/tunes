import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import {
  kRetryNoneAfterMs,
  LyricStore,
  runLyricPass,
  type LyricTarget,
} from "../src/lyricstore.js";
import type { ChainAnswer, FoundLyrics, LyricTiming } from "../src/lyricsources.js";

const got = (text: string, timing: LyricTiming = "line", source: FoundLyrics["source"] = "lrclib"): FoundLyrics => ({
  text,
  source,
  timing,
  id: "9",
  raw: { text },
});
const answer = (text: string | null): ChainAnswer => ({ found: text ? got(text) : null, complete: true });
const down: ChainAnswer = { found: null, complete: false };

const T = (n: number): LyricTarget => ({
  sha: String(n).padStart(64, "0"),
  title: `Song ${n}`,
  artist: "Artist",
  album: "Album",
  durationMs: 180000,
});

let dir: string;
let file: string;
beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), "lyrics-"));
  file = join(dir, "lyrics.json");
});
afterEach(async () => {
  await rm(dir, { recursive: true, force: true });
});

describe("a listener's lyrics reach everyone", () => {
  it("are served from the store and survive a restart", async () => {
    const a = await new LyricStore(file).load();
    await a.setUser(T(1).sha, "[00:01.00] hello\r\n[00:02.00] world ");
    const b = await new LyricStore(file).load();
    expect(b.forManifest().get(T(1).sha)).toEqual({
      lyrics: "[00:01.00] hello\n[00:02.00] world",
      source: "user",
    });
  });

  it("win over a fetch, now and later", async () => {
    const s = await new LyricStore(file).load();
    await s.setFetched(T(1).sha, got("from lrclib"));
    await s.setUser(T(1).sha, "mine");
    await s.setFetched(T(1).sha, got("from lrclib again"));
    expect(s.get(T(1).sha)?.text).toBe("mine");
    expect(s.get(T(1).sha)?.source).toBe("user");
  });

  it("can be taken away, and the track goes back to being asked about", async () => {
    const s = await new LyricStore(file).load();
    await s.setUser(T(1).sha, "mine");
    await s.setUser(T(1).sha, "   ");
    expect(s.get(T(1).sha)).toBeNull();
    expect(s.needsLookup(T(1).sha)).toBe(true);
  });

  it("show up as a change after the moment a phone last looked", async () => {
    const s = await new LyricStore(file).load();
    const before = Date.now() - 1000;
    await s.setUser(T(1).sha, "mine", new Date(before + 500));
    expect(s.changedSince(before)).toEqual([T(1).sha]);
    expect(s.changedSince(before + 600)).toEqual([]);
  });
});

describe("remembering what LRCLIB did not have", () => {
  it("does not ask again straight away, and does ask again in a week", async () => {
    const s = await new LyricStore(file).load();
    const t0 = new Date("2026-10-05T00:00:00Z");
    await s.setFetched(T(1).sha, null, t0);
    expect(s.needsLookup(T(1).sha, t0.getTime() + 1000)).toBe(false);
    expect(s.needsLookup(T(1).sha, t0.getTime() + kRetryNoneAfterMs + 1000)).toBe(true);
  });

  it("is not a change for anyone", async () => {
    const s = await new LyricStore(file).load();
    await s.setFetched(T(1).sha, null);
    expect(s.changedSince(0)).toEqual([]);
    expect(s.forManifest().size).toBe(0);
  });
});

describe("the fetch pass", () => {
  const ok = (text: string | null) => ({
    find: async () => answer(text),
  });

  it("fills in what is missing and leaves what is there", async () => {
    const s = await new LyricStore(file).load();
    await s.setUser(T(1).sha, "mine");
    const r = await runLyricPass({
      tracks: [T(1), T(2), T(3)],
      store: s,
      client: ok("[00:01.00] la"),
      gapMs: 0,
    });
    expect(r).toEqual({ found: 2, none: 0, upgraded: 0, stoppedEarly: false });
    expect(s.get(T(1).sha)?.text).toBe("mine");
    expect(s.get(T(2).sha)?.source).toBe("lrclib");
  });

  it("asks no more than the limit in one go", async () => {
    const s = await new LyricStore(file).load();
    let asked = 0;
    await runLyricPass({
      tracks: [T(1), T(2), T(3), T(4)],
      store: s,
      client: { find: async () => (asked++, answer(null)) },
      limit: 2,
      gapMs: 0,
    });
    expect(asked).toBe(2);
  });

  it("tries a busy service again, and records what it then finds", async () => {
    // "503, the server is busy, retry in a moment" -- and the next try is fine.
    const s = await new LyricStore(file).load();
    let calls = 0;
    const r = await runLyricPass({
      tracks: [T(1)],
      store: s,
      client: {
        find: async () => (++calls < 3 ? down : answer("[00:01.00] la")),
      },
      gapMs: 0,
      retryGapMs: 0,
    });
    expect(calls).toBe(3);
    expect(r).toEqual({ found: 1, none: 0, upgraded: 0, stoppedEarly: false });
    expect(s.get(T(1).sha)?.source).toBe("lrclib");
  });

  it("carries on to the next track when one will not answer", async () => {
    const s = await new LyricStore(file).load();
    const r = await runLyricPass({
      tracks: [T(1), T(2)],
      store: s,
      client: {
        find: async (q) => (q.title === "Song 1" ? down : answer("[00:01.00] la")),
      },
      gapMs: 0,
      retryGapMs: 0,
    });
    expect(r.found).toBe(1);
    // The one that failed is not recorded as having no lyrics.
    expect(s.get(T(1).sha)).toBeNull();
    expect(s.needsLookup(T(1).sha)).toBe(true);
  });

  it("stops when the service keeps failing, and records nothing", async () => {
    const s = await new LyricStore(file).load();
    let calls = 0;
    const r = await runLyricPass({
      tracks: [T(1), T(2), T(3), T(4)],
      store: s,
      client: {
        find: async () => {
          calls++;
          return down;
        },
      },
      gapMs: 0,
      retryGapMs: 0,
    });
    expect(r.stoppedEarly).toBe(true);
    // Two tracks, three tries each, then it stops asking.
    expect(calls).toBe(6);
    expect(s.get(T(1).sha)).toBeNull();
    expect(s.needsLookup(T(1).sha)).toBe(true);
  });

  it("remembers a song LRCLIB has nothing for", async () => {
    const s = await new LyricStore(file).load();
    const r = await runLyricPass({
      tracks: [T(1)],
      store: s,
      client: ok(null),
      gapMs: 0,
    });
    expect(r.none).toBe(1);
    expect(s.needsLookup(T(1).sha)).toBe(false);
  });
});

describe("more sources, finer timing", () => {
  it("asks songs with no words before songs it could only improve", async () => {
    const s = await new LyricStore(file).load();
    // An old LRCLIB record (no chain, line timing) and a brand-new song.
    await s.setFetched(T(1).sha, got("[00:01.00] old"));
    (s.get(T(1).sha) as { chain?: number }).chain = 1;
    const asked: string[] = [];
    await runLyricPass({
      tracks: [T(1), T(2)],
      store: s,
      client: { find: async (q) => (asked.push(q.title), answer(null)) },
      gapMs: 0,
    });
    expect(asked).toEqual(["Song 2", "Song 1"]);
  });

  it("upgrades line timing to word timing, and never the other way", async () => {
    const s = await new LyricStore(file).load();
    await s.setFetched(T(1).sha, got("[00:01.00] line"));
    await s.setFetched(T(1).sha, got("[00:01.000]<00:01.000>word<00:01.400>", "word", "netease"));
    expect(s.get(T(1).sha)?.timing).toBe("word");
    expect(s.get(T(1).sha)?.source).toBe("netease");
    await s.setFetched(T(1).sha, got("plain words", "plain", "genius"));
    expect(s.get(T(1).sha)?.timing).toBe("word");
    expect(s.forManifest().get(T(1).sha)?.source).toBe("netease");
  });

  it("re-asks a song nothing had, once new sources join", async () => {
    const s = await new LyricStore(file).load();
    await s.setFetched(T(1).sha, null);
    expect(s.needsLookup(T(1).sha)).toBe(false);
    (s.get(T(1).sha) as { chain?: number }).chain = 1;
    expect(s.lookupPriority(T(1).sha)).toBe(0);
  });

  it("keeps everything fetched and every listener save, for training", async () => {
    const s = await new LyricStore(file).load();
    await s.setFetched(T(1).sha, got("[00:01.00] a"));
    await s.setUser(T(1).sha, "[00:01.020]<00:01.020>a<00:01.300>");
    await s.setUser(T(1).sha, "[00:01.010]<00:01.010>a<00:01.290>");
    const lines = (await readFile(join(dir, "lyrics-raw", `${T(1).sha}.jsonl`), "utf8")).trim().split("\n");
    expect(lines.map((l) => JSON.parse(l).kind)).toEqual(["lrclib", "user", "user"]);
  });
});
