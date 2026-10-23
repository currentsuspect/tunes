import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { buildManifest } from "../src/manifest.js";
import type { ProbeResult } from "../src/probe.js";
import { loadReplacements, resourceLost } from "../src/resource.js";
import { rankCandidates, searchVariants, type SlskResponse } from "../src/soulseek.js";

const log = { info: () => {}, warn: () => {}, error: () => {}, debug: () => {} } as any;

function probe(over: Partial<ProbeResult> = {}): ProbeResult {
  return {
    sha: "a".repeat(64), size: 1000, codec: "flac", sampleRate: 44100, channels: 2, bitrate: 900000,
    durationMs: 247000, tags: { title: "Lean Back", artist: "Terror Squad" }, hasEmbeddedArt: false,
    audioSha: "lost", probedAt: "2026-10-16T00:00:00Z", ...over,
  };
}

function resp(username: string, filename: string, over: Partial<SlskResponse> = {}, length = 247): SlskResponse {
  return { username, hasFreeUploadSlot: true, uploadSpeed: 5e6, queueLength: 0, files: [{ filename, size: 28e6, length }], ...over };
}

describe("searchVariants", () => {
  it("tries the artist in parts and the title alone", () => {
    expect(searchVariants({ artist: "Kendrick Lamar", title: "Luther" })).toEqual([
      "kendrick lamar luther",
      "kendrick luther",
      "lamar luther",
    ]);
    expect(searchVariants({ artist: "Yeat", title: "Team ceo" })).toEqual(["yeat team ceo", "team ceo"]);
  });
});

describe("rankCandidates", () => {
  const w = { artist: "Terror Squad", title: "Lean Back", durationMs: 247000 };
  it("prefers lossless, then a free slot", () => {
    const r = rankCandidates(
      [
        resp("mp3guy", "Music\\Terror Squad - Lean Back.mp3"),
        resp("busyflac", "Music\\Terror Squad - Lean Back.flac", { hasFreeUploadSlot: false }),
        resp("freeflac", "Music\\Terror Squad - Lean Back.flac"),
      ],
      w
    );
    expect(r.map((c) => c.username)).toEqual(["freeflac", "busyflac", "mp3guy"]);
  });
  it("drops other versions, other songs and wrong lengths", () => {
    const r = rankCandidates(
      [
        resp("live", "Terror Squad - Lean Back (Live).flac"),
        resp("remix", "Terror Squad - Lean Back Remix.flac"),
        resp("other", "Terror Squad - Take Me Home.flac"),
        resp("short", "Terror Squad - Lean Back.flac", {}, 120),
        resp("ok", "Terror Squad - Lean Back.flac"),
      ],
      w
    );
    expect(r.map((c) => c.username)).toEqual(["ok"]);
  });
});

describe("resourceLost", () => {
  let dir: string;
  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "tunes-slsk-"));
  });
  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  function fakeApi(opts: { slow?: string[]; length?: number } = {}) {
    const started: string[] = [];
    const transfers = new Map<string, number>();
    const api = {
      loggedIn: async () => true,
      search: async () => [resp("slowpeer", "x\\Terror Squad - Lean Back.flac"), resp("goodpeer", "y\\Terror Squad - Lean Back.flac", { uploadSpeed: 1e6 })],
      download: async (user: string, file: { filename: string }) => {
        started.push(user);
        transfers.set(user, 0);
        if (!opts.slow?.includes(user)) {
          const sub = join(dir, "dl", file.filename.split("\\")[0]!);
          await mkdir(sub, { recursive: true });
          await writeFile(join(sub, "Terror Squad - Lean Back.flac"), "x".repeat(100));
        }
      },
      transfer: async (user: string) => {
        const n = (transfers.get(user) ?? 0) + 1;
        transfers.set(user, n);
        if (opts.slow?.includes(user)) return { state: "InProgress", percentComplete: 1, bytesTransferred: 10 };
        return { state: n > 1 ? "Completed, Succeeded" : "InProgress", percentComplete: 50, bytesTransferred: 1e6 };
      },
      cancel: async () => {},
    };
    return { api: api as any, started };
  }

  const deps = (api: any, length: number, commits: string[]) => ({
    api,
    downloadsDir: join(dir, "dl"),
    probe: async () => probe({ sha: "pending", durationMs: length }),
    commit: async (path: string) => (commits.push(path), "b".repeat(64)),
    ledgerPath: join(dir, "replacements.json"),
    log,
    acquireOptions: { judgeAfterMs: 0, pollMs: 1, timeoutMs: 2000 },
  });

  it("skips a crawling peer, keeps a good download, records the pointer", async () => {
    const { api, started } = fakeApi({ slow: ["slowpeer"] });
    const commits: string[] = [];
    const r = await resourceLost([probe()], deps(api, 246000, commits));
    expect(r).toEqual({ found: 1, missed: 0, skipped: 0 });
    expect(started).toEqual(["slowpeer", "goodpeer"]);
    expect(commits).toHaveLength(1);
    const ledger = await loadReplacements(join(dir, "replacements.json"));
    expect(ledger.bySha["a".repeat(64)]?.sha).toBe("b".repeat(64));
  });

  it("leaves the downloads folder in place, which slskd needs to start", async () => {
    const { api } = fakeApi();
    await resourceLost([], deps(api, 246000, []));
    const { stat } = await import("node:fs/promises");
    expect((await stat(join(dir, "dl"))).isDirectory()).toBe(true);
  });

  it("points at a copy already in the library instead of downloading", async () => {
    const { api, started } = fakeApi();
    const commits: string[] = [];
    const r = await resourceLost([probe()], {
      ...deps(api, 247000, commits),
      inLibrary: () => "d".repeat(64),
    });
    expect(r.found).toBe(1);
    expect(started).toEqual([]);
    expect(commits).toEqual([]);
    const ledger = await loadReplacements(join(dir, "replacements.json"));
    expect(ledger.bySha["a".repeat(64)]).toMatchObject({ sha: "d".repeat(64), via: "library" });
  });

  it("deletes a download whose length is wrong and remembers the miss", async () => {
    const { api } = fakeApi();
    const commits: string[] = [];
    const r = await resourceLost([probe()], deps(api, 130000, commits));
    expect(r.found).toBe(0);
    expect(commits).toHaveLength(0);
    const ledger = JSON.parse(await readFile(join(dir, "replacements.json"), "utf8"));
    expect(ledger.misses["a".repeat(64)]).toBeTruthy();
    // A second pass inside a week does not search again.
    const again = await resourceLost([probe()], deps(api, 130000, commits));
    expect(again).toEqual({ found: 0, missed: 0, skipped: 1 });
  });
});

describe("manifest", () => {
  it("lists the re-sourced file and points the lost copy at it", () => {
    const lost = probe({ sha: "a".repeat(64), audioSha: "lostaudio" });
    const found = probe({ sha: "b".repeat(64), audioSha: "newaudio" });
    const m = buildManifest(
      [found],
      new Map(), new Map(), [], [], new Map(), new Map(), new Map(), new Map(), new Map(),
      [lost],
      new Map([[lost.sha, found.sha]])
    );
    expect(m.tracks.map((t) => t.sha)).toEqual([found.sha]);
    expect(m.tracks[0]?.dupeShas).toEqual([lost.sha]);
  });
});
