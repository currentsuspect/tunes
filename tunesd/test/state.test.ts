import { mkdtemp, rm, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { State } from "../src/state.js";

let dir: string;
let path: string;

beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), "tunes-state-"));
  path = join(dir, "state.json");
});

afterEach(async () => {
  await rm(dir, { recursive: true, force: true });
});

describe("State", () => {
  it("round-trips seen marks and cursors", async () => {
    const s = await new State(path).load();
    s.markSeen("42", 7, "abc", "caption", "file.flac");
    s.setCursor("42", { headCursor: 7, lastScanAt: "2026-08-27T00:00:00Z" });
    await s.save();

    const s2 = await new State(path).load();
    expect(s2.hasSeen("42", 7)).toBe(true);
    expect(s2.seenSha("42", 7)).toBe("abc");
    const meta = s2.seenMeta("42", 7);
    expect(meta?.caption).toBe("caption");
    expect(meta?.fileName).toBe("file.flac");
    expect(s2.cursorOf("42").headCursor).toBe(7);
  });

  it("loads legacy string-form seen entries without losing them", async () => {
    const legacy = JSON.stringify({
      schema: 1,
      channels: {},
      seen: { "42:7": "abc123" },
      dailyFetched: 0,
      dailyDate: "2026-08-27",
    });
    await (await import("node:fs/promises")).writeFile(path, legacy);
    const s = await new State(path).load();
    expect(s.seenSha("42", 7)).toBe("abc123");
    expect(s.seenMeta("42", 7)).toEqual({ sha: "abc123", caption: null, fileName: null });
  });

  it("rolls the daily tally over at midnight", async () => {
    const s = await new State(path).load();
    const data = (s as unknown as { data: { dailyDate: string } }).data;
    data.dailyDate = "2000-01-01";
    expect(s.dailyRemaining(100)).toBe(100);
    s.tallyFetch();
    expect(s.dailyRemaining(100)).toBe(99);
  });

  it("loads a corrupt state file as fresh, never crashes", async () => {
    await (await import("node:fs/promises")).writeFile(path, "not json");
    const s = await new State(path).load();
    expect(s.cursorOf("1").headCursor).toBe(0);
    expect(s.allSeenShas()).toEqual([]);
  });

  it("stamps addedAt on first markSeen and preserves it across re-marks", async () => {
    const s = await new State(path).load();
    s.markSeen("42", 7, "abc", null, null);
    const first = s.addedAtFor("abc");
    expect(first).not.toBeNull();

    s.markSeen("42", 7, "abc", "different caption", null);
    const second = s.addedAtFor("abc");
    expect(second).toBe(first);
  });

  it("resets addedAt when the same message points at a new sha", async () => {
    const s = await new State(path).load();
    s.markSeen("42", 7, "abc", null, null);
    const original = s.addedAtFor("abc");
    expect(original).not.toBeNull();

    // Mutate the prior entry's addedAt to a known past value, then re-mark
    // with a new sha. The fresh stamp must overwrite that past value.
    const past = "2020-01-01T00:00:00.000Z";
    const internal = s as unknown as {
      data: { seen: Record<string, { addedAt: string }> };
    };
    const entry = internal.data.seen["42:7"]!;
    entry.addedAt = past;
    expect(s.addedAtFor("abc")).toBe(past);

    s.markSeen("42", 7, "xyz", null, null);
    const fresh = s.addedAtFor("xyz");
    expect(fresh).not.toBeNull();
    expect(fresh === past).toBe(false);
    // Old sha's addedAt is no longer reachable from this key.
    expect(s.addedAtFor("abc")).toBeNull();
  });

  it("allAddedAt returns one entry per unique sha, first-seen wins", async () => {
    const s = await new State(path).load();
    s.markSeen("42", 1, "sha-a", null, null);
    s.markSeen("42", 2, "sha-a", null, null);
    s.markSeen("42", 3, "sha-b", null, null);
    const all = s.allAddedAt();
    expect(all.size).toBe(2);
    expect(all.has("sha-a")).toBe(true);
    expect(all.has("sha-b")).toBe(true);
  });
});
describe("State.channelIdsSeen / sightingsFor across retired channels", () => {
  it("includes a channel that is no longer configured", async () => {
    const dir = await mkdtemp(join(tmpdir(), "state-"));
    try {
      const s = await new State(join(dir, "state.json")).load();
      s.markSeen("-100", 1, "a".repeat(64), "c", "f");
      s.markSeen("-200", 2, "b".repeat(64), "c", "f");
      expect(s.channelIdsSeen().sort()).toEqual(["-100", "-200"]);
      // The old rule: only the configured channel.
      expect(s.sightingsFor(["-200"]).map((r) => r.sha)).toEqual(["b".repeat(64)]);
      // The new rule: everything ever seen.
      expect(s.sightingsFor(s.channelIdsSeen()).map((r) => r.sha).sort()).toEqual(["a".repeat(64), "b".repeat(64)]);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});
