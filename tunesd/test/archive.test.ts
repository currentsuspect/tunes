import { mkdtemp, rm, utimes, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { archiveAll, evictable, fileNameFor, needsArchive } from "../src/archive.js";
import { State } from "../src/state.js";
import { ObjectStore } from "../src/store.js";

let dir: string;
let store: ObjectStore;
let state: State;
const CH = "-100";

async function put(text: string, ageMin: number): Promise<string> {
  const s = await store.beginStaging();
  await writeFile(s.path, text);
  const { sha } = await s.done(text.length);
  const t = new Date(Date.now() - ageMin * 60_000);
  await utimes(store.pathOf(sha), t, t);
  return sha;
}

beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), "tunes-archive-"));
  store = new ObjectStore(dir);
  state = await new State(join(dir, "state.json")).load();
});
afterEach(async () => rm(dir, { recursive: true, force: true }));

describe("cache: evicts only what Telegram still holds", () => {
  it("least recently played first, never a song only here", async () => {
    const old = await put("a".repeat(100), 60);
    const onlyHere = await put("b".repeat(100), 90);
    const fresh = await put("c".repeat(100), 1);
    state.markSeen(CH, 1, old);
    state.markSeen(CH, 2, fresh);
    state.data.auditedAt = new Date().toISOString();
    const r = await store.prune(200, evictable(state, [CH]));
    expect(store.has(old)).toBe(false);
    expect(store.has(onlyHere)).toBe(true); // oldest, but the only copy
    expect(store.has(fresh)).toBe(true);
    expect(r.removed).toBe(1);
  });

  it("without a recent audit nothing is evicted", async () => {
    const a = await put("a".repeat(100), 60);
    state.markSeen(CH, 1, a);
    state.data.auditedAt = new Date(Date.now() - 30 * 86400_000).toISOString();
    await store.prune(0, evictable(state, [CH]));
    expect(store.has(a)).toBe(true);
    state.data.auditedAt = null;
    await store.prune(0, evictable(state, [CH]));
    expect(store.has(a)).toBe(true);
  });

  it("a gone source does not count, nor a channel tunesd does not read", async () => {
    const a = await put("a".repeat(100), 60);
    const b = await put("b".repeat(100), 60);
    state.markSeen(CH, 1, a);
    state.markGone(CH, 1);
    state.markSeen("-999", 5, b);
    state.data.auditedAt = new Date().toISOString();
    await store.prune(0, evictable(state, [CH]));
    expect(store.has(a)).toBe(true);
    expect(store.has(b)).toBe(true);
  });

  it("a song streaming right now stays", async () => {
    const a = await put("a".repeat(100), 60);
    state.markSeen(CH, 1, a);
    state.data.auditedAt = new Date().toISOString();
    const release = store.beginRead(a);
    await store.prune(0, evictable(state, [CH]));
    expect(store.has(a)).toBe(true);
    release();
    await store.prune(0, evictable(state, [CH]));
    expect(store.has(a)).toBe(false);
  });
});

describe("archive: songs only here go up to Telegram", () => {
  it("skips what is live, and duplicates of live audio", () => {
    const todo = needsArchive(
      [
        { sha: "live", size: 1 },
        { sha: "dupe", size: 1 },
        { sha: "only", size: 1 },
      ],
      new Set(["live"]),
      (s) => ({ live: "A", dupe: "A", only: "B" })[s],
    );
    expect(todo.map((t) => t.sha)).toEqual(["only"]);
    // A file the ledger marks redundant is never uploaded.
    expect(needsArchive([{ sha: "only", size: 1 }], new Set(), () => undefined, new Set(["only"]))).toEqual([]);
  });

  it("records each upload as seen, only when the size matches", async () => {
    const a = await put("a".repeat(100), 1);
    const b = await put("b".repeat(50), 1);
    let next = 10;
    const sent: string[] = [];
    const r = await archiveAll(
      {
        store,
        state,
        archiveChat: Number(CH),
        tg: {
          uploadAudio: async (_chat, _path, meta) => {
            sent.push(meta.fileName);
            const id = next++;
            // The second upload comes back short: not recorded.
            return { messageId: id, size: id === 10 ? 100 : 49 };
          },
        },
        meta: () => ({ artist: "Yeat", title: "ON NOTHING", codec: "flac" }),
        log: { info: () => {}, warn: () => {} },
        sleep: async () => {},
      },
      [
        { sha: a, size: 100 },
        { sha: b, size: 50 },
      ],
      { max: 10, pauseMs: 0 },
    );
    expect(r).toEqual({ uploaded: 1, failed: 1, bytes: 100 });
    expect(state.seenSha(CH, 10)).toBe(a);
    expect(state.seenSha(CH, 11)).toBeNull();
    expect(sent[0]).toBe("Yeat - ON NOTHING.flac");
  });

  it("stops at a transport error; the next pass carries on", async () => {
    const a = await put("a".repeat(10), 1);
    const b = await put("b".repeat(10), 1);
    let calls = 0;
    const r = await archiveAll(
      {
        store,
        state,
        archiveChat: Number(CH),
        tg: {
          uploadAudio: async () => {
            calls++;
            throw new Error("FLOOD_WAIT_30");
          },
        },
        meta: () => undefined,
        log: { info: () => {}, warn: () => {} },
        sleep: async () => {},
      },
      [
        { sha: a, size: 10 },
        { sha: b, size: 10 },
      ],
      { max: 10, pauseMs: 0 },
    );
    expect(calls).toBe(1);
    expect(r.uploaded).toBe(0);
  });

  it("names files people can read", () => {
    expect(fileNameFor("abc", { artist: "A/B", title: "x: y", codec: "mp3" })).toBe("A B - x y.mp3");
    expect(fileNameFor("abcdef0123456789zz", undefined)).toBe("abcdef0123456789.bin");
  });
});
