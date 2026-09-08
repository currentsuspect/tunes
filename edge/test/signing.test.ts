import { describe, expect, it } from "vitest";
import { canonicalString, signMediaUrl, verifyMediaUrl } from "../src/signing.js";

const SECRET = "test-media-secret";
const NOW = 1_757_000_000;
const SHA = "a".repeat(64);
const PATH = `/track/${SHA}`;

function paramsOf(signed: string): URLSearchParams {
  return new URL(signed, "https://tunes.aestra.studio").searchParams;
}

describe("canonicalString", () => {
  it("cannot be collided by shifting a boundary between fields", () => {
    // Naive concatenation would make these two identical.
    expect(canonicalString("/a", "b", 1)).not.toBe(canonicalString("/ab", "", 1));
  });
});

describe("signed media urls", () => {
  it("verifies a freshly minted url", async () => {
    const signed = await signMediaUrl(PATH, "dev-1", NOW + 300, SECRET);
    expect(await verifyMediaUrl(PATH, paramsOf(signed), SECRET, NOW)).toEqual({
      ok: true,
      deviceId: "dev-1",
    });
  });

  it("rejects a url whose path was swapped for another object", async () => {
    // The whole point: a grant for one track must not fetch a different one.
    const signed = await signMediaUrl(PATH, "dev-1", NOW + 300, SECRET);
    const other = `/track/${"b".repeat(64)}`;
    expect(await verifyMediaUrl(other, paramsOf(signed), SECRET, NOW)).toEqual({
      ok: false,
      reason: "bad-signature",
    });
  });

  it("rejects an extended expiry", async () => {
    const signed = await signMediaUrl(PATH, "dev-1", NOW + 300, SECRET);
    const p = paramsOf(signed);
    p.set("exp", String(NOW + 86_400));
    expect(await verifyMediaUrl(PATH, p, SECRET, NOW)).toEqual({
      ok: false,
      reason: "bad-signature",
    });
  });

  it("rejects a swapped device id", async () => {
    const signed = await signMediaUrl(PATH, "dev-1", NOW + 300, SECRET);
    const p = paramsOf(signed);
    p.set("did", "dev-2");
    expect(await verifyMediaUrl(PATH, p, SECRET, NOW)).toEqual({
      ok: false,
      reason: "bad-signature",
    });
  });

  it("expires exactly at exp, not after", async () => {
    const exp = NOW + 300;
    const signed = await signMediaUrl(PATH, "dev-1", exp, SECRET);
    expect(await verifyMediaUrl(PATH, paramsOf(signed), SECRET, exp - 1)).toMatchObject({
      ok: true,
    });
    expect(await verifyMediaUrl(PATH, paramsOf(signed), SECRET, exp)).toEqual({
      ok: false,
      reason: "expired",
    });
  });

  it("reports expiry only for signatures that were genuinely valid", async () => {
    // An expired-but-authentic url says "expired"; a forged one says
    // "bad-signature" even when its exp is also in the past. Otherwise the
    // reason leaks whether the attacker had the right key.
    const signed = await signMediaUrl(PATH, "dev-1", NOW - 10, SECRET);
    expect(await verifyMediaUrl(PATH, paramsOf(signed), SECRET, NOW)).toEqual({
      ok: false,
      reason: "expired",
    });
    const forged = paramsOf(signed);
    forged.set("sig", "0".repeat(64));
    expect(await verifyMediaUrl(PATH, forged, SECRET, NOW)).toEqual({
      ok: false,
      reason: "bad-signature",
    });
  });

  it("rejects urls missing any signing field", async () => {
    const signed = await signMediaUrl(PATH, "dev-1", NOW + 300, SECRET);
    for (const drop of ["sig", "did", "exp"]) {
      const p = paramsOf(signed);
      p.delete(drop);
      expect(await verifyMediaUrl(PATH, p, SECRET, NOW)).toEqual({
        ok: false,
        reason: "missing",
      });
    }
  });

  it("rejects a non-numeric expiry without throwing", async () => {
    const signed = await signMediaUrl(PATH, "dev-1", NOW + 300, SECRET);
    const p = paramsOf(signed);
    p.set("exp", "not-a-number");
    expect(await verifyMediaUrl(PATH, p, SECRET, NOW)).toEqual({
      ok: false,
      reason: "missing",
    });
  });
});
