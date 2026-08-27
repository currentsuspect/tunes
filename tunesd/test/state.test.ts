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
});