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
const MEDIA_PATH = /^\/(track|art)\/[0-9a-f]{64}$/;

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
}

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

  if (!MEDIA_PATH.test(url.pathname)) {
    // Everything else -- /manifest, /search, /changes -- is library metadata
    // and must not be readable without a signature either. Until the app
    // carries tokens on those routes they are simply closed at the edge; that
    // is stricter than the tailnet was, which is the point.
    return deny("not-signed", 404);
  }

  // Only GET and HEAD reach media. The origin has no write routes today and
  // the edge should not be the thing that discovers otherwise.
  if (req.method !== "GET" && req.method !== "HEAD") return deny("method", 405);

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
