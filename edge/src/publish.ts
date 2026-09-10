/**
 * Box -> edge publish: the manifest and the sha->message map.
 *
 * The box remains the only thing that scans, probes and enriches. Everything
 * it learns that the cloud path needs -- the manifest JSON and new sightings
 * -- arrives here in one authenticated call per cycle, and is stored where
 * the serving path reads it: the manifest in R2, the rows in D1. The box
 * never needs Cloudflare credentials for this; it holds one opaque service
 * key, and the edge holds the Cloudflare side.
 */
import { timingSafeEqual } from "./crypto.js";

const SHA_RE = /^[0-9a-f]{64}$/;
const MAX_ROWS = 5000;
const MAX_MANIFEST_BYTES = 25 * 1024 * 1024;

export interface PublishEnv {
  INTERNAL_PUBLISH_KEY?: string;
  DB?: D1Database;
  CACHE?: R2Bucket;
}

interface MapRow {
  sha: string;
  chat: number;
  msg: number;
}

function error(status: number): Response {
  return new Response(JSON.stringify({ error: "invalid" }), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function validRow(r: unknown): r is MapRow {
  if (typeof r !== "object" || r === null) return false;
  const o = r as Record<string, unknown>;
  return (
    typeof o.sha === "string" &&
    SHA_RE.test(o.sha) &&
    typeof o.chat === "number" &&
    Number.isSafeInteger(o.chat) &&
    typeof o.msg === "number" &&
    Number.isSafeInteger(o.msg) &&
    (o.msg as number) > 0
  );
}

export async function handlePublish(req: Request, env: PublishEnv): Promise<Response> {
  if (req.method !== "POST") return error(405);
  const key = env.INTERNAL_PUBLISH_KEY ?? "";
  const header = req.headers.get("authorization") ?? "";
  // Compared in constant time by convention (see signing.ts): a service key
  // is high-entropy, but the cost of the habit is zero.
  if (key === "" || !timingSafeEqual(header, `Bearer ${key}`)) return error(401);

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return error(400);
  }
  if (typeof body !== "object" || body === null || Array.isArray(body)) return error(400);
  const { manifest, rows } = body as { manifest?: unknown; rows?: unknown };
  if (typeof manifest !== "object" || manifest === null || Array.isArray(manifest)) {
    return error(400);
  }
  if (!Array.isArray(rows) || rows.length > MAX_ROWS || !rows.every(validRow)) {
    return error(400);
  }

  const manifestBody = JSON.stringify(manifest);
  if (manifestBody.length > MAX_MANIFEST_BYTES) return error(413);

  // Binding checks read as dead code in production, where both always exist.
  // They are the test seam: unit tests stub one side at a time, and a Worker
  // deployed without a binding must fail closed, never half-publish.
  const db = env.DB;
  const cache = env.CACHE;
  if (!db || !cache) return error(500);

  if (rows.length > 0) {
    const now = Math.floor(Date.now() / 1000);
    await db.batch(
      rows.map((r) =>
        db
          .prepare(
            "INSERT OR REPLACE INTO fetch_map (sha, chat, msg, updated_at) VALUES (?, ?, ?, ?)"
          )
          .bind(r.sha, r.chat, r.msg, now)
      )
    );
  }
  await cache.put("manifest.json", manifestBody, {
    httpMetadata: { contentType: "application/json; charset=utf-8" },
  });
  return new Response(
    JSON.stringify({ ok: true, rows: rows.length, manifestBytes: manifestBody.length }),
    { headers: { "content-type": "application/json; charset=utf-8" } }
  );
}
