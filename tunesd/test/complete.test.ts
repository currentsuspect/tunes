import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { completeAlbums, matchAlbum, partialAlbums } from "../src/complete.js";
import * as resource from "../src/resource.js";

const log = { info: () => {}, warn: () => {}, error: () => {}, debug: () => {} } as never;

describe("which albums to fill in", () => {
  it("held in part, nearest to complete first", () => {
    const r = (id: string, owned: number, total: number | null) => ({
      id,
      title: id,
      artist: "Lunchbox",
      totalTracks: total,
      trackShas: Array.from({ length: owned }, (_, i) => `${id}${i}`),
    });
    const got = partialAlbums([r("new-jazz", 5, 23), r("lb-cooper", 11, 12), r("whole", 10, 10), r("two", 2, 12), r("unknown", 6, null)]);
    expect(got.map((a) => a.id)).toEqual(["lb-cooper", "new-jazz"]);
  });

  it("matches the Deezer album by title and artist, edition notes aside", () => {
    const album = { id: "x", title: "New Jazz (Deluxe)", artist: "Lunchbox", owned: 5, total: 23 };
    const m = matchAlbum(album, [
      { id: 1, title: "New Jazz Live", artist: "Lunchbox", coverUrl: null },
      { id: 2, title: "New Jazz", artist: "Lunchbox", coverUrl: null },
    ]);
    expect(m?.id).toBe(2);
    expect(matchAlbum(album, [{ id: 3, title: "New Jazz", artist: "Someone Else", coverUrl: null }])).toBeNull();
  });
});

describe("completeAlbums", () => {
  let dir: string;
  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "tunes-complete-"));
  });
  afterEach(async () => {
    vi.restoreAllMocks();
    await rm(dir, { recursive: true, force: true });
  });

  it("fetches only what is missing, keeps only the right length, once a week", async () => {
    const { writeFile, mkdir } = await import("node:fs/promises");
    vi.spyOn(resource, "acquire").mockImplementation(async (_api, w) => {
      await mkdir(join(dir, "dl", w.title), { recursive: true });
      const path = join(dir, "dl", w.title, "f.flac");
      await writeFile(path, "x");
      return { path, candidate: {} as never };
    });
    const committed: string[] = [];
    const deps = {
      deezer: {
        searchAlbumCandidates: async () => [{ id: 9, title: "New Jazz", artist: "Lunchbox", coverUrl: null }],
        albumTracks: async () => [
          { title: "Held", artist: "Lunchbox", durationMs: 100_000, trackNumber: 1, discNumber: 1 },
          { title: "Missing", artist: "Lunchbox", durationMs: 120_000, trackNumber: 2, discNumber: 1 },
          { title: "WrongLength", artist: "Lunchbox", durationMs: 200_000, trackNumber: 3, discNumber: 1 },
        ],
      },
      api: { loggedIn: async () => true } as never,
      downloadsDir: join(dir, "dl"),
      probe: async (path: string) =>
        ({ codec: "flac", durationMs: path.includes("WrongLength") ? 150_000 : 121_000 }) as never,
      commit: async (path: string) => {
        committed.push(path);
        return "sha";
      },
      inLibrary: (w: { title: string }) => (w.title === "Held" ? "heldsha" : null),
      ledgerPath: join(dir, "ledger.json"),
      log,
    };
    const album = { id: "nj", title: "New Jazz", artist: "Lunchbox", owned: 1, total: 3 };
    const r = await completeAlbums([album], deps);
    expect(r).toEqual({ albums: 1, found: 1, missed: 1 });
    expect(committed).toHaveLength(1);
    expect(committed[0]).toContain("Missing");
    // Looked at this week already: left alone.
    expect((await completeAlbums([album], deps)).albums).toBe(0);
  });
});
