import { describe, expect, it } from "vitest";
import { handleMedia, stripSignature } from "../src/media.js";
import { signAccessToken } from "../src/crypto.js";
import { signMediaUrl } from "../src/signing.js";

const ENV = { MEDIA_SECRET: "test-media-secret", ACCESS_SECRET: "test-access-secret" };
const NOW = 1_757_000_000;
const SHA = "a".repeat(64);
const HOST = "https://tunes.aestra.studio";

function get(path: string, init?: RequestInit): Request {
  return new Request(`${HOST}${path}`, init);
}

/** null means "pass through to origin". A Response means the edge answered. */
async function verdict(path: string, init?: RequestInit) {
  return handleMedia(get(path, init), ENV, NOW);
}

describe("media edge", () => {
  it("passes a validly signed track through to origin", async () => {
    const signed = await signMediaUrl(`/track/${SHA}`, "dev-1", NOW + 300, ENV.MEDIA_SECRET);
    expect(await verdict(signed)).toBeNull();
  });

  it("rejects an unsigned, unauthenticated track request", async () => {
    const res = await verdict(`/track/${SHA}`);
    expect(res?.status).toBe(403);
  });

  it("accepts a bearer token on media, for the app's own downloads", async () => {
    // downloadTrack goes through dart:io, which can set headers. mpv cannot,
    // which is why signed URLs exist -- but they are not the only credential.
    const token = await signAccessToken(
      { sub: "acct-1", did: "dev-1", iat: NOW, exp: NOW + 600 },
      ENV.ACCESS_SECRET,
    );
    expect(
      await verdict(`/track/${SHA}`, { headers: { authorization: `Bearer ${token}` } }),
    ).toBeNull();
  });

  it("a bad bearer on media is refused, not silently downgraded to signature", async () => {
    const forged = await signAccessToken(
      { sub: "acct-1", did: "dev-1", iat: NOW, exp: NOW + 600 },
      "wrong-secret",
    );
    const res = await verdict(`/track/${SHA}`, {
      headers: { authorization: `Bearer ${forged}` },
    });
    expect(res?.status).toBe(401);
  });

  it("rejects a signature lifted onto a different sha", async () => {
    // Property 6/8: a grant is for exactly one object.
    const signed = await signMediaUrl(`/track/${SHA}`, "dev-1", NOW + 300, ENV.MEDIA_SECRET);
    const query = signed.slice(signed.indexOf("?"));
    const res = await verdict(`/track/${"b".repeat(64)}${query}`);
    expect(res?.status).toBe(403);
    expect(await res!.json()).toEqual({ error: "bad-signature" });
  });

  it("rejects an expired grant", async () => {
    const signed = await signMediaUrl(`/track/${SHA}`, "dev-1", NOW - 1, ENV.MEDIA_SECRET);
    const res = await verdict(signed);
    expect(await res!.json()).toEqual({ error: "expired" });
  });

  it("refuses library metadata without a token", async () => {
    // /manifest names every track we hold, so it cannot be public.
    for (const p of ["/manifest", "/search?q=a", "/changes", "/missing"]) {
      const res = await verdict(p);
      expect(res?.status, `${p} should need a token`).toBe(401);
    }
  });

  it("lets a valid bearer token through to library metadata", async () => {
    // The half that was missing: closed to the public, open to an enrolled
    // device. Without this the app cannot sync at all.
    const token = await signAccessToken(
      { sub: "acct-1", did: "dev-1", iat: NOW, exp: NOW + 600 },
      ENV.ACCESS_SECRET,
    );
    for (const p of ["/manifest", "/search?q=a", "/changes", "/missing", "/discography?artist=x"]) {
      const res = await verdict(p, { headers: { authorization: `Bearer ${token}` } });
      expect(res, `${p} should pass through`).toBeNull();
    }
  });

  it("refuses an expired or forged token on metadata", async () => {
    const expired = await signAccessToken(
      { sub: "acct-1", did: "dev-1", iat: NOW - 700, exp: NOW - 1 },
      ENV.ACCESS_SECRET,
    );
    expect((await verdict("/manifest", { headers: { authorization: `Bearer ${expired}` } }))?.status).toBe(401);

    const forged = await signAccessToken(
      { sub: "acct-1", did: "dev-1", iat: NOW, exp: NOW + 600 },
      "wrong-secret",
    );
    expect((await verdict("/manifest", { headers: { authorization: `Bearer ${forged}` } }))?.status).toBe(401);
  });

  it("a media grant does not grant metadata", async () => {
    // Different credentials for different things: a signed track URL must not
    // be reusable as a library listing.
    const signed = await signMediaUrl(`/track/${SHA}`, "dev-1", NOW + 300, ENV.MEDIA_SECRET);
    const q = signed.slice(signed.indexOf("?"));
    expect((await verdict(`/manifest${q}`))?.status).toBe(401);
  });

  it("leaves the update feed public", async () => {
    // A phone that cannot authenticate must still be able to discover and
    // download a build that can.
    expect(await verdict("/update")).toBeNull();
    expect(await verdict("/update/apk")).toBeNull();
  });

  it("refuses writes to media paths", async () => {
    const signed = await signMediaUrl(`/track/${SHA}`, "dev-1", NOW + 300, ENV.MEDIA_SECRET);
    expect((await verdict(signed, { method: "POST" }))?.status).toBe(405);
  });

  it("does not accept a traversal dressed as a media path", async () => {
    for (const p of [
      "/track/../../etc/passwd",
      `/track/${SHA}/../../secret`,
      `/track/${"A".repeat(64)}`, // uppercase hex is not the canonical form
      `/track/${"a".repeat(63)}`,
      `/track/${"a".repeat(65)}`,
    ]) {
      const res = await verdict(p);
      expect(res, `expected ${p} to be refused`).not.toBeNull();
    }
  });

  it("strips credentials before the request reaches origin", async () => {
    const signed = await signMediaUrl(`/track/${SHA}`, "dev-1", NOW + 300, ENV.MEDIA_SECRET);
    const out = new URL(stripSignature(get(signed)).url);
    expect(out.searchParams.get("sig")).toBeNull();
    expect(out.searchParams.get("did")).toBeNull();
    expect(out.searchParams.get("exp")).toBeNull();
    expect(out.pathname).toBe(`/track/${SHA}`);
  });

  it("preserves the Range header, which playback depends on", async () => {
    const signed = await signMediaUrl(`/track/${SHA}`, "dev-1", NOW + 300, ENV.MEDIA_SECRET);
    const out = stripSignature(get(signed, { headers: { Range: "bytes=100-200" } }));
    expect(out.headers.get("Range")).toBe("bytes=100-200");
  });
});
