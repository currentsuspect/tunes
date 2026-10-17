import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { auditDue, auditSources } from "../src/audit.js";
import { State } from "../src/state.js";
import { RetryableError } from "../src/telegram/ports.js";

const log = { info: () => {}, warn: () => {}, error: () => {}, debug: () => {} } as any;

let dir: string;
let state: State;

beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), "tunes-audit-"));
  state = await new State(join(dir, "state.json")).load();
  for (let m = 1; m <= 250; m++) state.markSeen("-7", m, m.toString(16).padStart(64, "0"), null, null);
});

afterEach(async () => {
  await rm(dir, { recursive: true, force: true });
});

describe("auditSources", () => {
  it("asks in batches of 100 and records what is gone", async () => {
    const calls: number[][] = [];
    const gone = new Set([7, 150, 249]);
    const r = await auditSources(
      { missingAudio: async (_c, ids) => (calls.push(ids), ids.filter((i) => gone.has(i))) },
      state,
      log,
      { channelIds: ["-7"], pause: () => 0 }
    );
    expect(calls.map((c) => c.length)).toEqual([100, 100, 50]);
    expect(r).toEqual({ checked: 250, gone: 3, stopped: false });
    expect(state.isGone("-7", 150)).toBe(true);
    expect(state.isGone("-7", 151)).toBe(false);
    expect(state.liveSightingsFor(["-7"])).toHaveLength(247);
    expect(state.data.auditedAt).toBeTruthy();
  });

  it("does not ask again about sources already known gone", async () => {
    state.markGone("-7", 1);
    const asked: number[] = [];
    await auditSources(
      { missingAudio: async (_c, ids) => (asked.push(...ids), []) },
      state,
      log,
      { channelIds: ["-7"], pause: () => 0 }
    );
    expect(asked).not.toContain(1);
    expect(asked).toHaveLength(249);
  });

  it("stops on a transport error and keeps what it learned", async () => {
    let n = 0;
    const r = await auditSources(
      {
        missingAudio: async (_c, ids) => {
          n += 1;
          if (n === 2) throw new RetryableError("link down");
          return [ids[0]!];
        },
      },
      state,
      log,
      { channelIds: ["-7"], pause: () => 0 }
    );
    expect(r).toEqual({ checked: 100, gone: 1, stopped: true });
    expect(n).toBe(2);
    expect(state.isGone("-7", 1)).toBe(true);
    expect(state.data.auditedAt ?? null).toBeNull();
  });

  it("runs about once a week", () => {
    const now = new Date("2026-10-16T12:00:00Z");
    expect(auditDue(null, now)).toBe(true);
    expect(auditDue("2026-10-15T12:00:00Z", now)).toBe(false);
    expect(auditDue("2026-10-08T12:00:00Z", now)).toBe(true);
  });
});
