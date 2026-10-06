import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { LyricStore } from "../src/lyricstore.js";
import { ManifestServer } from "../src/serve.js";
import type { ManifestV3 } from "../src/manifest.js";

/**
 * The route a phone uses to share lyrics, and the signal other phones read to
 * find out. The server is the real one; only the library behind it is faked.
 */
const SHA = "a".repeat(64);
const OTHER = "b".repeat(64);

let dir: string;
let store: LyricStore;
let server: ManifestServer;
let base: string;
let changed = 0;
let builds = 0;

function manifest(): ManifestV3 {
  return {
    schema: 4,
    generatedAt: new Date().toISOString(),
    integrity: "x",
    tracks: [{ sha: SHA, addedAt: "2026-01-01T00:00:00Z" }],
    releases: [],
    artists: [],
  } as unknown as ManifestV3;
}

beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), "lyrics-route-"));
  store = await new LyricStore(join(dir, "lyrics.json")).load();
  const port = 41000 + Math.floor(Math.random() * 2000);
  base = `http://127.0.0.1:${port}`;
  changed = 0;
  builds = 0;
  server = new ManifestServer(
    {} as never,
    join(dir, "covers"),
    async () => {
      builds += 1;
      return manifest();
    },
    port,
    { info() {}, warn() {}, error() {}, debug() {} } as never,
    undefined,
    null,
    null,
    null,
    undefined,
    "127.0.0.1",
    null,
    null,
    store,
    () => {
      changed += 1;
    },
  );
  await server.start();
});

afterEach(async () => {
  await rm(dir, { recursive: true, force: true });
});

const put = (sha: string, body: unknown) =>
  fetch(`${base}/lyrics/${sha}`, {
    method: "PUT",
    headers: { "content-type": "application/json" },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });

describe("PUT /lyrics/<sha>", () => {
  it("stores a listener's lyrics, tells the daemon, and shows in the manifest source", async () => {
    const r = await put(SHA, { lyrics: "[00:01.00] hello" });
    expect(r.status).toBe(204);
    expect(changed).toBe(1);
    expect(store.forManifest().get(SHA)).toEqual({
      lyrics: "[00:01.00] hello",
      source: "user",
    });
  });

  it("takes them away with empty text", async () => {
    await put(SHA, { lyrics: "hello" });
    const r = await put(SHA, { lyrics: "  " });
    expect(r.status).toBe(204);
    expect(store.forManifest().has(SHA)).toBe(false);
  });

  it("refuses a track that is not in the library", async () => {
    const r = await put(OTHER, { lyrics: "hello" });
    expect(r.status).toBe(404);
    expect(store.get(OTHER)).toBeNull();
  });

  it("refuses a body that is not the right shape", async () => {
    expect((await put(SHA, "not json")).status).toBe(400);
    expect((await put(SHA, { words: "x" })).status).toBe(400);
    expect((await put(SHA, { lyrics: 5 })).status).toBe(400);
    expect(store.get(SHA)).toBeNull();
  });

  it("refuses lyrics longer than any song has", async () => {
    const r = await put(SHA, { lyrics: "la ".repeat(40000) });
    expect(r.status).toBe(400);
    expect(store.get(SHA)).toBeNull();
  });

  it("is PUT only", async () => {
    const r = await fetch(`${base}/lyrics/${SHA}`);
    expect(r.status).toBe(405);
  });
});

describe("/changes tells phones about new lyrics", () => {
  it("lists tracks whose lyrics changed since the phone last looked", async () => {
    const before = new Date(Date.now() - 60_000).toISOString();
    await put(SHA, { lyrics: "hello" });
    const r = (await (
      await fetch(`${base}/changes?since=${encodeURIComponent(before)}`)
    ).json()) as { addedShas: string[]; lyricsChanged: string[] };
    expect(r.addedShas).toEqual([]);
    expect(r.lyricsChanged).toEqual([SHA]);
  });

  it("lists nothing for a phone that is already up to date", async () => {
    await put(SHA, { lyrics: "hello" });
    const after = new Date(Date.now() + 60_000).toISOString();
    const r = (await (
      await fetch(`${base}/changes?since=${encodeURIComponent(after)}`)
    ).json()) as { lyricsChanged: string[] };
    expect(r.lyricsChanged).toEqual([]);
  });
});

describe("GET /changes", () => {
  it("answers from the cached manifest instead of rebuilding it on every call", async () => {
    // Every phone asks this every half minute or so. Rebuilding the whole
    // manifest each time made it take seconds on a busy box, long enough that
    // the app's own connection check gave up and called a good connection lost.
    for (let i = 0; i < 5; i++) {
      const r = await fetch(`${base}/changes?since=2020-01-01T00:00:00Z`);
      expect(r.status).toBe(200);
    }
    expect(builds).toBe(1);
  });

  it("still sees new lyrics at once, because saving them drops the cache", async () => {
    await fetch(`${base}/changes?since=2020-01-01T00:00:00Z`);
    await put(SHA, { lyrics: "[00:01.00] hello" });
    const r = await fetch(`${base}/changes?since=2020-01-01T00:00:00Z`);
    const body = (await r.json()) as { lyricsChanged: string[] };
    expect(body.lyricsChanged).toContain(SHA);
  });
});
