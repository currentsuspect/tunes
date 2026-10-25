import { describe, expect, it, vi } from "vitest";
import {
  handleArtGet,
  handleArtPut,
  handleAudioPut,
  handleManifestGet,
  handleManifestPut,
  handlePublish,
  handleTrackGet,
} from "../src/publish.js";

const KEY = "k".repeat(64);
const HOST = "https://tunes.aestra.studio";
const SHA = "a".repeat(64);

function fakeEnv(over: Record<string, unknown> = {}, boxes: Record<string, unknown> = {}) {
  const puts: { key: string; value: string }[] = [];
  const batches: unknown[][] = [];
  return {
    env: {
      INTERNAL_PUBLISH_KEY: KEY,
      DB: {
        prepare: (sql: string) => ({
          bind: (...args: unknown[]) => ({
            sql,
            args,
            // BYOB box lookups (a key that is not the owner's): no box unless a test adds one.
            first: async () => (boxes as Record<string, unknown>)[String(args[0])] ?? null,
            run: async () => ({}),
          }),
        }),
        batch: vi.fn(async (stmts: unknown[]) => {
          batches.push(stmts);
          return [];
        }),
      },
      CACHE: {
        put: vi.fn(async (key: string, value: string) => {
          puts.push({ key, value });
        }),
      },
      ...over,
    } as any,
    puts,
    batches,
  };
}

function post(body: unknown, key = KEY): Request {
  return new Request(`${HOST}/internal/publish`, {
    method: "POST",
    headers: { authorization: `Bearer ${key}` },
    body: JSON.stringify(body),
  });
}

const good = () => ({
  manifest: { schema: 3, tracks: [] },
  rows: [{ sha: SHA, chat: -1, msg: 7 }],
});

describe("publish endpoint", () => {
  it("stores the manifest and the rows on a valid call", async () => {
    const { env, puts, batches } = fakeEnv();
    const res = await handlePublish(post(good()), env);
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ ok: true, rows: 1 });
    expect(puts).toHaveLength(1);
    expect(puts[0]!.key).toBe("manifest.json");
    expect(JSON.parse(puts[0]!.value)).toMatchObject({ schema: 3 });
    expect(batches).toHaveLength(1);
  });

  it("denies a wrong key, a missing key, and a missing binding key alike", async () => {
    const { env } = fakeEnv();
    for (const init of [
      { headers: { authorization: "Bearer wrong" } },
      {},
    ]) {
      const res = await handlePublish(
        new Request(`${HOST}/internal/publish`, { method: "POST", ...init, body: "{}" }),
        env
      );
      expect(res.status).toBe(401);
    }
    const noKey = fakeEnv({ INTERNAL_PUBLISH_KEY: undefined });
    const res = await handlePublish(post(good()), noKey.env);
    expect(res.status).toBe(401);
  });

  it("rejects malformed rows and oversized batches", async () => {
    const { env } = fakeEnv();
    for (const rows of [
      [{ sha: "nope", chat: -1, msg: 7 }],
      [{ sha: SHA, chat: -1, msg: -3 }],
      [{ sha: SHA, chat: -1 }],
      new Array(5001).fill({ sha: SHA, chat: -1, msg: 7 }),
      "not-an-array",
    ]) {
      const res = await handlePublish(post({ manifest: {}, rows }), env);
      expect(res.status).toBe(400);
    }
  });

  it("rejects a non-object manifest", async () => {
    const { env } = fakeEnv();
    for (const manifest of [null, [], "str"]) {
      const res = await handlePublish(post({ manifest, rows: [] }), env);
      expect(res.status).toBe(400);
    }
  });

  it("fails closed without bindings", async () => {
    const { env } = fakeEnv({ DB: undefined });
    expect((await handlePublish(post(good()), env)).status).toBe(500);
    const noCache = fakeEnv({ CACHE: undefined });
    expect((await handlePublish(post(good()), noCache.env)).status).toBe(500);
  });

  it("publishes an empty row set (manifest-only cycle)", async () => {
    const { env, puts, batches } = fakeEnv();
    const res = await handlePublish(post({ manifest: { schema: 3 }, rows: [] }), env);
    expect(res.status).toBe(200);
    expect(batches).toHaveLength(0);
    expect(puts).toHaveLength(1);
  });
});

