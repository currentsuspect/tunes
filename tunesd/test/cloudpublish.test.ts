import { gunzipSync } from "node:zlib";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { publishCloud, selectNewRows, selectAudioToBackfill, publishAudioFile } from "../src/cloudpublish.js";
import { State } from "../src/state.js";

const log = { info: () => {}, warn: (...a: unknown[]) => void a, error: () => {}, debug: () => {} } as any;

describe("publishCloud", () => {
  it("sends the rows as JSON, then the manifest gzipped to its own route", async () => {
    const seen: { url: string; init: any }[] = [];
    const fetchFn = vi.fn(async (url: string, init: any) => {
      seen.push({ url, init });
      return { ok: true, status: 200, json: async () => ({ ok: true, encoding: "gzip" }) };
    });
    const res = await publishCloud({
      url: "https://edge/internal/publish",
      key: "k",
      manifest: { schema: 3 },
      rows: [
        { sha: "a", chat: -1, msg: 7 },
        { sha: "b", chat: -1, msg: 8 },
      ],
      log,
      fetchFn: fetchFn as any,
    });
    expect(res).toMatchObject({ rows: 2, manifestBytes: '{"schema":3}'.length });
    expect(seen.map((x) => [x.init.method, x.url])).toEqual([
      ["POST", "https://edge/internal/publish"],
      ["PUT", "https://edge/internal/manifest"],
    ]);
    expect(seen.every((x) => x.init.headers.authorization === "Bearer k")).toBe(true);
    expect(JSON.parse(seen[0]!.init.body)).toEqual({
      rows: [
        { sha: "a", chat: -1, msg: 7 },
        { sha: "b", chat: -1, msg: 8 },
      ],
    });
    // The manifest as built, gzipped, and said to be.
    expect(seen[1]!.init.headers["x-tunes-encoding"]).toBe("gzip");
    expect(gunzipSync(seen[1]!.init.body).toString()).toBe('{"schema":3}');
  });

  it("an edge from before gzip is sent the manifest plain at once", async () => {
    const seen: { url: string; init: any }[] = [];
    const fetchFn = vi.fn(async (url: string, init: any) => {
      seen.push({ url, init });
      return { ok: true, status: 200, json: async () => ({ ok: true, manifestBytes: 12 }) };
    });
    const res = await publishCloud({ url: "https://edge/internal/publish", key: "k", manifest: { schema: 3 }, rows: [], log, fetchFn: fetchFn as any });
    expect(res).not.toBeNull();
    expect(seen.length).toBe(2);
    expect(seen[1]!.init.headers["x-tunes-encoding"]).toBeUndefined();
    expect(seen[1]!.init.body).toBe('{"schema":3}');
  });

  it("with no new rows, only the manifest goes", async () => {
    const fetchFn = vi.fn(async () => ({ ok: true, status: 200, json: async () => ({ encoding: "gzip" }) }));
    await publishCloud({ url: "https://edge/internal/publish", key: "k", manifest: {}, rows: [], log, fetchFn: fetchFn as any });
    expect(fetchFn).toHaveBeenCalledTimes(1);
  });

  it("an edge without the raw route gets the old combined publish", async () => {
    const seen: { url: string; init: any }[] = [];
    const fetchFn = vi.fn(async (url: string, init: any) => {
      seen.push({ url, init });
      if (url.endsWith("/internal/manifest")) return { ok: false, status: 404 };
      return { ok: true, status: 200, json: async () => ({ rows: 0, manifestBytes: 2 }) };
    });
    const res = await publishCloud({ url: "https://edge/internal/publish", key: "k", manifest: {}, rows: [], log, fetchFn: fetchFn as any });
    expect(res).not.toBeNull();
    const last = seen[seen.length - 1]!;
    expect(last.url).toBe("https://edge/internal/publish");
    expect(JSON.parse(last.init.body)).toEqual({ manifest: {}, rows: [] });
  });

  it("returns null on rejection without throwing", async () => {
    const warns: unknown[][] = [];
    const l = { ...log, warn: (...a: unknown[]) => void warns.push(a) };
    const res = await publishCloud({
      url: "https://edge/internal/publish",
      key: "k",
      manifest: {},
      rows: [],
      log: l,
      fetchFn: (async () => ({ ok: false, status: 401 })) as any,
    });
    expect(res).toBeNull();
    expect(warns.length).toBeGreaterThan(0);
  });

  it("returns null on transport failure without throwing", async () => {
    const res = await publishCloud({
      url: "https://edge/internal/publish",
      key: "k",
      manifest: {},
      rows: [],
      log,
      fetchFn: (async () => {
        throw new Error("down");
      }) as any,
    });
    expect(res).toBeNull();
  });
});

