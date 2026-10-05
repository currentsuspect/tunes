import { describe, expect, it } from "vitest";
import { parseRange, serveHit, type R2Like } from "../src/hit.js";

const data = Uint8Array.from({ length: 100 }, (_, i) => i);

function fakeR2(present = true): R2Like & { gets: number } {
  const r = {
    gets: 0,
    async head() {
      return present ? { size: 100, httpMetadata: { contentType: "audio/flac" } } : null;
    },
    async get(_k: string, opts?: { range?: { offset: number; length: number } }) {
      r.gets++;
      if (!present) return null;
      const o = opts?.range?.offset ?? 0;
      const l = opts?.range?.length ?? 100;
      return {
        body: new Response(data.slice(o, o + l)).body!,
        size: 100,
        httpMetadata: { contentType: "audio/flac" },
      };
    },
  };
  return r;
}

describe("parseRange", () => {
  it("handles closed, open and clamped ranges", () => {
    expect(parseRange("bytes=10-19", 100)).toEqual({ start: 10, end: 19 });
    expect(parseRange("bytes=0-", 100)).toEqual({ start: 0, end: 99 });
    expect(parseRange("bytes=50-5000", 100)).toEqual({ start: 50, end: 99 });
  });
  it("flags a start past the end, and ignores shapes it does not serve", () => {
    expect(parseRange("bytes=100-", 100)).toBe("unsatisfiable");
    expect(parseRange("bytes=-20", 100)).toBeNull();
    expect(parseRange("bytes=0-1,5-9", 100)).toBeNull();
    expect(parseRange(null, 100)).toBeNull();
  });
});

describe("serveHit", () => {
  it("misses cleanly so the caller can go to the fetcher", async () => {
    expect(await serveHit(fakeR2(false), "s", null, false)).toBeNull();
  });

  it("answers mpv's bytes=0- with a 206 and the true total", async () => {
    const hit = await serveHit(fakeR2(), "s", "bytes=0-", false);
    expect(hit!.response.status).toBe(206);
    expect(hit!.response.headers.get("content-range")).toBe("bytes 0-99/100");
    expect(hit!.size).toBe(100);
    expect(new Uint8Array(await hit!.response.arrayBuffer())).toEqual(data);
  });

  it("serves exactly the bytes asked for on a seek", async () => {
    const hit = await serveHit(fakeR2(), "s", "bytes=20-29", false);
    expect(hit!.response.status).toBe(206);
    expect(hit!.response.headers.get("content-length")).toBe("10");
    expect(new Uint8Array(await hit!.response.arrayBuffer())).toEqual(data.slice(20, 30));
  });

  it("returns 416 past the end and never reads the body", async () => {
    const r2 = fakeR2();
    const hit = await serveHit(r2, "s", "bytes=500-", false);
    expect(hit!.response.status).toBe(416);
    expect(hit!.response.headers.get("content-range")).toBe("bytes */100");
    expect(r2.gets).toBe(0);
  });

  it("sends the whole object with a length when no range is asked", async () => {
    const hit = await serveHit(fakeR2(), "s", null, false);
    expect(hit!.response.status).toBe(200);
    expect(hit!.response.headers.get("content-length")).toBe("100");
    expect(hit!.response.headers.get("content-type")).toBe("audio/flac");
  });

  it("HEAD reads no bytes", async () => {
    const r2 = fakeR2();
    const hit = await serveHit(r2, "s", null, true);
    expect(hit!.response.headers.get("content-length")).toBe("100");
    expect(r2.gets).toBe(0);
  });

  it("falls back when the object is evicted between head and get", async () => {
    const r2 = fakeR2();
    r2.get = async () => null;
    expect(await serveHit(r2, "s", "bytes=0-", false)).toBeNull();
  });
});