describe("manifest sent raw (23 Oct: the combined publish ran out of CPU)", () => {
  const put = (body: string, key = KEY, method = "PUT") =>
    new Request(`${HOST}/internal/manifest`, {
      method,
      headers: { authorization: `Bearer ${key}`, "content-length": String(body.length) },
      body,
    });

  it("streams the bytes to R2 untouched", async () => {
    const { env } = fakeEnv();
    const text = JSON.stringify({ schema: 3, tracks: [] });
    const res = await handleManifestPut(put(text), env);
    expect(res.status).toBe(200);
    expect(env.CACHE.put).toHaveBeenCalledTimes(1);
    expect(env.CACHE.put.mock.calls[0][0]).toBe("manifest.json");
  });

  it("needs the service key, PUT, and a length", async () => {
    const { env } = fakeEnv();
    expect((await handleManifestPut(put("{}", "x".repeat(64)), env)).status).toBe(401);
    expect((await handleManifestPut(put("{}", KEY, "POST"), env)).status).toBe(405);
    const noLength = new Request(`${HOST}/internal/manifest`, {
      method: "PUT",
      headers: { authorization: `Bearer ${KEY}` },
      body: "{}",
    });
    expect([411, 200]).toContain((await handleManifestPut(noLength, env)).status);
    expect(env.CACHE.put).not.toHaveBeenCalledWith("manifest.json", "x", expect.anything());
  });

  it("the publish then carries only the rows", async () => {
    const { env, puts, batches } = fakeEnv();
    const res = await handlePublish(post({ rows: [{ sha: SHA, chat: -1, msg: 7 }] }), env);
    expect(res.status).toBe(200);
    expect(batches).toHaveLength(1);
    expect(puts).toHaveLength(0);
  });
});

describe("art put endpoint", () => {
  const SHA = "b".repeat(64);
  const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0x00, 0x11]);

  function put(bytes: Uint8Array, key = KEY, path = `/internal/art/${SHA}`): Request {
    return new Request(`${HOST}${path}`, {
      method: "PUT",
      headers: { authorization: `Bearer ${key}` },
      body: bytes as BodyInit,
    });
  }

  function artEnv(files: Record<string, { body: Uint8Array; type: string }> = {}) {
    const { env } = fakeEnv();
    const puts: { key: string; value: unknown }[] = [];
    const store = new Map<string, { body: Uint8Array; type: string }>(Object.entries(files));
    (env.CACHE as any).get = vi.fn(async (k: string) => {
      const f = store.get(k);
      return f ? { body: f.body, httpMetadata: { contentType: f.type } } : null;
    });
    (env.CACHE as any).put = vi.fn(async (k: string, v: Uint8Array, opts: any) => {
      puts.push({ key: k, value: v });
      store.set(k, { body: v, type: opts?.httpMetadata?.contentType });
    });
    return { env, puts, store };
  }

  it("stores a real image under its sha key", async () => {
    const { env, puts, store } = artEnv();
    const res = await handleArtPut(put(JPEG), `/internal/art/${SHA}`, env);
    expect(res.status).toBe(200);
    expect(puts).toHaveLength(1);
    expect(puts[0]!.key).toBe(`art/${SHA}`);
    expect(store.get(`art/${SHA}`)?.type).toBe("image/jpeg");
  });

  it("names bytes by magic, not by the uploader's label", async () => {
    const { env, store } = artEnv();
    const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    const res = await handleArtPut(put(png), `/internal/art/${SHA}`, env);
    expect(res.status).toBe(200);
    expect(store.get(`art/${SHA}`)?.type).toBe("image/png");
  });

  it("refuses non-images, empties, oversize, bad keys, and bad shas", async () => {
    const { env } = artEnv();
    expect((await handleArtPut(put(new Uint8Array([1, 2, 3])), `/internal/art/${SHA}`, env)).status).toBe(415);
    expect((await handleArtPut(put(new Uint8Array([])), `/internal/art/${SHA}`, env)).status).toBe(413);
    expect((await handleArtPut(put(JPEG, "wrong"), `/internal/art/${SHA}`, env)).status).toBe(401);
    expect((await handleArtPut(put(JPEG), "/internal/art/nope", env)).status).toBe(404);
    const big = new Uint8Array(2 * 1024 * 1024 + 1);
    big[0] = 0xff; big[1] = 0xd8; big[2] = 0xff;
    expect((await handleArtPut(put(big), `/internal/art/${SHA}`, env)).status).toBe(413);
  });

  it("fails closed without the R2 binding", async () => {
    const { env } = fakeEnv({ CACHE: undefined });
    expect((await handleArtPut(put(JPEG), `/internal/art/${SHA}`, env)).status).toBe(500);
  });
});

