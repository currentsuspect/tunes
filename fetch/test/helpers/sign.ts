/**
 * Test-only signer, mirroring edge/src/signing.ts signMediaUrl.
 *
 * The fetch worker only verifies; the test needs a signer to produce vectors
 * with. If edge ever changes its canonical string, this helper must change
 * in lockstep -- which is exactly the failure this file is designed to
 * surface loudly rather than hide behind a shared import.
 */
import { canonicalString } from "../../src/grant.js";

const enc = new TextEncoder();

export async function signMediaUrl(
  path: string,
  deviceId: string,
  exp: number,
  secret: string
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(canonicalString(path, deviceId, exp)));
  const hex = [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
  const q = new URLSearchParams({ exp: String(exp), did: deviceId, sig: hex });
  return `${path}?${q.toString()}`;
}
