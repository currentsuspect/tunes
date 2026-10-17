import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { OnDemandFetcher } from "../src/ondemand.js";
import { ObjectStore } from "../src/store.js";
import { State } from "../src/state.js";
import { RetryableError, PermanentError, SourceGoneError } from "../src/telegram/ports.js";

const log = {
  info: () => {},
  warn: () => {},
  error: () => {},
  debug: () => {},
} as any;

let dir: string;
let store: ObjectStore;
let state: State;

const BYTES = Buffer.from("on-demand audio bytes");

async function shaOf(): Promise<string> {
  const staging = await store.beginStaging();
  await writeFile(staging.path, BYTES);
  const { sha } = await staging.done(BYTES.length);
  return sha;
}

function client(
  download: (chat: number, msg: number, out: string) => Promise<number>,
) {
  return { downloadAudioTo: vi.fn(download) } as any;
}

function okClient() {
  return client(async (_chat, _msg, out) => {
    await writeFile(out, BYTES);
    return BYTES.length;
  });
}

beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), "tunes-ondemand-"));
  store = new ObjectStore(dir);
  state = await new State(join(dir, "state.json")).load();
});

afterEach(async () => {
  await rm(dir, { recursive: true, force: true });
});

describe("OnDemandFetcher", () => {
  it("serves a store hit without touching Telegram", async () => {
    const sha = await shaOf();
    const c = okClient();
    const f = new OnDemandFetcher(c, store, state, { dailyCapFiles: 10 }, log);
    expect(await f.fetchTrack(sha)).toBe(store.pathOf(sha));
    expect(c.downloadAudioTo).not.toHaveBeenCalled();
  });

  it("fetches a miss from its source message and commits it", async () => {
    const staging = await store.beginStaging();
    await writeFile(staging.path, BYTES);
    const { sha } = await staging.done(BYTES.length);
    // The object exists now; remove it to simulate the miss. The seen index
    // still knows which message holds it.
    const { rm: rmFile } = await import("node:fs/promises");
    await rmFile(store.pathOf(sha));
    expect(store.has(sha)).toBe(false);

    state.markSeen("-99", 41, sha, null, null);
    await state.save();

    const c = okClient();
    const before = state.dailyRemaining(10);
    const f = new OnDemandFetcher(c, store, state, { dailyCapFiles: 10 }, log);
    const path = await f.fetchTrack(sha);
    expect(path).toBe(store.pathOf(sha));
    expect(store.has(sha)).toBe(true);
    expect(c.downloadAudioTo).toHaveBeenCalledWith(-99, 41, expect.any(String));
    // A human tap counts against the same daily cap as the crawler.
    expect(state.dailyRemaining(10)).toBe(before - 1);
  });

  it("answers null for a sha no message holds", async () => {
    const c = okClient();
    const f = new OnDemandFetcher(c, store, state, { dailyCapFiles: 10 }, log);
    expect(await f.fetchTrack("f".repeat(64))).toBeNull();
    expect(c.downloadAudioTo).not.toHaveBeenCalled();
  });

  it("rejects malformed shas without touching anything", async () => {
    const c = okClient();
    const f = new OnDemandFetcher(c, store, state, { dailyCapFiles: 10 }, log);
    expect(await f.fetchTrack("nope")).toBeNull();
    expect(c.downloadAudioTo).not.toHaveBeenCalled();
  });

  it("answers null when the cap is exhausted", async () => {
    const sha = "e".repeat(64);
    state.markSeen("-99", 42, sha, null, null);
    const c = okClient();
    const f = new OnDemandFetcher(c, store, state, { dailyCapFiles: 0 }, log);
    expect(await f.fetchTrack(sha)).toBeNull();
    expect(c.downloadAudioTo).not.toHaveBeenCalled();
  });

  it("answers null on bytes for somebody else, without serving them", async () => {
    const wanted = "d".repeat(64);
    state.markSeen("-99", 43, wanted, null, null);
    const c = okClient(); // serves BYTES, whose sha is not `wanted`
    const f = new OnDemandFetcher(c, store, state, { dailyCapFiles: 10 }, log);
    expect(await f.fetchTrack(wanted)).toBeNull();
    expect(store.has(wanted)).toBe(false);
  });

  it("coalesces concurrent requests for the same sha into one download", async () => {
    const sha = "c".repeat(64);
    state.markSeen("-99", 44, sha, null, null);
    const c = client(async (_chat, _msg, out) => {
      await new Promise((r) => setTimeout(r, 20));
      await writeFile(out, BYTES);
      return BYTES.length;
    });
    const f = new OnDemandFetcher(c, store, state, { dailyCapFiles: 10 }, log);
    // Singleflight is about the download count: both callers share one
    // flight and get the same answer (here null -- these bytes mismatch).
    const [a, b] = await Promise.all([f.fetchTrack(sha), f.fetchTrack(sha)]);
    expect(c.downloadAudioTo).toHaveBeenCalledTimes(1);
    expect(a).toBe(b);
  });

  it("stops and reports on transport errors instead of retrying hot", async () => {
    const sha = "b".repeat(64);
    state.markSeen("-99", 45, sha, null, null);
    const c = client(async () => {
      throw new RetryableError("flood");
    });
    const f = new OnDemandFetcher(c, store, state, { dailyCapFiles: 10 }, log);
    expect(await f.fetchTrack(sha)).toBeNull();
    expect(c.downloadAudioTo).toHaveBeenCalledTimes(1);
    expect(store.has(sha)).toBe(false);
  });

  it("treats a gone source message as a miss, not a crash", async () => {
    const sha = "a".repeat(64);
    state.markSeen("-99", 46, sha, null, null);
    const c = client(async () => {
      throw new PermanentError("Source message 46 not found in -99");
    });
    const f = new OnDemandFetcher(c, store, state, { dailyCapFiles: 10 }, log);
    expect(await f.fetchTrack(sha)).toBeNull();
  });

  it("tries the next source when the first is dead", async () => {
    const sha = await shaOf();
    const { rm: rmFile } = await import("node:fs/promises");
    await rmFile(store.pathOf(sha));
    // Old channel row first (dead), live channel row second (holds it).
    state.markSeen("-1", 1, sha, null, null);
    state.markSeen("-99", 2, sha, null, null);
    await state.save();
    const seen: number[] = [];
    const c = client(async (_chat, msg, out) => {
      seen.push(msg);
      if (msg === 1) {
        throw new PermanentError("Source message 1 not found in -1");
      }
      await writeFile(out, BYTES);
      return BYTES.length;
    });
    const f = new OnDemandFetcher(c, store, state, { dailyCapFiles: 10 }, log);
    expect(await f.fetchTrack(sha)).toBe(store.pathOf(sha));
    expect(seen).toEqual([1, 2]);
  });
});