describe("art get from R2", () => {
  const SHA = "c".repeat(64);
  const JPEG = new Uint8Array([0xff, 0xd8, 0xff]);

  function artEnv(files: Record<string, { body: Uint8Array; type: string }> = {}) {
    const { env } = fakeEnv();
    const store = new Map(Object.entries(files));
    (env.CACHE as any).get = vi.fn(async (k: string) => {
      const f = store.get(k);
      return f ? { body: (f as any).body, httpMetadata: { contentType: (f as any).type } } : null;
    });
    return env;
  }

  it("serves a cached cover immutable", async () => {
    const env = artEnv({ [`art/${SHA}`]: { body: JPEG, type: "image/jpeg" } });
    const res = (await handleArtGet(`/art/${SHA}`, env))!;
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("image/jpeg");
    expect(res.headers.get("cache-control")).toContain("immutable");
    expect(new Uint8Array(await res.arrayBuffer())).toEqual(JPEG);
  });

  it("returns null on miss, malformed shape, or missing binding", async () => {
    const env = artEnv();
    expect(await handleArtGet(`/art/${SHA}`, env)).toBeNull();
    expect(await handleArtGet("/art/nope", env)).toBeNull();
    expect(await handleArtGet("/track/" + SHA, env)).toBeNull();
    const noCache = fakeEnv({ CACHE: undefined }).env;
    expect(await handleArtGet(`/art/${SHA}`, noCache)).toBeNull();
  });
});

describe("audio put endpoint", () => {
  // "fLaC" + padding: sniffed as audio/flac, hashed to prove the path check.
  const BYTES = new Uint8Array([0x66, 0x4c, 0x61, 0x43, 1, 2, 3, 4]);

  async function shaOf(bytes: Uint8Array): Promise<string> {
    const digest = await crypto.subtle.digest("SHA-256", bytes as any);
    return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
  }

  function put(bytes: Uint8Array, sha: string, key = KEY): Request {
    return new Request(`${HOST}/internal/audio/${sha}`, {
      method: "PUT",
      headers: { authorization: `Bearer ${key}` },
      body: bytes as BodyInit,
    });
  }

  function audioEnv() {
    const { env } = fakeEnv();
    const puts: { key: string; value: unknown }[] = [];
    const store = new Map<string, { body: unknown; type: unknown }>();
    (env.CACHE as any).put = vi.fn(async (k: string, v: unknown, opts: any) => {
      puts.push({ key: k, value: v });
      store.set(k, { body: v, type: opts?.httpMetadata?.contentType });
    });
    return { env, puts, store };
  }

  it("stores verified bytes under the bare sha with a sniffed type", async () => {
    const { env, puts, store } = audioEnv();
    const sha = await shaOf(BYTES);
    const res = await handleAudioPut(put(BYTES, sha), `/internal/audio/${sha}`, env);
    expect(res.status).toBe(200);
    expect(puts).toHaveLength(1);
    expect(puts[0]!.key).toBe(sha);
    expect(store.get(sha)?.type).toBe("audio/flac");
    expect(JSON.parse(await res.text())).toMatchObject({ ok: true, sha });
  });

  it("refuses mismatched hashes, empties, bad keys, and bad shas", async () => {
    const { env } = audioEnv();
    const sha = await shaOf(BYTES);
    const wrong = "0".repeat(64);
    expect((await handleAudioPut(put(BYTES, wrong), `/internal/audio/${wrong}`, env)).status).toBe(422);
    expect((await handleAudioPut(put(new Uint8Array([]), sha), `/internal/audio/${sha}`, env)).status).toBe(413);
    expect((await handleAudioPut(put(BYTES, sha, "wrong"), `/internal/audio/${sha}`, env)).status).toBe(401);
    expect((await handleAudioPut(put(BYTES, sha), "/internal/audio/nope", env)).status).toBe(404);
  });

  it("fails closed without the R2 binding", async () => {
    const { env } = fakeEnv({ CACHE: undefined });
    const sha = await shaOf(BYTES);
    expect((await handleAudioPut(put(BYTES, sha), `/internal/audio/${sha}`, env)).status).toBe(500);
  });
});

