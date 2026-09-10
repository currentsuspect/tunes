import { describe, expect, it, vi } from "vitest";
import { handlePublish } from "../src/publish.js";

const KEY = "k".repeat(64);
const HOST = "https://tunes.aestra.studio";
const SHA = "a".repeat(64);

function fakeEnv(over: Record<string, unknown> = {}) {
  const puts: { key: string; value: string }[] = [];
  const batches: unknown[][] = [];
  return {
    env: {
      INTERNAL_PUBLISH_KEY: KEY,
      DB: {
        prepare: (sql: string) => ({
          bind: (...args: unknown[]) => ({ sql, args }),
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
