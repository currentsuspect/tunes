/**
 * Account sync.
 *
 * Two routes, both behind the same bearer token as everything else:
 *
 *   POST /sync/push   { docs: [{ key, value, deleted, updatedAt }] }
 *   GET  /sync/pull?after=<seq>
 *
 * A doc is one thing a listener owns, keyed so the same thing on two devices
 * is the same key (`like:<sha>`, `playlist:<uuid>`...). The device sends what
 * it changed; the server keeps the newest write per key and numbers every
 * accepted change; a device asks for everything after the number it last saw.
 * That is the whole protocol: no sessions, no sockets, and a device that was
 * off for a month catches up with one request.
 *
 * The account comes from the token and from nowhere else, so one account's
 * documents cannot be named, let alone read, from another's.
 */

import { verifyAccessToken } from "./crypto.js";

export interface SyncEnv {
  DB: D1Database;
  ACCESS_SECRET: string;
}

/** What may be stored. Anything else is a 400, so the table cannot become a
 * free-form store for whoever holds a token. */
const KEY =
  /^(like:[0-9a-f]{64}|playlist:[0-9a-f-]{36}|edit:[0-9a-f]{64}:(title|artist|album|year)|profile|now|queue|cmd|plays:[0-9a-f-]{36}:[0-9]{8})$/;

export const MAX_DOCS_PER_PUSH = 200;
export const MAX_VALUE_BYTES = 256 * 1024;
export const PULL_PAGE = 500;

/** A device clock this far ahead is treated as this far ahead, not trusted:
 * one wrong clock must not win every conflict for ever. */
const MAX_FUTURE_MS = 60_000;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

const reject = (status = 401) => json({ error: "invalid" }, status);

interface PushDoc {
  key: string;
  value: string | null;
  deleted: boolean;
  updatedAt: number;
}

function parseDocs(body: unknown): PushDoc[] | null {
  if (typeof body !== "object" || body === null) return null;
  const raw = (body as Record<string, unknown>)["docs"];
  if (!Array.isArray(raw) || raw.length > MAX_DOCS_PER_PUSH) return null;
  const out: PushDoc[] = [];
  for (const d of raw) {
    if (typeof d !== "object" || d === null) return null;
    const r = d as Record<string, unknown>;
    const key = r["key"];
    const updatedAt = r["updatedAt"];
    const deleted = r["deleted"] === true;
    const value = r["value"];
    if (typeof key !== "string" || !KEY.test(key)) return null;
    if (typeof updatedAt !== "number" || !Number.isFinite(updatedAt)) return null;
    if (!deleted) {
      if (typeof value !== "string") return null;
      if (new TextEncoder().encode(value).length > MAX_VALUE_BYTES) return null;
    }
    out.push({ key, value: deleted ? null : (value as string), deleted, updatedAt: Math.floor(updatedAt) });
  }
  return out;
}

/**
 * Returns a Response for a /sync route, or null for anything else.
 * `nowMs` is injected so the clock rule can be tested.
 */
export async function handleSync(
  req: Request,
  env: SyncEnv,
  nowMs: number,
): Promise<Response | null> {
  const url = new URL(req.url);
  const isPush = url.pathname === "/sync/push" && req.method === "POST";
  const isPull = url.pathname === "/sync/pull" && req.method === "GET";
  if (!isPush && !isPull) {
    return url.pathname.startsWith("/sync/") ? reject(404) : null;
  }

  const header = req.headers.get("authorization");
  if (!header?.startsWith("Bearer ")) return reject();
  const claims = await verifyAccessToken(header.slice(7), env.ACCESS_SECRET, Math.floor(nowMs / 1000));
  if (!claims) return reject();
  const account = claims.sub;
  const device = claims.did;

  if (isPush) {
    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return reject(400);
    }
    const docs = parseDocs(body);
    if (!docs) return reject(400);
    if (docs.length > 0) {
      const stmts = docs.map((d) => {
        const at = Math.min(d.updatedAt, nowMs + MAX_FUTURE_MS);
        return env.DB.prepare(
          `INSERT INTO sync_doc (account_id, key, value, deleted, updated_at, device_id, seq)
           VALUES (?1, ?2, ?3, ?4, ?5, ?6,
                   (SELECT COALESCE(MAX(seq), 0) + 1 FROM sync_doc WHERE account_id = ?1))
           ON CONFLICT (account_id, key) DO UPDATE SET
             value = excluded.value,
             deleted = excluded.deleted,
             updated_at = excluded.updated_at,
             device_id = excluded.device_id,
             seq = excluded.seq
           WHERE excluded.updated_at > sync_doc.updated_at`,
        ).bind(account, d.key, d.value, d.deleted ? 1 : 0, at, device);
      });
      await env.DB.batch(stmts);
    }
    const head = await env.DB.prepare(
      "SELECT COALESCE(MAX(seq), 0) AS seq FROM sync_doc WHERE account_id = ?",
    )
      .bind(account)
      .first<{ seq: number }>();
    return json({ head: head?.seq ?? 0, now: nowMs });
  }

  const after = Number(url.searchParams.get("after") ?? "0");
  if (!Number.isSafeInteger(after) || after < 0) return reject(400);
  // `only=live` is the fast lane: just where the music is, what is queued and
  // any command, so a device can ask every second or two without dragging the
  // likes and playlists along.
  const live = url.searchParams.get("only") === "live";
  const rows = await env.DB.prepare(
    `SELECT key, value, deleted, updated_at, device_id, seq
       FROM sync_doc WHERE account_id = ? AND seq > ?
       ${live ? "AND key IN ('now', 'queue', 'cmd')" : ""}
       ORDER BY seq LIMIT ?`,
  )
    .bind(account, after, PULL_PAGE + 1)
    .all<{
      key: string;
      value: string | null;
      deleted: number;
      updated_at: number;
      device_id: string;
      seq: number;
    }>();
  const all = rows.results ?? [];
  const page = all.slice(0, PULL_PAGE);
  // Device labels ride along so "playing on Laptop" needs no second request.
  const labels = await env.DB.prepare("SELECT id, label FROM device WHERE account_id = ?")
    .bind(account)
    .all<{ id: string; label: string }>();
  return json({
    docs: page.map((r) => ({
      key: r.key,
      value: r.value,
      deleted: r.deleted === 1,
      updatedAt: r.updated_at,
      deviceId: r.device_id,
      seq: r.seq,
    })),
    next: page.length ? page[page.length - 1]!.seq : after,
    more: all.length > PULL_PAGE,
    devices: Object.fromEntries((labels.results ?? []).map((d) => [d.id, d.label])),
    now: nowMs,
  });
}
