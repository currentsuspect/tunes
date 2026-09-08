import { describe, expect, it } from "vitest";
import {
  b64urlDecode,
  b64urlEncode,
  randomToken,
  sha256Hex,
  signAccessToken,
  timingSafeEqual,
  verifyAccessToken,
} from "../src/crypto.js";

const SECRET = "test-access-secret";
const NOW = 1_757_000_000;

describe("base64url", () => {
  it("round-trips bytes including the ones that differ from plain base64", () => {
    // 0xfb 0xff produce '+' and '/' in standard base64; url-safe must not.
    const bytes = new Uint8Array([0, 1, 250, 251, 255, 62, 63]);
    const encoded = b64urlEncode(bytes);
    expect(encoded).not.toMatch(/[+/=]/);
    expect([...b64urlDecode(encoded)]).toEqual([...bytes]);
  });
});

describe("sha256Hex", () => {
  it("matches a known vector", async () => {
    expect(await sha256Hex("abc")).toBe(
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    );
  });
});

describe("randomToken", () => {
  it("does not repeat across calls", () => {
    const seen = new Set(Array.from({ length: 200 }, () => randomToken()));
    expect(seen.size).toBe(200);
  });
});

describe("timingSafeEqual", () => {
  it("is true only for identical strings", () => {
    expect(timingSafeEqual("abc", "abc")).toBe(true);
    expect(timingSafeEqual("abc", "abd")).toBe(false);
    expect(timingSafeEqual("abc", "ab")).toBe(false);
    expect(timingSafeEqual("", "")).toBe(true);
  });
});

describe("access tokens", () => {
  const claims = { sub: "acct-1", did: "dev-1", iat: NOW, exp: NOW + 600 };

  it("verifies a token it just signed", async () => {
    const token = await signAccessToken(claims, SECRET);
    expect(await verifyAccessToken(token, SECRET, NOW)).toMatchObject({
      sub: "acct-1",
      did: "dev-1",
    });
  });

  it("rejects a token signed with a different secret", async () => {
    const token = await signAccessToken(claims, "other-secret");
    expect(await verifyAccessToken(token, SECRET, NOW)).toBeNull();
  });

  it("rejects once expired, exactly at exp", async () => {
    const token = await signAccessToken(claims, SECRET);
    expect(await verifyAccessToken(token, SECRET, claims.exp - 1)).not.toBeNull();
    expect(await verifyAccessToken(token, SECRET, claims.exp)).toBeNull();
  });

  it("rejects a tampered payload", async () => {
    const token = await signAccessToken(claims, SECRET);
    const [h, , s] = token.split(".") as [string, string, string];
    const forged = b64urlEncode(
      new TextEncoder().encode(JSON.stringify({ ...claims, sub: "acct-2" })),
    );
    expect(await verifyAccessToken(`${h}.${forged}.${s}`, SECRET, NOW)).toBeNull();
  });

  it("rejects alg=none rather than trusting the header", async () => {
    // The classic JWT confusion attack: strip the signature and claim the
    // token is unsigned. verifyAccessToken must pin HS256, not read alg.
    const header = b64urlEncode(
      new TextEncoder().encode(JSON.stringify({ alg: "none", typ: "JWT" })),
    );
    const payload = b64urlEncode(new TextEncoder().encode(JSON.stringify(claims)));
    expect(await verifyAccessToken(`${header}.${payload}.`, SECRET, NOW)).toBeNull();
  });

  it("rejects malformed input without throwing", async () => {
    for (const bad of ["", "a", "a.b", "a.b.c.d", "...", "not-a-token"]) {
      expect(await verifyAccessToken(bad, SECRET, NOW)).toBeNull();
    }
  });
});
