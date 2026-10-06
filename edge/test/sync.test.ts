// @ts-nocheck -- runs the real migration on node's built-in SQLite; the Workers
// type set has no node types, and this file is the only one that needs them.
import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import { beforeEach, describe, expect, it } from "vitest";
import { signAccessToken } from "../src/crypto.js";
import { handleSync, MAX_DOCS_PER_PUSH } from "../src/sync.js";

// `node:sqlite` has no un-prefixed name, which vite cannot resolve; require it.
const { DatabaseSync } = createRequire(import.meta.url)("node:sqlite");
type DatabaseSync = any;

const SECRET = "s".repeat(64);
const HOST = "https://tunes.aestra.studio";
const SHA = "a".repeat(64);
const SHB = "b".repeat(64);

/** Just enough of D1 over a real SQLite, so the SQL under test is really run. */
function d1(db: DatabaseSync): D1Database {
  const stmt = (sql: string, args: unknown[] = []) => ({
    bind: (...a: unknown[]) => stmt(sql, a),
    first: async () => (db.prepare(sql).get(...(args as any[])) as any) ?? null,
    all: async () => ({ results: db.prepare(sql).all(...(args as any[])) as any[] }),
    run: async () => db.prepare(sql).run(...(args as any[])),
    _run: () => db.prepare(sql).run(...(args as any[])),
  });
  return {
    prepare: (sql: string) => stmt(sql),
    batch: async (stmts: any[]) => {
      db.exec("BEGIN");
      try {
        for (const s of stmts) s._run();
        db.exec("COMMIT");
      } catch (e) {
        db.exec("ROLLBACK");
        throw e;
      }
      return [];
    },
  } as unknown as D1Database;
}

let db: DatabaseSync;
let env: { DB: D1Database; ACCESS_SECRET: string };

async function token(account: string, device: string) {
  const now = Math.floor(Date.now() / 1000);
  return signAccessToken({ sub: account, did: device, iat: now, exp: now + 600 }, SECRET);
}

async function push(account: string, device: string, docs: unknown[], nowMs = Date.now()) {
  const res = await handleSync(
    new Request(`${HOST}/sync/push`, {
      method: "POST",
      headers: { authorization: `Bearer ${await token(account, device)}` },
      body: JSON.stringify({ docs }),
    }),
    env,
    nowMs,
  );
  return res!;
}

async function pull(account: string, device: string, after = 0, live = false) {
  const res = await handleSync(
    new Request(`${HOST}/sync/pull?after=${after}${live ? "&only=live" : ""}`, {
      headers: { authorization: `Bearer ${await token(account, device)}` },
    }),
    env,
    Date.now(),
  );
  return { res: res!, body: (await res!.json()) as any };
}

const like = (sha: string, at: number, deleted = false) => ({
  key: `like:${sha}`,
  value: deleted ? null : "1",
  deleted,
  updatedAt: at,
});

beforeEach(() => {
  db = new DatabaseSync(":memory:");
  db.exec(readFileSync(new URL("../migrations/0001_init.sql", import.meta.url), "utf8"));
  db.exec(readFileSync(new URL("../migrations/0005_sync.sql", import.meta.url), "utf8"));
  const t = 1;
  db.prepare("INSERT INTO account (id,label,status,created_at) VALUES ('acct-1','one','active',?)").run(t);
  db.prepare("INSERT INTO account (id,label,status,created_at) VALUES ('acct-2','two','active',?)").run(t);
  db.prepare(
    "INSERT INTO device (id,account_id,label,refresh_hash,status,created_at) VALUES ('dev-phone','acct-1','Phone','h1','active',?)",
  ).run(t);
  db.prepare(
    "INSERT INTO device (id,account_id,label,refresh_hash,status,created_at) VALUES ('dev-laptop','acct-1','Laptop','h2','active',?)",
  ).run(t);
  env = { DB: d1(db), ACCESS_SECRET: SECRET };
});

