/**
 * Signed media URLs.
 *
 * Why URLs and not an Authorization header: media bytes are not fetched by the
 * app's HTTP client. Streaming goes through media_kit into mpv, and
 * notification artwork is fetched by Android's own loader, which cannot set
 * headers at all. A capability in the URL is the only thing all three paths
 * can carry (SPEC §2.4).
 *
 * What a signed URL is, stated plainly: a bearer capability scoped to one
 * object for a few minutes. Anyone holding it can fetch that object until it
 * expires. `did` is bound into the signature so grants are attributable and
 * differ per device -- it is NOT enforcement, because verifying the device
 * would need a database read on every range request and that is exactly the
 * statelessness this design is buying. The mitigation is the short window, and
 * the fact that a leaked URL grants one track rather than the library.
 */

import { hmacHex, timingSafeEqual } from "./crypto.js";

/**
 * How long a minted media URL stays valid.
 *
 * This was 300s in the design doc, and 300s cannot work. Reading
 * `tune_player.dart` settles it: `player.open(Playlist(...))` builds a `Media`
 * for the ENTIRE queue up front, and mpv resolves each URL only when playback
 * reaches that item. A grant minted at queue-open for track 20 is fetched an
 * hour later. Five minutes expires everything past the first track or two.
 *
 * The alternatives were:
 *
 *   a) Re-mint and re-open the playlist near expiry. Re-opening is an existing
 *      code path (playQueueAt seeks after open), but doing it mid-playback
 *      every few minutes puts an audible gap in every listening session.
 *   b) Open a short window and append as playback advances. Keeps the short
 *      TTL, but breaks gapless across the window edge, and repeat/shuffle,
 *      queue reorder and the QueueSheet all read the full `_queue`.
 *   c) Mint for as long as a listening session plausibly runs.
 *
 * (c), deliberately, with the cost stated: an intercepted URL grants ONE
 * track, to nobody in particular, for up to this long. It does not grant the
 * library, and it cannot be exchanged for a token.
 *
 * What this does NOT weaken: a revoked device stops being issued new grants
 * immediately, because minting reads the database. What it does weaken is how
 * long already-issued grants outlive a revocation. That window is this value.
 */
export const MEDIA_TTL_SEC = 14_400; // 4 hours

/**
 * Ceiling on a client-requested TTL.
 *
 * The mint endpoint accepts no TTL from the client today, but if it ever does,
 * an unbounded value is a permanent capability. Kept here so the cap lives
 * beside the default rather than being invented at the call site.
 */
export const MEDIA_TTL_MAX_SEC = 86_400;

/**
 * The exact string that gets signed.
 *
 * Fields are joined with a character that cannot appear in any of them, so
 * distinct inputs cannot collide into one signed string. Path always begins
 * with "/" and a uuid contains no newline, so "\n" is safe here -- a naive
 * concatenation would let ("/a", "b") and ("/ab", "") sign identically.
 */
export function canonicalString(path: string, deviceId: string, exp: number): string {
  return `${path}\n${deviceId}\n${exp}`;
}

export async function signMediaUrl(
  path: string,
  deviceId: string,
  exp: number,
  secret: string,
): Promise<string> {
  const sig = await hmacHex(secret, canonicalString(path, deviceId, exp));
  const q = new URLSearchParams({ exp: String(exp), did: deviceId, sig });
  return `${path}?${q.toString()}`;
}

export type MediaVerdict =
  | { ok: true; deviceId: string }
  | { ok: false; reason: "missing" | "expired" | "bad-signature" };

/**
 * Verifies a signed media request.
 *
 * Expiry is checked *after* the signature. Checking it first would let an
 * attacker distinguish "this signature was valid but stale" from "this
 * signature was never valid", which tells them whether they have the right
 * secret shape. The cost is one HMAC on requests that were going to fail
 * anyway.
 */
export async function verifyMediaUrl(
  path: string,
  params: URLSearchParams,
  secret: string,
  nowSec: number,
): Promise<MediaVerdict> {
  const sig = params.get("sig");
  const did = params.get("did");
  const expRaw = params.get("exp");
  if (!sig || !did || !expRaw) return { ok: false, reason: "missing" };

  const exp = Number(expRaw);
  if (!Number.isSafeInteger(exp)) return { ok: false, reason: "missing" };

  const expected = await hmacHex(secret, canonicalString(path, did, exp));
  if (!timingSafeEqual(expected, sig)) return { ok: false, reason: "bad-signature" };
  if (exp <= nowSec) return { ok: false, reason: "expired" };
  return { ok: true, deviceId: did };
}
