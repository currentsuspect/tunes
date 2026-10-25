/**
 * Crypto primitives for the auth edge.
 *
 * Pure functions over WebCrypto, which the Workers runtime provides. No JWT
 * library: HS256 sign/verify is about forty lines here, and AGENTS.md §1 asks
 * for removing code over adding a package for one small function.
 *
 * Everything in this file is deterministic given its inputs and testable
 * without a Worker, which is the point -- the handler stays thin glue.
 */

const enc = new TextEncoder();

export function b64urlEncode(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function b64urlDecode(s: string): Uint8Array {
  const p = s.replace(/-/g, "+").replace(/_/g, "/");
  const bin = atob(p + "=".repeat((4 - (p.length % 4)) % 4));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function toHex(bytes: Uint8Array): string {
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** A URL-safe secret with 256 bits of entropy. Used for refresh tokens and invite codes. */
export function randomToken(): string {
  return b64urlEncode(crypto.getRandomValues(new Uint8Array(32)));
}

export function randomId(): string {
  return crypto.randomUUID();
}

/**
 * sha256, hex. What gets stored for refresh tokens and invite codes.
 *
 * A plain hash rather than a password KDF on purpose: these are 256-bit
 * random values, not user-chosen passwords, so there is no dictionary to
 * mount and the slow-hash argument does not apply.
 */
export async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", enc.encode(input));
  return toHex(new Uint8Array(digest));
}

/**
 * Length-independent constant-time comparison.
 *
 * Both sides here are hex digests of fixed width, so length is not secret,
 * but comparing with === would still leak position of first difference via
 * timing. Cheap to do correctly.
 */
export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function hmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

export async function hmacHex(secret: string, message: string): Promise<string> {
  const key = await hmacKey(secret);
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(message));
  return toHex(new Uint8Array(sig));
}

export interface AccessClaims {
  /** Account id. */
  sub: string;
  /** Device id. Present so a revoked device can be rejected without a DB hit. */
  did: string;
  /** Expiry, unix seconds. */
  exp: number;
  /** Issued at, unix seconds. */
  iat: number;
  /** The account's own box (docs/BYOB.md), when it has one: where its library requests go. Absent = the owner's box.
   * Set at /auth/token, which reads the database; the gate routes on it without one. */
  box?: string;
}

/** Mints an HS256 JWT. The only token type this service issues. */
export async function signAccessToken(
  claims: AccessClaims,
  secret: string,
): Promise<string> {
  const header = b64urlEncode(enc.encode(JSON.stringify({ alg: "HS256", typ: "JWT" })));
  const payload = b64urlEncode(enc.encode(JSON.stringify(claims)));
  const body = `${header}.${payload}`;
  const key = await hmacKey(secret);
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(body));
  return `${body}.${b64urlEncode(new Uint8Array(sig))}`;
}

/**
 * Verifies signature and expiry. Returns null on any failure rather than
 * throwing, so callers cannot accidentally distinguish "bad signature" from
 * "expired" in a response and hand an attacker an oracle.
 *
 * `alg` is checked against the expected value rather than read from the
 * header, which is the classic JWT confusion bug.
 */
export async function verifyAccessToken(
  token: string,
  secret: string,
  nowSec: number,
): Promise<AccessClaims | null> {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const [header, payload, sig] = parts as [string, string, string];

  let head: { alg?: unknown; typ?: unknown };
  try {
    head = JSON.parse(new TextDecoder().decode(b64urlDecode(header)));
  } catch {
    return null;
  }
  if (head.alg !== "HS256") return null;

  const key = await hmacKey(secret);
  let ok: boolean;
  try {
    ok = await crypto.subtle.verify(
      "HMAC",
      key,
      b64urlDecode(sig),
      enc.encode(`${header}.${payload}`),
    );
  } catch {
    return null;
  }
  if (!ok) return null;

  let claims: AccessClaims;
  try {
    claims = JSON.parse(new TextDecoder().decode(b64urlDecode(payload)));
  } catch {
    return null;
  }
  if (typeof claims.exp !== "number" || claims.exp <= nowSec) return null;
  if (typeof claims.sub !== "string" || typeof claims.did !== "string") return null;
  return claims;
}
