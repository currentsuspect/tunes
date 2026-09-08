/**
 * Tunes auth service.
 *
 * invite -> device enrolment -> refresh token -> short-lived access token
 * -> media grant -> revoke. That chain and nothing else: no OAuth, no social
 * login, no roles, no quotas (SPEC §1.5, AGENTS.md §1).
 *
 * The invariant this exists to satisfy:
 *
 *   No reusable credential distributed with the APK grants access to the
 *   Tunes service or media. Every online media authorization is derived from
 *   an authenticated device session and expires automatically.
 *
 * So the APK ships with no secret at all. It holds a refresh token it earned
 * by redeeming an invite, in Android keystore, and everything else is minted.
 */

import {
  randomId,
  randomToken,
  sha256Hex,
  signAccessToken,
  verifyAccessToken,
} from "./crypto.js";
import { MEDIA_TTL_SEC, signMediaUrl } from "./signing.js";
import { handleMedia, stripSignature } from "./media.js";
import {
  accountById,
  deviceById,
  deviceByRefreshHash,
  inviteByHash,
  redeemInvite,
  revokeDevice,
  touchDevice,
} from "./db.js";

export interface Env {
  DB: D1Database;
  /** HS256 key for access tokens. */
  ACCESS_SECRET: string;
  /** HMAC key for media URLs. Separate from ACCESS_SECRET so one can be rotated alone. */
  MEDIA_SECRET: string;
  ACCESS_TTL_SEC?: string;
}

const DEFAULT_ACCESS_TTL_SEC = 600;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

/**
 * One error shape for every rejection.
 *
 * Deliberately uninformative: "invalid" covers a bad code, an expired code, an
 * already-redeemed code, a revoked device and a disabled account alike.
 * Telling a caller which of those it hit is telling an attacker which half of
 * the guess was right.
 */
function reject(status = 401): Response {
  return json({ error: "invalid" }, status);
}

async function readJson(req: Request): Promise<Record<string, unknown> | null> {
  try {
    const body = await req.json();
    return typeof body === "object" && body !== null ? (body as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

/** Extracts and verifies a bearer access token. Null when absent or invalid. */
async function bearer(req: Request, env: Env, nowSec: number) {
  const header = req.headers.get("authorization");
  if (!header?.startsWith("Bearer ")) return null;
  return verifyAccessToken(header.slice(7), env.ACCESS_SECRET, nowSec);
}

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url);
    const nowSec = Math.floor(Date.now() / 1000);

    // ---- POST /auth/redeem ------------------------------------------------
    // Invite code -> a device row and the only refresh token it will ever get.
    if (url.pathname === "/auth/redeem" && req.method === "POST") {
      const body = await readJson(req);
      const code = body?.["code"];
      const label = body?.["label"];
      if (typeof code !== "string" || typeof label !== "string" || label.length > 64) {
        return reject(400);
      }

      const invite = await inviteByHash(env.DB, await sha256Hex(code));
      if (!invite || invite.redeemed_at !== null || invite.expires_at <= nowSec) {
        return reject();
      }
      const account = await accountById(env.DB, invite.account_id);
      if (!account || account.status !== "active") return reject();

      const refresh = randomToken();
      const device = {
        id: randomId(),
        account_id: account.id,
        label,
        refresh_hash: await sha256Hex(refresh),
        status: "active",
        created_at: nowSec,
      };
      // Lost the race to another redemption of the same code.
      if (!(await redeemInvite(env.DB, invite, device, nowSec))) return reject();

      return json({
        device_id: device.id,
        account_label: account.label,
        refresh_token: refresh,
      });
    }

    // ---- POST /auth/token -------------------------------------------------
    // Refresh token -> short-lived access token. The refresh token is not
    // rotated: rotation on every call means a dropped response permanently
    // bricks a device, and the revocation story here is "delete the row",
    // which does not need rotation to be effective.
    if (url.pathname === "/auth/token" && req.method === "POST") {
      const body = await readJson(req);
      const refresh = body?.["refresh_token"];
      if (typeof refresh !== "string") return reject(400);

      const device = await deviceByRefreshHash(env.DB, await sha256Hex(refresh));
      if (!device || device.status !== "active") return reject();
      const account = await accountById(env.DB, device.account_id);
      if (!account || account.status !== "active") return reject();

      const ttl = Number(env.ACCESS_TTL_SEC ?? DEFAULT_ACCESS_TTL_SEC);
      const token = await signAccessToken(
        { sub: account.id, did: device.id, iat: nowSec, exp: nowSec + ttl },
        env.ACCESS_SECRET,
      );
      await touchDevice(env.DB, device.id, nowSec);
      return json({ access_token: token, expires_in: ttl });
    }

    // ---- POST /auth/media/grant -------------------------------------------
    // Access token -> a signed URL for one object. Media bytes are fetched by
    // mpv and by Android's notification loader, neither of which is the app's
    // HTTP client, so the grant travels in the URL rather than a header.
    if (url.pathname === "/auth/media/grant" && req.method === "POST") {
      const claims = await bearer(req, env, nowSec);
      if (!claims) return reject();

      const body = await readJson(req);
      const path = body?.["path"];
      // Only ever sign our own media paths, and never a path containing a
      // traversal or a query of its own -- a signature over an attacker-chosen
      // string is a signing oracle.
      if (typeof path !== "string" || !/^\/(track|art)\/[0-9a-f]{64}$/.test(path)) {
        return reject(400);
      }

      // A revoked device must stop working before its access token expires,
      // so this one endpoint pays for a database read. The media edge itself
      // stays stateless.
      const device = await deviceById(env.DB, claims.did);
      if (!device || device.status !== "active") return reject();

      const exp = nowSec + MEDIA_TTL_SEC;
      return json({
        url: await signMediaUrl(path, claims.did, exp, env.MEDIA_SECRET),
        expires_in: MEDIA_TTL_SEC,
      });
    }

    // ---- DELETE /auth/device/:id ------------------------------------------
    // A device may revoke itself; an account may revoke any of its own.
    const revokeMatch = /^\/auth\/device\/([0-9a-f-]{36})$/.exec(url.pathname);
    if (revokeMatch && req.method === "DELETE") {
      const claims = await bearer(req, env, nowSec);
      if (!claims) return reject();
      const target = await deviceById(env.DB, revokeMatch[1]!);
      if (!target || target.account_id !== claims.sub) return reject(404);
      return json({ revoked: await revokeDevice(env.DB, target.id) });
    }

    // ---- everything else: the media edge ----------------------------------
    // Stateless from here down. No env.DB below this line, deliberately: the
    // path that serves bytes must not depend on the database, or the origin
    // and cache layers cannot move later without dragging auth along.
    const rejected = await handleMedia(req, env, nowSec);
    if (rejected) return rejected;

    // Validated, or a public path. Continue to origin — which for
    // tunes.aestra.studio is tunesd through the tunnel. The Worker does not
    // know or care where the bytes come from.
    return fetch(stripSignature(req));
  },
};
