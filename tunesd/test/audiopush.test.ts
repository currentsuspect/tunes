import { describe, expect, it } from "vitest";
import { AudioPusher } from "../src/audiopush.js";

const log = { info() {}, warn() {}, error() {}, debug() {} } as any;
const sha = (n: number) => n.toString(16).padStart(64, "0");

function setup(opts: { fail?: Set<string>; missing?: Set<string> } = {}) {
  const sent: string[] = [];
  const tries: string[] = [];
  const saves: number[] = [];
  let active = 0;
  let peak = 0;
  let t = 1_000_000;
  const ledger: Record<string, string> = {};
  const p = new AudioPusher(ledger, {
    log,
    now: () => t,
    retryAfterMs: 1000,
    read: async (s) => (opts.missing?.has(s) ? null : new Uint8Array([1, 2, 3])),
    put: async (s) => {
      tries.push(s);
      active++;
      peak = Math.max(peak, active);
      await new Promise((r) => setTimeout(r, 2));
      active--;
      if (opts.fail?.has(s)) return false;
      sent.push(s);
      return true;
    },
    save: async (l) => void saves.push(Object.keys(l).length),
  });
  return { p, sent, tries, saves, ledger, peak: () => peak, tick: (ms: number) => (t += ms) };
}

describe("AudioPusher", () => {
  it("sends one at a time, in the order given", async () => {
    const s = setup();
    s.p.enqueue([sha(1), sha(2), sha(3)]);
    await s.p.idle();
    expect(s.sent).toEqual([sha(1), sha(2), sha(3)]);
    expect(s.peak()).toBe(1);
  });

  it("records what was sent and never sends it twice", async () => {
    const s = setup();
    s.p.enqueue([sha(1)]);
    await s.p.idle();
    s.p.enqueue([sha(1), sha(2)]);
    await s.p.idle();
    expect(s.sent).toEqual([sha(1), sha(2)]);
    expect(Object.keys(s.ledger)).toEqual([sha(1), sha(2)]);
    expect(s.saves.at(-1)).toBe(2);
  });

  it("puts newly enqueued tracks ahead of an older backlog", async () => {
    const s = setup();
    s.p.enqueue([sha(1), sha(2), sha(3)]);
    s.p.enqueue([sha(9)]);
    await s.p.idle();
    expect(s.sent[0]).toBe(sha(1)); // already in flight
    expect(s.sent[1]).toBe(sha(9));
  });

  it("skips files it does not hold without failing the run", async () => {
    const s = setup({ missing: new Set([sha(1)]) });
    s.p.enqueue([sha(1), sha(2)]);
    await s.p.idle();
    expect(s.sent).toEqual([sha(2)]);
    expect(s.ledger[sha(1)]).toBeUndefined();
  });

  it("leaves a rejected file off the ledger and waits before retrying it", async () => {
    const s = setup({ fail: new Set([sha(1)]) });
    s.p.enqueue([sha(1)]);
    await s.p.idle();
    expect(s.ledger[sha(1)]).toBeUndefined();
    s.p.enqueue([sha(1)]); // too soon: ignored
    await s.p.idle();
    s.tick(2000);
    s.p.enqueue([sha(1)]); // now allowed
    await s.p.idle();
    expect(s.tries).toEqual([sha(1), sha(1)]); // not hammered: one retry, after the wait
  });
});