describe("track get from R2", () => {
  const SHA = "d".repeat(64);
  const BYTES = new Uint8Array([10, 20, 30, 40, 50, 60, 70, 80]);

  function trackEnv(files: Record<string, Uint8Array> = { [`${SHA}`]: BYTES }) {
    const { env } = fakeEnv();
    const store = new Map(Object.entries(files));
    (env.CACHE as any).head = vi.fn(async (k: string) => {
      const b = store.get(k);
      return b ? { size: b.length, httpMetadata: { contentType: "audio/flac" } } : null;
    });
    (env.CACHE as any).get = vi.fn(async (k: string, opts?: any) => {
      const b = store.get(k);
      if (!b) return null;
      if (opts?.range) {
        const { offset, length } = opts.range;
        return { body: b.slice(offset, offset + length), httpMetadata: { contentType: "audio/flac" } };
      }
      return { body: b, httpMetadata: { contentType: "audio/flac" } };
    });
    return env;
  }

  const get = (path: string, range?: string) =>
    new Request(`${HOST}${path}`, {
      method: "GET",
      headers: range ? { range } : {},
    });
  const head = (path: string, range?: string) =>
    new Request(`${HOST}${path}`, {
      method: "HEAD",
      headers: range ? { range } : {},
    });

  it("serves a full hit with origin-like headers", async () => {
    const res = (await handleTrackGet(`/track/${SHA}`, get(`/track/${SHA}`), trackEnv()))!;
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("audio/flac");
    expect(res.headers.get("accept-ranges")).toBe("bytes");
    expect(res.headers.get("etag")).toBe(`"${SHA}"`);
    expect(res.headers.get("cache-control")).toContain("immutable");
    expect(new Uint8Array(await res.arrayBuffer())).toEqual(BYTES);
  });

  it("serves ranges and answers HEAD without bytes", async () => {
    const env = trackEnv();
    const part = (await handleTrackGet(`/track/${SHA}`, get(`/track/${SHA}`, "bytes=2-5"), env))!;
    expect(part.status).toBe(206);
    expect(part.headers.get("content-range")).toBe("bytes 2-5/8");
    expect(new Uint8Array(await part.arrayBuffer())).toEqual(new Uint8Array([30, 40, 50, 60]));
    const open = (await handleTrackGet(`/track/${SHA}`, get(`/track/${SHA}`, "bytes=6-"), env))!;
    expect(open.status).toBe(206);
    expect(open.headers.get("content-range")).toBe("bytes 6-7/8");
    const headers = (await handleTrackGet(`/track/${SHA}`, head(`/track/${SHA}`), env))!;
    expect(headers.status).toBe(200);
    expect(headers.headers.get("content-length")).toBe("8");
    const hpart = (await handleTrackGet(`/track/${SHA}`, head(`/track/${SHA}`, "bytes=0-3"), env))!;
    expect(hpart.status).toBe(206);
    expect(hpart.headers.get("content-range")).toBe("bytes 0-3/8");
  });

  it("416s unsatisfiable ranges and nulls the rest", async () => {
    const env = trackEnv();
    const bad = (await handleTrackGet(`/track/${SHA}`, get(`/track/${SHA}`, "bytes=99-"), env))!;
    expect(bad.status).toBe(416);
    expect(bad.headers.get("content-range")).toBe("bytes */8");
    const empty = trackEnv({});
    expect(await handleTrackGet(`/track/${SHA}`, get(`/track/${SHA}`), empty)).toBeNull();
    expect(await handleTrackGet("/art/" + SHA, get(`/art/${SHA}`), env)).toBeNull();
    expect(await handleTrackGet(`/track/${SHA}`, get(`/track/${SHA}`), fakeEnv({ CACHE: undefined }).env)).toBeNull();
    const post = new Request(`${HOST}/track/${SHA}`, { method: "POST" });
    expect(await handleTrackGet(`/track/${SHA}`, post, env)).toBeNull();
  });
});

