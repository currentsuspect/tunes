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
import { MEDIA_TTL_MAX_SEC, MEDIA_TTL_SEC, signMediaUrl } from "./signing.js";
import { handleMedia, stripSignature } from "./media.js";
import { handleSync } from "./sync.js";
import { handleArtGet, handleArtPut, handleAudioPut, handlePublish,
  handleManifestPut, handleTrackGet } from "./publish.js";
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
  /// Overrides MEDIA_TTL_SEC. Exists so the expiry path can be exercised
  /// against the real edge without waiting four hours -- deploy with a small
  /// value, prove a grant dies, put it back. Capped, so a bad value cannot
  /// mint a permanent capability.
  MEDIA_TTL_SEC?: string;
  /** Service key the box publishes with. Absent in tests; publish denies all. */
  INTERNAL_PUBLISH_KEY?: string;
  /** Shared tune cache. Absent in tests; manifest falls through to origin. */
  CACHE?: R2Bucket;
  /** Cloud byte path. Absent in tests; /t/ falls through to origin deny. */
  FETCH_WORKER?: Fetcher;
}

const DEFAULT_ACCESS_TTL_SEC = 600;

/** Ceiling on one batch mint. Longer than any real queue, short enough to bound work. */
const MAX_GRANTS_PER_REQUEST = 500;

/** The only shapes that may ever be signed. Mirrors tunesd's own route
 * matching, plus the cloud fetcher's /t/ prefix, which signs the same way. */
const MEDIA_PATH = /^\/(track|art|t)\/[0-9a-f]{64}$/;

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
    // Access token -> signed URLs. Media bytes are fetched by mpv and by
    // Android's notification loader, neither of which is the app's HTTP
    // client, so the grant travels in the URL rather than a header.
    //
    // Batched because the player opens a whole playlist at once. One request
    // per queue entry would put dozens of round trips in front of the first
    // note.
    if (url.pathname === "/auth/media/grant" && req.method === "POST") {
      const claims = await bearer(req, env, nowSec);
      if (!claims) return reject();

      const body = await readJson(req);
      const raw = body?.["paths"];
      if (!Array.isArray(raw) || raw.length === 0) return reject(400);
      // Bounded so one request cannot ask for unlimited signing work. A queue
      // longer than this is not a real queue.
      if (raw.length > MAX_GRANTS_PER_REQUEST) return reject(400);

      // Only ever sign our own media paths. A signature over an
      // attacker-chosen string is a signing oracle, so the shape is checked
      // before anything is signed, and a single bad entry fails the request
      // rather than being skipped -- silently returning fewer grants than
      // asked for would surface as tracks that mysteriously do not play.
      const paths: string[] = [];
      for (const p of raw) {
        if (typeof p !== "string" || !MEDIA_PATH.test(p)) return reject(400);
        paths.push(p);
      }

      // A revoked device must stop being issued grants immediately, so this
      // endpoint pays for a database read. The media edge itself never does.
      const device = await deviceById(env.DB, claims.did);
      if (!device || device.status !== "active") return reject();

      const configured = Number(env.MEDIA_TTL_SEC ?? MEDIA_TTL_SEC);
      const ttl =
        Number.isSafeInteger(configured) && configured > 0
          ? Math.min(configured, MEDIA_TTL_MAX_SEC)
          : MEDIA_TTL_SEC;
      const exp = nowSec + ttl;
      const grants: Record<string, string> = {};
      for (const p of paths) {
        grants[p] = await signMediaUrl(p, claims.did, exp, env.MEDIA_SECRET);
      }
      return json({ grants, expires_in: ttl });
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

    // ---- /sync/push, /sync/pull ------------------------------------------
    // What follows a listener between devices. Needs the database, so it sits
    // above the stateless media path below.
    const synced = await handleSync(req, env, Date.now());
    if (synced) return synced;

    // ---- everything else: the media edge ----------------------------------
    // ---- POST /internal/publish ------------------------------------------
    // Box -> edge: manifest JSON to R2, new sightings to D1. The only write
    // route on this Worker, and the only one keyed by a service secret
    // rather than a device credential.
    if (url.pathname === "/internal/publish") {
      return handlePublish(req, env);
    }

    // ---- PUT /internal/manifest ------------------------------------------
    // The manifest alone, raw, streamed to R2 (publish.ts says why).
    if (url.pathname === "/internal/manifest") {
      return handleManifestPut(req, env);
    }

    // ---- PUT /internal/art/:sha ------------------------------------------
    // Box -> edge cover upload, same service key as the manifest publish.
    if (url.pathname.startsWith("/internal/art/")) {
      return handleArtPut(req, url.pathname, env);
    }

    // ---- PUT /internal/audio/:sha ----------------------------------------
    // Box -> edge audio backfill, same service key. Hashed against the path
    // before storing: the key is the only identity these bytes are served
    // under, so a mismatch is refused rather than cached.
    if (url.pathname.startsWith("/internal/audio/")) {
      return handleAudioPut(req, url.pathname, env);
    }

    // ---- GET /manifest -----------------------------------------------------
    // Served from R2 once the box publishes it; until then (or when the
    // binding is absent, as in tests) the request falls through to origin
    // exactly as before. Short client cache: the manifest changes on scan
    // cadence, not per request.
    //
    // After the media gate, deliberately: the origin path requires a device
    // credential, and a copy in R2 must not drop that gate.
    const rejected = await handleMedia(req, env, nowSec);
    if (rejected) return rejected;
    if (url.pathname === "/manifest" && req.method === "GET" && env.CACHE) {
      const obj = await env.CACHE.get("manifest.json");
      if (obj) {
        return new Response(obj.body, {
          headers: {
            "content-type": "application/json; charset=utf-8",
            "cache-control": "public, max-age=60",
          },
        });
      }
    }

    // ---- GET /art/:sha -----------------------------------------------------
    // Served from R2 once the box publishes it; until then the request falls
    // through to origin exactly as before. After the media gate,
    // deliberately: a cached cover must not drop the device credential, and
    // an art sha is content-addressed, so the bytes never change -- a client
    // or proxy may cache them for a year.
    if (req.method === "GET" && env.CACHE) {
      const cached = await handleArtGet(url.pathname, env);
      if (cached) return cached;
    }

    // ---- GET|HEAD /track/:sha --------------------------------------------
    // Served from R2 once the box backfills it; until then the request falls
    // through to origin exactly as before. After the media gate,
    // deliberately: cached bytes must not drop the device credential.
    // Range-aware like the origin: players seek, and a miss here is a miss
    // of the whole object, never a partial answer.
    if ((req.method === "GET" || req.method === "HEAD") && env.CACHE) {
      const audio = await handleTrackGet(url.pathname, req, env);
      if (audio) return audio;
    }

    // Stateless from here down. No env.DB below this line, deliberately: the
    // path that serves bytes must not depend on the database, or the origin
    // and cache layers cannot move later without dragging auth along.
    // Validated, or a public path. The cloud byte path goes to the fetch
    // worker over a service binding -- same hostname externally, and the
    // grant above was already verified, so nothing ungated crosses over.
    // Without the binding (tests) it falls through to the origin deny below.
    const cloudTrack =
      (req.method === "GET" || req.method === "HEAD") &&
      /^\/t\/[0-9a-f]{64}$/.test(url.pathname)
        ? env.FETCH_WORKER
        : undefined;
    if (cloudTrack) {
      return cloudTrack.fetch(new Request(url.toString(), req));
    }
    // Continue to origin — which for tunes.aestra.studio is tunesd through
    // the tunnel. The Worker does not know or care where the bytes come from.
    return fetch(stripSignature(req));
  },
};