describe("sync", () => {
  it("refuses a request with no token, and does not touch other routes", async () => {
    const res = await handleSync(new Request(`${HOST}/sync/pull`), env, Date.now());
    expect(res!.status).toBe(401);
    expect(await handleSync(new Request(`${HOST}/manifest`), env, Date.now())).toBeNull();
  });

  it("a new device pulls what another pushed, from the start", async () => {
    await push("acct-1", "dev-phone", [like(SHA, 1000), like(SHB, 2000)]);
    const { body } = await pull("acct-1", "dev-laptop");
    expect(body.docs.map((d: any) => d.key)).toEqual([`like:${SHA}`, `like:${SHB}`]);
    expect(body.devices["dev-phone"]).toBe("Phone");
    expect(body.more).toBe(false);
  });

  it("pulling after a number returns only what is newer", async () => {
    await push("acct-1", "dev-phone", [like(SHA, 1000)]);
    const first = (await pull("acct-1", "dev-laptop")).body;
    await push("acct-1", "dev-phone", [like(SHB, 2000)]);
    const next = (await pull("acct-1", "dev-laptop", first.next)).body;
    expect(next.docs.map((d: any) => d.key)).toEqual([`like:${SHB}`]);
  });

  it("the newer write wins, whichever arrives last", async () => {
    await push("acct-1", "dev-phone", [like(SHA, 5000)]);
    await push("acct-1", "dev-laptop", [like(SHA, 3000, true)]); // older unlike, late
    const { body } = await pull("acct-1", "dev-laptop");
    expect(body.docs[0].deleted).toBe(false);
    await push("acct-1", "dev-laptop", [like(SHA, 9000, true)]); // newer unlike
    const after = (await pull("acct-1", "dev-phone", body.next)).body;
    expect(after.docs[0].deleted).toBe(true);
    expect(after.docs[0].value).toBeNull();
  });

  it("a losing write does not make news for other devices", async () => {
    await push("acct-1", "dev-phone", [like(SHA, 5000)]);
    const a = (await pull("acct-1", "dev-laptop")).body;
    await push("acct-1", "dev-laptop", [like(SHA, 1000, true)]);
    const b = (await pull("acct-1", "dev-phone", a.next)).body;
    expect(b.docs).toEqual([]);
  });

  it("accounts cannot see each other", async () => {
    await push("acct-1", "dev-phone", [like(SHA, 1000)]);
    const other = (await pull("acct-2", "dev-x")).body;
    expect(other.docs).toEqual([]);
  });

  it("rejects keys that are not ours to store, and oversize pushes", async () => {
    expect((await push("acct-1", "dev-phone", [{ key: "anything", value: "x", deleted: false, updatedAt: 1 }])).status).toBe(400);
    const many = Array.from({ length: MAX_DOCS_PER_PUSH + 1 }, () => like(SHA, 1));
    expect((await push("acct-1", "dev-phone", many)).status).toBe(400);
  });

  it("a clock far in the future cannot win every conflict for ever", async () => {
    const now = 1_000_000;
    await push("acct-1", "dev-phone", [like(SHA, now + 10 * 24 * 3600 * 1000)], now);
    // a sane device writing a minute later must beat the clamped write
    await push("acct-1", "dev-laptop", [like(SHA, now + 120_000, true)], now + 120_000);
    const { body } = await pull("acct-1", "dev-phone");
    expect(body.docs[0].deleted).toBe(true);
  });

  it("accepts a device's listening for a day, and nothing looser", async () => {
    const dev = "11111111-2222-4333-8444-555555555555";
    const ok = { key: `plays:${dev}:20261005`, value: "[]", deleted: false, updatedAt: 1 };
    expect((await push("acct-1", "dev-phone", [ok])).status).toBe(200);
    const bad = { ...ok, key: `plays:${dev}:today` };
    expect((await push("acct-1", "dev-phone", [bad])).status).toBe(400);
  });

  it("the live lane returns only where it is playing, the queue and commands", async () => {
    const cmd = { key: "cmd", value: '{"id":"1"}', deleted: false, updatedAt: 5 };
    const now = { key: "now", value: "{}", deleted: false, updatedAt: 6 };
    await push("acct-1", "dev-phone", [like(SHA, 1000), cmd, now]);
    const all = (await pull("acct-1", "dev-laptop")).body;
    expect(all.docs.length).toBe(3);
    const fast = (await pull("acct-1", "dev-laptop", 0, true)).body;
    expect(fast.docs.map((d: any) => d.key).sort()).toEqual(["cmd", "now"]);
  });

  it("pages a long pull", async () => {
    const docs = Array.from({ length: 150 }, (_, i) => like(i.toString(16).padStart(64, "0"), 1000 + i));
    await push("acct-1", "dev-phone", docs);
    await push("acct-1", "dev-phone", docs.slice(0, 1).map((d) => ({ ...d, updatedAt: 99999 })));
    const { body } = await pull("acct-1", "dev-laptop");
    expect(body.docs.length).toBe(150);
  });
});