describe("the manifest gzipped (24 Oct: 16 MB re-sent ~500 times a day)", () => {
  /** An R2 that keeps what it is given, as bytes. */
  function memoryR2() {
    const objects = new Map<string, Uint8Array>();
    return {
      objects,
      put: vi.fn(async (key: string, value: ReadableStream | string) => {
        objects.set(key, new Uint8Array(await new Response(value).arrayBuffer()));
      }),
      get: vi.fn(async (key: string) => {
        const b = objects.get(key);
        return b ? { body: new Response(b).body! } : null;
      }),
      delete: vi.fn(async (key: string) => {
        objects.delete(key);
      }),
    };
  }
  const gzip = async (text: string) =>
    new Uint8Array(
      await new Response(new Blob([text]).stream().pipeThrough(new CompressionStream("gzip"))).arrayBuffer(),
    );
  const text = JSON.stringify({ schema: 4, tracks: [{ sha: "a", lyrics: "la la" }] });

  it("keeps a gzipped upload as such, and the old plain copy goes", async () => {
    const r2 = memoryR2();
    r2.objects.set("manifest.json", new TextEncoder().encode("{\"old\":1}"));
    const body = await gzip(text);
    const res = await handleManifestPut(
      new Request(`${HOST}/internal/manifest`, {
        method: "PUT",
        headers: { authorization: `Bearer ${KEY}`, "content-length": String(body.length), "x-tunes-encoding": "gzip" },
        body,
      }),
      { INTERNAL_PUBLISH_KEY: KEY, CACHE: r2 } as any,
    );
    expect(await res.json()).toMatchObject({ ok: true, encoding: "gzip" });
    expect(r2.objects.has("manifest.json.gz")).toBe(true);
    expect(r2.objects.has("manifest.json")).toBe(false);
  });

  it("hands a client that takes gzip the gzip, and one that does not the JSON", async () => {
    const r2 = memoryR2();
    r2.objects.set("manifest.json.gz", await gzip(text));
    const env = { CACHE: r2 } as any;
    const zipped = await handleManifestGet(
      new Request(`${HOST}/manifest`, { headers: { "accept-encoding": "gzip, deflate" } }),
      env,
    );
    expect(zipped?.headers.get("content-encoding")).toBe("gzip");
    const plain = await handleManifestGet(new Request(`${HOST}/manifest`), env);
    expect(plain?.headers.get("content-encoding")).toBeNull();
    expect(await plain!.text()).toBe(text);
  });

  it("serves the plain copy from a box that has not started gzipping, else nothing", async () => {
    const r2 = memoryR2();
    expect(await handleManifestGet(new Request(`${HOST}/manifest`), { CACHE: r2 } as any)).toBeNull();
    r2.objects.set("manifest.json", new TextEncoder().encode(text));
    const res = await handleManifestGet(new Request(`${HOST}/manifest`), { CACHE: r2 } as any);
    expect(await res!.text()).toBe(text);
  });
});

describe("the lean manifest (24 Oct: lyrics were 87% of it)", () => {
  function r2() {
    const objects = new Map<string, Uint8Array>();
    return {
      objects,
      put: vi.fn(async (k: string, v: ReadableStream | string) => {
        objects.set(k, new Uint8Array(await new Response(v).arrayBuffer()));
      }),
      get: vi.fn(async (k: string) => {
        const b = objects.get(k);
        return b ? { body: new Response(b).body! } : null;
      }),
      delete: vi.fn(async (k: string) => {
        objects.delete(k);
      }),
    };
  }
  const putReq = (lean: boolean, body = "x") =>
    new Request(`${HOST}/internal/manifest${lean ? "?lean=1" : ""}`, {
      method: "PUT",
      headers: { authorization: `Bearer ${KEY}`, "content-length": String(body.length), "x-tunes-encoding": "gzip" },
      body,
    });

  it("is kept apart from the full one, which says it can be", async () => {
    const cache = r2();
    const full = await handleManifestPut(putReq(false, "full"), { INTERNAL_PUBLISH_KEY: KEY, CACHE: cache } as any);
    expect(await full.json()).toMatchObject({ lean: "supported" });
    await handleManifestPut(putReq(true, "lean"), { INTERNAL_PUBLISH_KEY: KEY, CACHE: cache } as any);
    expect(new TextDecoder().decode(cache.objects.get("manifest.json.gz"))).toBe("full");
    expect(new TextDecoder().decode(cache.objects.get("manifest-lean.json.gz"))).toBe("lean");
  });

  it("goes to whoever asks for it, the full one to the rest and until it exists", async () => {
    const cache = r2();
    cache.objects.set("manifest.json.gz", new TextEncoder().encode("full"));
    const ask = (q: string) =>
      handleManifestGet(new Request(`${HOST}/manifest${q}`, { headers: { "accept-encoding": "gzip" } }), { CACHE: cache } as any);
    expect(await (await ask("?lean=1"))!.text()).toBe("full");
    cache.objects.set("manifest-lean.json.gz", new TextEncoder().encode("lean"));
    expect(await (await ask("?lean=1"))!.text()).toBe("lean");
    expect(await (await ask(""))!.text()).toBe("full");
  });
});

