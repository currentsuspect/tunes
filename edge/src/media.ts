/**
 * The media edge: validate a signed URL, then get out of the way.
 *
 * This is the half of the system that must stay stateless. It reads no
 * database, knows nothing about accounts or devices beyond the id baked into
 * a signature, and cannot tell whether the bytes it forwards came from the
 * local object store, R2, or a fresh Telegram fetch. That opacity is what
 * lets the storage layer move without touching auth (SPEC §2.4).
 *
 * Revocation is therefore NOT enforced here, and cannot be: a signature made
 * before a device was revoked still verifies afterwards. Enforcement lives at
 * the mint endpoint, which does read the database. A revoked device stops
 * getting new grants immediately; the grants it already holds expire on their
 * own. Real revocation latency is the media-grant TTL, not the access-token
 * TTL.
 */

import { verifyAccessToken } from "./crypto.js";
import { verifyMediaUrl } from "./signing.js";

/** Paths served straight through with no signature. Nothing here reveals library content. */
const PUBLIC_PATHS = new Set(["/update", "/health"]);

/**
 * Media paths are content-addressed and nothing else is signable.
 *
 * Anchored, lowercase hex, exactly 64 characters. This is the same shape
 * tunesd itself matches in serve.ts, and keeping it strict is what stops a
 * signature from ever being minted over a traversal or an arbitrary path.
 */
const MEDIA_PATH = /^\/(track|art|t)\/[0-9a-f]{64}$/;

/**
 * A listener adding lyrics for a track, for everyone. The one write a phone
 * makes to the library: PUT only, and only with a bearer token, because unlike
 * everything else here it changes what other people see.
 */
const LYRICS_PATH = /^\/lyrics\/[0-9a-f]{64}$/;

/**
 * A moment of a song cut to share (tunesd clip.ts): POST, with the lyric card
 * as the body, and only with a bearer token. It reads, never writes, but it
 * makes the box do work, so it is not open to a signed media URL.
 */
const CLIP_PATH = /^\/clip\/[0-9a-f]{64}$/;

function deny(reason: string, status = 403): Response {
  // The reason is for our own logs and the app's error surface; it names the
  // check that failed, never whether the object exists. A 403 for a bad
  // signature and a 403 for a signature over a missing sha are identical from
  // outside, so this cannot be used to enumerate the library.
  return new Response(JSON.stringify({ error: reason }), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

export interface MediaEnv {
  MEDIA_SECRET: string;
  ACCESS_SECRET: string;
}

/**
 * Library metadata. Closed to the public, but reachable with a bearer token.
 *
 * These were briefly closed outright, which was half a design: /manifest names
 * every track in the library, so it cannot be public -- but the app cannot
 * sign them either, because a signature is minted per object and these are not
 * objects. The answer is the access token the app already holds.
 *
 * Verified by signature alone, no database read, exactly like the media path.
 * A revoked device therefore keeps reading metadata until its access token
 * expires, which is the same ~10 minute bound documented for every other use
 * of that token.
 */
const API_PATHS = new Set([
  "/manifest",
  "/changes",
  "/search",
  "/missing",
  "/discography",
  // Songs got from Soulseek on request, and an album's full track list
  // (tunesd getter.ts). Token-checked like the rest; the box does the work.
  "/soulseek/search",
  "/soulseek/get",
  "/soulseek/jobs",
  "/soulseek/complete",
  "/soulseek/cancel",
  "/tracklist",
  // What Genius knows, for the song, album, artist and person pages (tunesd
  // about.ts). Read-only, token-checked like the rest.
  "/about/song",
  "/about/album",
  "/about/artist",
  "/about/person",
  // The words of the songs whose lyrics changed, for devices on the lean
  // manifest (tunesd serve.ts).
  "/lyrics-for",
]);

/**
 * Returns a Response when the request is handled or rejected here, or null to
 * let the caller pass it through to origin untouched.
 */
export async function handleMedia(
  req: Request,
  env: MediaEnv,
  nowSec: number,
): Promise<Response | null> {
  const url = new URL(req.url);

  if (PUBLIC_PATHS.has(url.pathname)) return null;
  if (url.pathname.startsWith("/update/")) return null;

  if (API_PATHS.has(url.pathname)) {
    const header = req.headers.get("authorization");
    if (!header?.startsWith("Bearer ")) return deny("no-token", 401);
    const claims = await verifyAccessToken(
      header.slice(7),
      env.ACCESS_SECRET,
      nowSec,
    );
    if (!claims) return deny("bad-token", 401);
    return null;
  }

  if (CLIP_PATH.test(url.pathname)) {
    if (req.method !== "POST") return deny("method", 405);
    const header = req.headers.get("authorization");
    if (!header?.startsWith("Bearer ")) return deny("no-token", 401);
    const claims = await verifyAccessToken(
      header.slice(7),
      env.ACCESS_SECRET,
      nowSec,
    );
    if (!claims) return deny("bad-token", 401);
    return null;
  }

  if (LYRICS_PATH.test(url.pathname)) {
    if (req.method !== "PUT") return deny("method", 405);
    const header = req.headers.get("authorization");
    if (!header?.startsWith("Bearer ")) return deny("no-token", 401);
    const claims = await verifyAccessToken(
      header.slice(7),
      env.ACCESS_SECRET,
      nowSec,
    );
    if (!claims) return deny("bad-token", 401);
    return null;
  }

  if (!MEDIA_PATH.test(url.pathname)) {
    // Not media, not a known API route, not public. Refused without saying
    // whether it exists.
    return deny("not-found", 404);
  }

  // Only GET and HEAD reach media. The origin has no write routes today and
  // the edge should not be the thing that discovers otherwise.
  if (req.method !== "GET" && req.method !== "HEAD") return deny("method", 405);

  // A bearer token is also a valid way to ask for media, and the app's own
  // HTTP client uses it -- downloads go through dart:io, which can set
  // headers. Signed URLs exist because mpv and Android's notification loader
  // cannot; they are not the only credential a device holds.
  //
  // Strictly tighter than the signature it replaces: an access token lives
  // ~10 minutes against a grant's four hours.
  const header = req.headers.get("authorization");
  if (header?.startsWith("Bearer ")) {
    const claims = await verifyAccessToken(
      header.slice(7),
      env.ACCESS_SECRET,
      nowSec,
    );
    if (claims) return null;
    return deny("bad-token", 401);
  }

  const verdict = await verifyMediaUrl(
    url.pathname,
    url.searchParams,
    env.MEDIA_SECRET,
    nowSec,
  );
  if (!verdict.ok) return deny(verdict.reason);

  return null;
}

/**
 * Strips the signing parameters before the request continues to origin.
 *
 * tunesd ignores unknown query parameters, so this is hygiene rather than a
 * fix -- but a signature is a credential, and credentials should not be
 * written into origin access logs.
 *
 * The Range header is deliberately left untouched. Audio playback is almost
 * entirely range requests, and rewriting or dropping them here would turn
 * seeking into a full re-download.
 */
export function stripSignature(req: Request): Request {
  const url = new URL(req.url);
  for (const k of ["sig", "did", "exp"]) url.searchParams.delete(k);
  return new Request(url.toString(), req);
}
