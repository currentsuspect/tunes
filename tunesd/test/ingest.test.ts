import { describe, expect, it, vi } from "vitest";
import { Wake, coalesce } from "../src/ingest.js";

describe("Wake", () => {
  it("falls back to the poll when nothing is pushed", async () => {
    const w = new Wake({ settleMs: 5, minGapMs: 5 });
    expect(await w.wait(30)).toBe("poll");
  });

  it("wakes on a push, after the settle time", async () => {
    const w = new Wake({ settleMs: 40, minGapMs: 0 });
    const t0 = Date.now();
    setTimeout(() => w.poke(), 10);
    expect(await w.wait(2000)).toBe("push");
    expect(Date.now() - t0).toBeGreaterThanOrEqual(45);
    expect(Date.now() - t0).toBeLessThan(500);
  });

  it("groups a burst of pushes into one wake", async () => {
    const w = new Wake({ settleMs: 40, minGapMs: 0 });
    w.poke();
    setTimeout(() => w.poke(), 25);
    const t0 = Date.now();
    expect(await w.wait(2000)).toBe("push");
    expect(Date.now() - t0).toBeGreaterThanOrEqual(60);
    expect(await w.wait(30)).toBe("poll"); // consumed, not left pending
  });

  it("never starts scans closer than the minimum gap", async () => {
    const w = new Wake({ settleMs: 0, minGapMs: 80 });
    w.started();
    w.poke();
    const t0 = Date.now();
    expect(await w.wait(2000)).toBe("push");
    expect(Date.now() - t0).toBeGreaterThanOrEqual(75);
  });

  it("keeps a push that arrived during a scan", async () => {
    const w = new Wake({ settleMs: 0, minGapMs: 0 });
    w.started();
    w.poke(); // mid-scan
    expect(await w.wait(2000)).toBe("push");
  });

  it("does not let a late push outrun the fallback poll deadline", async () => {
    const w = new Wake({ settleMs: 500, minGapMs: 0 });
    w.poke();
    expect(await w.wait(30)).toBe("poll");
  });
});

describe("coalesce", () => {
  it("turns many requests into one run", async () => {
    const fn = vi.fn(async () => {});
    const c = coalesce(fn, 0);
    for (let i = 0; i < 20; i++) c.request();
    await c.idle();
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it("runs once more for a request that arrives mid-run, never in parallel", async () => {
    let active = 0;
    let peak = 0;
    let calls = 0;
    const fn = async () => {
      calls++;
      active++;
      peak = Math.max(peak, active);
      await new Promise((r) => setTimeout(r, 20));
      active--;
    };
    const c = coalesce(fn, 0);
    c.request();
    await new Promise((r) => setTimeout(r, 5));
    c.request();
    c.request();
    await c.idle();
    expect(calls).toBe(2);
    expect(peak).toBe(1);
  });

  it("spaces runs by the minimum gap", async () => {
    const starts: number[] = [];
    const c = coalesce(async () => void starts.push(Date.now()), 60);
    c.request();
    await c.idle();
    c.request();
    await c.idle();
    expect(starts[1]! - starts[0]!).toBeGreaterThanOrEqual(55);
  });

  it("survives a failing run", async () => {
    let n = 0;
    const c = coalesce(async () => {
      n++;
      if (n === 1) throw new Error("boom");
    }, 0);
    c.request();
    await c.idle();
    c.request();
    await c.idle();
    expect(n).toBe(2);
  });
});

import { playableOnly } from "../src/ingest.js";

describe("playableOnly", () => {
  const items = [{ sha: "a" }, { sha: "b" }, { sha: "c" }];
  it("keeps what is held or has a live source, and counts the rest", () => {
    const r = playableOnly(items, (s) => s === "a", new Set(["b"]));
    expect(r.kept.map((i) => i.sha)).toEqual(["a", "b"]);
    expect(r.dropped).toBe(1);
  });
  it("drops nothing when everything is playable", () => {
    expect(playableOnly(items, () => true, new Set()).dropped).toBe(0);
  });
  it("does not mutate its input", () => {
    playableOnly(items, () => false, new Set());
    expect(items).toHaveLength(3);
  });
});