describe("State.findMessage", () => {
  it("resolves a sha back to its message", async () => {
    state.markSeen("-99", 7, "abc", null, null);
    expect(state.findMessage("abc")).toEqual({
      channelId: "-99",
      messageId: 7,
    });
  });

  it("lists every source oldest first", async () => {
    state.markSeen("-1", 1, "abc", null, null);
    state.markSeen("-99", 2, "abc", null, null);
    expect(state.findMessages("abc")).toEqual([
      { channelId: "-1", messageId: 1 },
      { channelId: "-99", messageId: 2 },
    ]);
  });

  it("returns null for unknown shas", async () => {
    expect(state.findMessage("zzz")).toBeNull();
  });

  it("remembers a source that is gone and does not ask Telegram again", async () => {
    const sha = "e".repeat(64);
    state.markSeen("-99", 5328, sha, null, null);
    const c = client(async () => {
      throw new SourceGoneError("Source message 5328 not found in -99");
    });
    const f = new OnDemandFetcher(c, store, state, { dailyCapFiles: 10 }, log);
    let told = 0;
    f.onGone = () => {
      told += 1;
    };
    expect(await f.fetchTrack(sha)).toBeNull();
    expect(state.isGone("-99", 5328)).toBe(true);
    expect(told).toBe(1);
    expect(await f.fetchTrack(sha)).toBeNull();
    expect(c.downloadAudioTo).toHaveBeenCalledTimes(1);
    const reloaded = await new State(join(dir, "state.json")).load();
    expect(reloaded.isGone("-99", 5328)).toBe(true);
  });
});
