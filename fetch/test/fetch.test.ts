import { describe, expect, it } from "vitest";
import { canonicalString, timingSafeEqual, verifyMediaUrl } from "../src/grant.js";
import { pickVictims } from "../src/policy.js";
import { sniffMime } from "../src/policy.js";

// Pinned against edge/src/signing.ts: the canonical string is the shared
// contract. If this vector ever diverges from edge/test/media.test.ts, one of
// the two workers is verifying a different shape than the other signs.
describe("grant verification", () => {
  it("builds the same canonical string as the signer", () => {
    expect(canonicalString("/t/" + "a".repeat(64), "dev-1", 99)).toBe(
      `/t/${"a".repeat(64)}\ndev-1\n99`
    );
  });

  it("accepts a fresh signature and rejects a forged one", async () => {
    const secret = "test-media-secret";
    const path = "/t/" + "b".repeat(64);
    const exp = Math.floor(Date.now() / 1000) + 300;
    const { signMediaUrl } = await import("./helpers/sign.js");
    const signed = new URL(await signMediaUrl(path, "dev-9", exp, secret), "https://x");
    const v = await verifyMediaUrl(path, signed.searchParams, secret, exp - 60);
    expect(v).toEqual({ ok: true, deviceId: "dev-9" });
    const bad = new URLSearchParams(signed.searchParams);
    bad.set("sig", "0".repeat(64));
    expect(
      (await verifyMediaUrl(path, bad, secret, exp - 60)).ok
    ).toBe(false);
  });

  it("rejects expired and missing params", async () => {
    const secret = "s";
    const path = "/t/" + "c".repeat(64);
    expect(
      (await verifyMediaUrl(path, new URLSearchParams(), secret, 100)).ok
    ).toBe(false);
    // Properly signed but stale: expiry is checked after the signature, so a
    // forged sig on an old timestamp still reads as bad-signature.
    const { signMediaUrl } = await import("./helpers/sign.js");
    const stale = new URL(await signMediaUrl(path, "d", 50, secret), "https://x");
    expect(await verifyMediaUrl(path, stale.searchParams, secret, 100)).toEqual({
      ok: false,
      reason: "expired",
    });
    const bad = new URLSearchParams(stale.searchParams);
    bad.set("sig", "0".repeat(64));
    expect((await verifyMediaUrl(path, bad, secret, 100)).ok).toBe(false);
  });

  it("compares in constant time", () => {
    expect(timingSafeEqual("abc", "abc")).toBe(true);
    expect(timingSafeEqual("abc", "abd")).toBe(false);
    expect(timingSafeEqual("abc", "abcd")).toBe(false);
  });
});

describe("sniffMime", () => {
  const bytes = (s: string) => new TextEncoder().encode(s);
  it("names the pipeline containers", () => {
    expect(sniffMime(bytes("fLaC...."))).toBe("audio/flac");
    expect(sniffMime(bytes("OggS...."))).toBe("audio/ogg");
    expect(sniffMime(bytes("ID3....."))).toBe("audio/mpeg");
    expect(sniffMime(bytes("RIFF....WAVE"))).toBe("audio/wav");
    expect(sniffMime(new Uint8Array([0xff, 0xe3, 0, 0]))).toBe("audio/mpeg");
  });
  it("falls back to octet-stream rather than guessing", () => {
    expect(sniffMime(bytes("........"))).toBe("application/octet-stream");
  });
});

describe("eviction policy", () => {
  const GB = 1024 * 1024 * 1024;

  it("does nothing under budget", () => {
    const p = pickVictims(
      [
        { sha: "a", size: GB, accessed: 1 },
        { sha: "b", size: GB, accessed: 2 },
      ],
      3 * GB
    );
    expect(p).toEqual({ victims: [], remaining: 2 * GB });
  });

  it("evicts least-recently-used down past hysteresis, not to the line", () => {
    const p = pickVictims(
      [
        { sha: "old", size: GB, accessed: 1 },
        { sha: "mid", size: GB, accessed: 2 },
        { sha: "new", size: GB, accessed: 3 },
      ],
      2.5 * GB
    );
    // 3 GB over a 2.5 budget: evicting one leaves 2 GB, under the 2.25 floor.
    expect(p.victims).toEqual(["old"]);
    expect(p.remaining).toBe(2 * GB);
  });

  it("keeps going when one eviction is not enough", () => {
    const p = pickVictims(
      [
        { sha: "a", size: 2 * GB, accessed: 1 },
        { sha: "b", size: 2 * GB, accessed: 2 },
        { sha: "c", size: 1 * GB, accessed: 3 },
      ],
      3 * GB
    );
    expect(p.victims).toEqual(["a", "b"]);
    expect(p.remaining).toBe(1 * GB);
  });

  it("never evicts in-flight shas", () => {
    const p = pickVictims(
      [
        { sha: "streaming", size: 2 * GB, accessed: 1 },
        { sha: "cold", size: 2 * GB, accessed: 2 },
      ],
      3 * GB,
      new Set(["streaming"])
    );
    expect(p.victims).toEqual(["cold"]);
  });

  it("keeps a lone entry bigger than the budget", () => {
    const p = pickVictims([{ sha: "big", size: 5 * GB }], 3 * GB);
    expect(p.victims).toEqual([]);
  });

  it("ranks never-served entries oldest", () => {
    const p = pickVictims(
      [
        { sha: "fresh", size: 2 * GB, accessed: Date.now() },
        { sha: "never", size: 2 * GB },
      ],
      3 * GB
    );
    expect(p.victims).toEqual(["never"]);
  });
});
