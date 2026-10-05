import { describe, expect, it } from "vitest";
import { Flight, Gate, runDownload } from "../src/flight.js";

const bytes = (n: number, from = 0) =>
  Uint8Array.from({ length: n }, (_, i) => (from + i) & 0xff);

async function read(s: ReadableStream<Uint8Array>): Promise<Uint8Array> {
  const parts: Uint8Array[] = [];
  const r = s.getReader();
  for (;;) {
    const x = await r.read();
    if (x.done) break;
    parts.push(x.value);
  }
  const out = new Uint8Array(parts.reduce((a, p) => a + p.length, 0));
  let at = 0;
  for (const p of parts) {
    out.set(p, at);
    at += p.length;
  }
  return out;
}

async function* chunks(all: Uint8Array, from: number, size: number) {
  for (let i = from; i < all.length; i += size) yield all.subarray(i, i + size);
}

describe("Flight", () => {
  it("delivers bytes to a reader that started before they arrived", async () => {
    const all = bytes(100);
    const f = new Flight(100);
    const out = read(f.stream(0, 99));
    f.push(all.subarray(0, 40));
    f.push(all.subarray(40, 100));
    f.finish();
    expect(await out).toEqual(all);
  });

  it("serves a range that starts mid-file", async () => {
    const all = bytes(100);
    const f = new Flight(100);
    const out = read(f.stream(30, 69));
    f.push(all.subarray(0, 50));
    f.push(all.subarray(50, 100));
    f.finish();
    expect(await out).toEqual(all.subarray(30, 70));
  });

  it("lets a second listener join part-way", async () => {
    const all = bytes(90);
    const f = new Flight(90);
    f.push(all.subarray(0, 30));
    const late = read(f.stream(0, 89));
    f.push(all.subarray(30, 90));
    f.finish();
    expect(await late).toEqual(all);
  });

  it("errors a reader when the flight fails", async () => {
    const f = new Flight(10);
    const out = read(f.stream(0, 9));
    f.push(bytes(4));
    f.fail(new Error("boom"));
    await expect(out).rejects.toThrow("boom");
  });

  it("head() returns the first bytes across chunk boundaries", () => {
    const f = new Flight(10);
    f.push(bytes(3));
    f.push(bytes(3, 3));
    expect(f.head(5)).toEqual(bytes(5));
  });
});

describe("runDownload", () => {
  it("fills the flight from a healthy source", async () => {
    const all = bytes(1000);
    const f = new Flight(1000);
    await runDownload(f, (o) => chunks(all, o, 300), { stallMs: 50, attempts: 3 });
    expect(f.done).toBe(true);
    expect(f.bytes()).toEqual(all);
  });

  it("resumes at the byte already received after the connection drops", async () => {
    const all = bytes(1000);
    const f = new Flight(1000);
    const offsets: number[] = [];
    let retries = 0;
    await runDownload(
      f,
      (offset) => {
        offsets.push(offset);
        if (offsets.length === 1) {
          return (async function* () {
            yield all.subarray(0, 400);
            throw new Error("Network connection lost.");
          })();
        }
        return chunks(all, offset, 300);
      },
      { stallMs: 50, attempts: 3, onRetry: () => void retries++ }
    );
    expect(offsets).toEqual([0, 400]);
    expect(retries).toBe(1);
    expect(f.bytes()).toEqual(all);
  });

  it("treats a silent source as dead instead of waiting forever", async () => {
    const all = bytes(600);
    const f = new Flight(600);
    let calls = 0;
    await runDownload(
      f,
      (offset) => {
        calls++;
        if (calls === 1) {
          return (async function* () {
            yield all.subarray(0, 200);
            await new Promise(() => {}); // never settles
          })();
        }
        return chunks(all, offset, 200);
      },
      { stallMs: 30, attempts: 2 }
    );
    expect(f.bytes()).toEqual(all);
  });

  it("fails the flight once attempts run out", async () => {
    const f = new Flight(100);
    await runDownload(
      f,
      () =>
        (async function* () {
          throw new Error("down");
        })(),
      { stallMs: 20, attempts: 2 }
    );
    expect(f.error?.message).toBe("down");
    await expect(f.complete()).rejects.toThrow("down");
  });

  it("treats a short stream as a failure, not a finished file", async () => {
    const f = new Flight(100);
    await runDownload(f, (o) => chunks(bytes(60), o, 30), { stallMs: 20, attempts: 1 });
    expect(f.done).toBe(false);
    expect(f.error).not.toBeNull();
  });
});

describe("Gate", () => {
  it("never runs more than the limit at once, and passes slots on in order", async () => {
    const g = new Gate(2);
    let active = 0;
    let peak = 0;
    const order: number[] = [];
    const job = (n: number) =>
      g.run(async () => {
        active++;
        peak = Math.max(peak, active);
        order.push(n);
        await new Promise((r) => setTimeout(r, 10));
        active--;
      });
    await Promise.all([1, 2, 3, 4, 5].map(job));
    expect(peak).toBe(2);
    expect(order).toEqual([1, 2, 3, 4, 5]);
    expect(g.busy).toBe(false);
  });
});