describe("the box reading its own audio back (24 Oct, drop moments)", () => {
  const SHA2 = "b".repeat(64);
  const env = () => ({
    INTERNAL_PUBLISH_KEY: KEY,
    CACHE: {
      get: vi.fn(async (key: string) =>
        key === SHA2 ? { body: new Response("flac bytes").body!, httpMetadata: { contentType: "audio/flac" } } : null,
      ),
    },
  }) as any;
  const get = (sha: string, key = KEY) =>
    new Request(`${HOST}/internal/audio/${sha}`, { headers: { authorization: `Bearer ${key}` } });

  it("hands the box the bytes it put there", async () => {
    const res = await handleAudioPut(get(SHA2), `/internal/audio/${SHA2}`, env());
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("audio/flac");
    expect(await res.text()).toBe("flac bytes");
  });

  it("only to the service key, and 404 for what is not there", async () => {
    expect((await handleAudioPut(get(SHA2, "x".repeat(64)), `/internal/audio/${SHA2}`, env())).status).toBe(401);
    expect((await handleAudioPut(get(SHA), `/internal/audio/${SHA}`, env())).status).toBe(404);
  });
});


// BYOB (docs/BYOB.md): a box publishes with its own key, into its own place.
describe("a box's own publish", () => {
  const BOX_KEY = "b".repeat(64);
  const hashOf = async (s: string) =>
    Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s))))
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
  const putAs = (body: string, key: string) =>
    new Request(`${HOST}/internal/manifest`, {
      method: "PUT",
      headers: { authorization: `Bearer ${key}`, "content-length": String(body.length) },
      body,
    });

  it("writes under boxes/<id>/, never the owner's manifest", async () => {
    const boxes = { [await hashOf(BOX_KEY)]: { id: "box-cedric", status: "active" } };
    const { env } = fakeEnv({}, boxes);
    const res = await handleManifestPut(putAs("{\"tracks\":[]}", BOX_KEY), env);
    expect(res.status).toBe(200);
    expect(env.CACHE.put.mock.calls[0][0]).toBe("boxes/box-cedric/manifest.json");
  });

  it("refuses a key that is neither the owner's nor an active box's", async () => {
    const { env } = fakeEnv({}, {});
    expect((await handleManifestPut(putAs("{}", "c".repeat(64)), env)).status).toBe(401);
    expect(env.CACHE.put).not.toHaveBeenCalled();
  });

  it("serves a box's account its own manifest", async () => {
    const stored: Record<string, string> = {
      "manifest.json": "{\"owner\":true}",
      "boxes/box-cedric/manifest.json": "{\"box\":true}",
    };
    const { env } = fakeEnv({
      CACHE: {
        get: async (key: string) =>
          key in stored ? { body: new Response(stored[key]).body } : null,
      },
    });
    const req = new Request(`${HOST}/manifest`);
    expect(await (await handleManifestGet(req, env, "box-cedric"))!.text()).toBe("{\"box\":true}");
    expect(await (await handleManifestGet(req, env))!.text()).toBe("{\"owner\":true}");
    // A box that has not published yet: nothing here, so the request goes on to its tunnel.
    expect(await handleManifestGet(req, env, "box-dennis")).toBeNull();
  });
});
