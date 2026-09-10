/**
 * Media-grant verification, mirrored from edge/src/signing.ts.
 *
 * Duplicated rather than shared: these two workers deploy independently and
 * there is no shared-package plumbing between them. If the canonical string
 * ever changes, change both -- edge/test/media.test.ts and the tests here
 * pin the same vectors.
 */

export function canonicalString(path: string, deviceId: string, exp: number): string {
  return `${path}\n${deviceId}\n${exp}`;
}

const enc = new TextEncoder();

async function hmacHex(secret: string, msg: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(msg));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export type MediaVerdict =
  | { ok: true; deviceId: string }
  | { ok: false; reason: "missing" | "expired" | "bad-signature" };

export async function verifyMediaUrl(
  path: string,
  params: URLSearchParams,
  secret: string,
  nowSec: number
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