describe("State.sightingsFor", () => {
  let dir: string;
  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "tunes-sight-"));
  });
  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it("returns only the requested channels", async () => {
    const s = await new State(join(dir, "state.json")).load();
    s.markSeen("-1", 1, "aaa", null, null);
    s.markSeen("-99", 2, "bbb", null, null);
    expect(s.sightingsFor(["-99"])).toMatchObject([
      { sha: "bbb", chat: -99, msg: 2 },
    ]);
    expect(s.sightingsFor(["-1", "-99"])).toHaveLength(2);
    expect(s.sightingsFor(["-zzz"])).toEqual([]);
  });

  it("carries first-seen stamps oldest first", async () => {
    const s = await new State(join(dir, "state.json")).load();
    s.markSeen("-99", 2, "bbb", null, null);
    s.markSeen("-99", 1, "aaa", null, null);
    const rows = s.sightingsFor(["-99"]);
    expect(rows.map((r) => r.sha)).toEqual(["bbb", "aaa"]);
    expect(typeof rows[0]!.addedAt).toBe("string");
  });
});

describe("selectNewRows", () => {
  const r = (sha: string, addedAt: string | null) => ({ sha, addedAt });

  it("sends everything on first run", () => {
    const { rows, watermark } = selectNewRows(
      [r("a", "2026-01-01"), r("b", "2026-01-02")],
      null
    );
    expect(rows).toHaveLength(2);
    expect(watermark).toBe("2026-01-02");
  });

  it("sends only newer rows afterwards", () => {
    expect(
      selectNewRows([r("a", "2026-01-01")], "2026-01-02").rows
    ).toEqual([]);
    const next = selectNewRows(
      [r("a", "2026-01-01"), r("b", "2026-01-03")],
      "2026-01-02"
    );
    expect(next.rows.map((x) => x.sha)).toEqual(["b"]);
    expect(next.watermark).toBe("2026-01-03");
  });

  it("keeps the watermark when nothing is new", () => {
    expect(selectNewRows([r("a", "2026-01-01")], "2026-01-02")).toEqual({
      rows: [],
      watermark: "2026-01-02",
    });
  });
});

describe("selectAudioToBackfill", () => {
  const A = "a".repeat(64);
  const B = "b".repeat(64);
  const C = "c".repeat(64);
  const present = (sha: string) => sha !== C;

  it("keeps caller order with no cap, skipping published and absent", () => {
    expect(selectAudioToBackfill([B, A, B, C], {}, present)).toEqual([B, A]);
    expect(selectAudioToBackfill([B, A], { [B]: "2026-09-12" }, present)).toEqual([A]);
    expect(selectAudioToBackfill(["nope", null, undefined], {}, present)).toEqual([]);
  });
});

describe("publishAudioFile", () => {
  const SHA = "e".repeat(64);

  function putter(status: number, throws = false) {
    const seen: { url: unknown; init: unknown }[] = [];
    const fetchFn = vi.fn(async (url: unknown, init: any) => {
      seen.push({ url, init });
      if (throws) throw new Error("down");
      return { ok: status >= 200 && status < 300, status };
    });
    return { seen, fetchFn };
  }

  it("PUTs bytes to the audio route with the service key", async () => {
    const { seen, fetchFn } = putter(200);
    const bytes = new Uint8Array([0x66, 0x4c, 0x61, 0x43]);
    const ok = await publishAudioFile({
      baseUrl: "https://edge/internal",
      key: "k",
      sha: SHA,
      bytes,
      log,
      fetchFn: fetchFn as any,
    });
    expect(ok).toBe(true);
    expect(seen[0]!.url).toBe(`https://edge/internal/audio/${SHA}`);
    expect((seen[0]!.init as any).method).toBe("PUT");
    expect((seen[0]!.init as any).body).toBe(bytes);
  });

  it("refuses oversize, malformed, rejected, and failed transfers", async () => {
    const b = putter(200);
    expect(
      await publishAudioFile({
        baseUrl: "https://edge/internal", key: "k", sha: SHA,
        bytes: new Uint8Array(64 * 1024 * 1024 + 1), log, fetchFn: b.fetchFn as any,
      })
    ).toBe(false);
    expect(b.fetchFn).not.toHaveBeenCalled();
    expect(
      await publishAudioFile({
        baseUrl: "https://edge/internal", key: "k", sha: "nope",
        bytes: new Uint8Array([1]), log, fetchFn: b.fetchFn as any,
      })
    ).toBe(false);
    const rej = putter(401);
    expect(
      await publishAudioFile({
        baseUrl: "https://edge/internal", key: "k", sha: SHA,
        bytes: new Uint8Array([1]), log, fetchFn: rej.fetchFn as any,
      })
    ).toBe(false);
    const down = putter(0, true);
    expect(
      await publishAudioFile({
        baseUrl: "https://edge/internal", key: "k", sha: SHA,
        bytes: new Uint8Array([1]), log, fetchFn: down.fetchFn as any,
      })
    ).toBe(false);
  });
});

describe("publishAudioFile URL", () => {
  it("PUTs to <base>/audio/<sha>, so the base is the /internal prefix", async () => {
    const urls: string[] = [];
    const ok = await publishAudioFile({
      baseUrl: "https://t.example/internal",
      key: "k",
      sha: "a".repeat(64),
      bytes: new Uint8Array([1]),
      log,
      fetchFn: (async (u: unknown) => (urls.push(String(u)), new Response("{}"))) as any,
    });
    expect(ok).toBe(true);
    expect(urls).toEqual([`https://t.example/internal/audio/${"a".repeat(64)}`]);
  });
});
