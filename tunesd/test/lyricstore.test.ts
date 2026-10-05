import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import {
  kRetryNoneAfterMs,
  LyricStore,
  runLyricPass,
  type LyricTarget,
} from "../src/lyricstore.js";
import { LyricsUnavailable } from "../src/lyrics.js";

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
    await s.setFetched(T(1).sha, { text: "from lrclib", id: 5 });
    await s.setUser(T(1).sha, "mine");
    await s.setFetched(T(1).sha, { text: "from lrclib again", id: 6 });
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
    find: async () => (text ? { synced: text, plain: null, id: 9 } : null),
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
    expect(r).toEqual({ found: 2, none: 0, stoppedEarly: false });
    expect(s.get(T(1).sha)?.text).toBe("mine");
    expect(s.get(T(2).sha)?.source).toBe("lrclib");
  });

  it("asks no more than the limit in one go", async () => {
    const s = await new LyricStore(file).load();
    let asked = 0;
    await runLyricPass({
      tracks: [T(1), T(2), T(3), T(4)],
      store: s,
      client: { find: async () => (asked++, null) },
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
        find: async () => {
          if (++calls < 3) throw new LyricsUnavailable("lrclib 503");
          return { synced: "[00:01.00] la", plain: null, id: 4 };
        },
      },
      gapMs: 0,
      retryGapMs: 0,
    });
    expect(calls).toBe(3);
    expect(r).toEqual({ found: 1, none: 0, stoppedEarly: false });
    expect(s.get(T(1).sha)?.source).toBe("lrclib");
  });

  it("carries on to the next track when one will not answer", async () => {
    const s = await new LyricStore(file).load();
    const r = await runLyricPass({
      tracks: [T(1), T(2)],
      store: s,
      client: {
        find: async (q) => {
          if (q.title === "Song 1") throw new LyricsUnavailable("lrclib 503");
          return { synced: "[00:01.00] la", plain: null, id: 4 };
        },
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
          throw new LyricsUnavailable("down");
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
