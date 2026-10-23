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
const MAX_ART_BYTES = 2 * 1024 * 1024;
const ART_PATH = /^\/internal\/art\/([0-9a-f]{64})$/;
const AUDIO_PATH = /^\/internal\/audio\/([0-9a-f]{64})$/;
// Largest library file measured on the box is ~50 MB; 64 MB caps a
// single buffered PUT safely inside the Worker memory limit.
const MAX_AUDIO_BYTES = 64 * 1024 * 1024;

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

export function checkAuth(req: Request, env: PublishEnv): boolean {
  const key = env.INTERNAL_PUBLISH_KEY ?? "";
  const header = req.headers.get("authorization") ?? "";
  // Compared in constant time by convention (see signing.ts): a service key
  // is high-entropy, but the cost of the habit is zero.
  return key !== "" && timingSafeEqual(header, `Bearer ${key}`);
}

export async function handlePublish(req: Request, env: PublishEnv): Promise<Response> {
  if (req.method !== "POST") return error(405);
  if (!checkAuth(req, env)) return error(401);

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return error(400);
  }
  if (typeof body !== "object" || body === null || Array.isArray(body)) return error(400);
  const { manifest, rows } = body as { manifest?: unknown; rows?: unknown };
  // The manifest may come separately, raw, to PUT /internal/manifest: then
  // this carries only the rows. Parsing and re-encoding an 8 MB manifest
  // here ran the Worker out of CPU on 23 Oct.
  if (
    manifest !== undefined &&
    (typeof manifest !== "object" || manifest === null || Array.isArray(manifest))
  ) {
    return error(400);
  }
  if (!Array.isArray(rows) || rows.length > MAX_ROWS || !rows.every(validRow)) {
    return error(400);
  }

  const manifestBody = manifest === undefined ? null : JSON.stringify(manifest);
  if (manifestBody !== null && manifestBody.length > MAX_MANIFEST_BYTES) return error(413);

  // Binding checks read as dead code in production, where both always exist.
  // They are the test seam: unit tests stub one side at a time, and a Worker
  // deployed without a binding must fail closed, never half-publish.
  const db = env.DB;
  const cache = env.CACHE;
  if (!db || !cache) return error(500);

  if (rows.length > 0) {
    const now = Math.floor(Date.now() / 1000);
    // OR IGNORE, not OR REPLACE: the key is the whole row, so a row already
    // there has nothing to change, and REPLACE rewrote it (and its index)
    // anyway. The box sends every row after each restart, about 2,600, so
    // a day of restarts and retries came to ~98k written rows and went over
    // D1's free 100k a day (24 Oct). Ignored rows are not written.
    await db.batch(
      rows.map((r) =>
        db
          .prepare(
            "INSERT OR IGNORE INTO fetch_map (sha, chat, msg, updated_at) VALUES (?, ?, ?, ?)"
          )
          .bind(r.sha, r.chat, r.msg, now)
      )
    );
  }
  if (manifestBody !== null) {
    await cache.put("manifest.json", manifestBody, {
      httpMetadata: { contentType: "application/json; charset=utf-8" },
    });
  }
  return new Response(
    JSON.stringify({ ok: true, rows: rows.length, manifestBytes: manifestBody?.length ?? 0 }),
    { headers: { "content-type": "application/json; charset=utf-8" } }
  );
}

/** PUT /internal/manifest: the manifest's bytes, as the box built them,
 * streamed into R2 untouched. No parse and no re-encode, so its cost does not
 * grow with the library: the combined publish ran out of CPU at 7.9 MB
 * (23 Oct). The box is the only writer (service key) and sends what it
 * serves itself; a length is required so R2 can take the stream as is. */
export async function handleManifestPut(req: Request, env: PublishEnv): Promise<Response> {
  if (req.method !== "PUT") return error(405);
  if (!checkAuth(req, env)) return error(401);
  const length = Number(req.headers.get("content-length") ?? NaN);
  if (!Number.isFinite(length) || length <= 1) return error(411);
  if (length > MAX_MANIFEST_BYTES) return error(413);
  const cache = env.CACHE;
  if (!cache || !req.body) return error(500);
  await cache.put("manifest.json", req.body, {
    httpMetadata: { contentType: "application/json; charset=utf-8" },
  });
  return new Response(JSON.stringify({ ok: true, manifestBytes: length }), {
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

/** Cover bytes named by magic, not by the uploader's label. */
function sniffArt(bytes: Uint8Array): string | null {
  const h = (i: number) => bytes[i];
  if (bytes.length >= 3 && h(0) === 0xff && h(1) === 0xd8 && h(2) === 0xff) {
    return "image/jpeg";
  }
  if (
    bytes.length >= 8 &&
    h(0) === 0x89 && h(1) === 0x50 && h(2) === 0x4e && h(3) === 0x47 &&
    h(4) === 0x0d && h(5) === 0x0a && h(6) === 0x1a && h(7) === 0x0a
  ) {
    return "image/png";
  }
  if (
    bytes.length >= 12 &&
    h(0) === 0x52 && h(1) === 0x49 && h(2) === 0x46 && h(3) === 0x46 &&
    h(8) === 0x57 && h(9) === 0x45 && h(10) === 0x42 && h(11) === 0x50
  ) {
    return "image/webp";
  }
  if (
    bytes.length >= 6 &&
    h(0) === 0x47 && h(1) === 0x49 && h(2) === 0x46 &&
    h(3) === 0x38 && (h(4) === 0x37 || h(4) === 0x39) && h(5) === 0x61
  ) {
    return "image/gif";
  }
  return null;
}

/** R2 audio read for the GET /track path. Returns null on a miss so the
 * caller falls through to origin -- an un-backfilled track streams the old
 * way, not 404ed. Range-aware: players seek, and a seek that restarts the
 * file instead is gapless's enemy. Semantics mirror the origin server. */
export async function handleTrackGet(
  pathname: string,
  req: Request,
  env: PublishEnv,
): Promise<Response | null> {
  const m = /^\/track\/([0-9a-f]{64})$/.exec(pathname);
  if (!m?.[1] || !env.CACHE) return null;
  if (req.method !== "GET" && req.method !== "HEAD") return null;
  const sha = m[1]!;
  const head = await env.CACHE.head(sha);
  if (!head) return null;
  const size = head.size;
  const contentType = head.httpMetadata?.contentType ?? "application/octet-stream";
  const base: Record<string, string> = {
    "content-type": contentType,
    "accept-ranges": "bytes",
    etag: `"${sha}"`,
    "cache-control": "public, max-age=31536000, immutable",
  };
  const rangeHeader = req.headers.get("range");
  if (rangeHeader === null) {
    if (req.method === "HEAD") {
      return new Response(null, {
        headers: { ...base, "content-length": String(size) },
      });
    }
    const obj = await env.CACHE.get(sha);
    if (!obj) return null;
    return new Response(obj.body, {
      headers: { ...base, "content-length": String(size) },
    });
  }
  const range = parseRange(rangeHeader, size);
  if (range === null) {
    return new Response(null, {
      status: 416,
      headers: { "content-range": `bytes */${size}` },
    });
  }
  if (req.method === "HEAD") {
    return new Response(null, {
      status: 206,
      headers: {
        ...base,
        "content-range": `bytes ${range.start}-${range.end}/${size}`,
        "content-length": String(range.end - range.start + 1),
      },
    });
  }
  const obj = await env.CACHE.get(sha, {
    range: { offset: range.start, length: range.end - range.start + 1 },
  });
  if (!obj) return null;
  return new Response(obj.body, {
    status: 206,
    headers: {
      ...base,
      "content-range": `bytes ${range.start}-${range.end}/${size}`,
      "content-length": String(range.end - range.start + 1),
    },
  });
}

function parseRange(header: string, size: number): { start: number; end: number } | null {
  const m = /^bytes=(\d*)-(\d*)$/.exec(header.trim());
  if (!m) return null;
  const first = m[1]!;
  const last = m[2]!;
  if (first === "" && last === "") return null;
  if (first === "") {
    const suffix = Number(last);
    if (!Number.isSafeInteger(suffix) || suffix <= 0) return null;
    if (suffix > size) return { start: 0, end: size - 1 };
    return { start: size - suffix, end: size - 1 };
  }
  const start = Number(first);
  if (!Number.isSafeInteger(start) || start < 0 || start >= size) return null;
  if (last === "") return { start, end: size - 1 };
  const end = Number(last);
  if (!Number.isSafeInteger(end) || end < start) return null;
  return { start, end: Math.min(end, size - 1) };
}

/** R2 cover read for the GET path. Returns null on a miss so the caller
 * falls through to origin -- an unpublished cover is served the old way,
 * not 404ed. Content-addressed bytes never change, hence immutable. */
export async function handleArtGet(pathname: string, env: PublishEnv): Promise<Response | null> {
  const m = /^\/art\/([0-9a-f]{64})$/.exec(pathname);
  if (!m?.[1] || !env.CACHE) return null;
  const obj = await env.CACHE.get(`art/${m[1]}`);
  if (!obj) return null;
  return new Response(obj.body, {
    headers: {
      "content-type": obj.httpMetadata?.contentType ?? "application/octet-stream",
      "cache-control": "public, max-age=31536000, immutable",
    },
  });
}
/** Box -> edge cover upload: one file per call.
 *
 * Same service key as the manifest publish, same fail-closed bindings. The
 * content type is verified server-side -- the box's label is ignored -- and
 * anything that is not a small image is refused: this route writes bytes
 * that signed device URLs will later serve, so it must never become a
 * general-purpose drop. Keys mirror the origin layout (`art/<sha>`) so the
 * GET path below reads what this writes. */
export async function handleArtPut(req: Request, pathname: string, env: PublishEnv): Promise<Response> {
  if (req.method !== "PUT") return error(405);
  if (!checkAuth(req, env)) return error(401);
  const m = ART_PATH.exec(pathname);
  if (!m?.[1]) return error(404);
  const sha = m[1]!;
  const cache = env.CACHE;
  if (!cache) return error(500);
  let bytes: Uint8Array;
  try {
    bytes = new Uint8Array(await req.arrayBuffer());
  } catch {
    return error(400);
  }
  if (bytes.length === 0 || bytes.length > MAX_ART_BYTES) return error(413);
  const contentType = sniffArt(bytes);
  if (!contentType) return error(415);
  await cache.put(`art/${sha}`, bytes, {
    httpMetadata: { contentType },
  });
  return new Response(JSON.stringify({ ok: true, sha }), {
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

/** Audio container sniff for the Content-Type served on R2 hits.
 *
 * Same six containers the fetch worker names, because mpv gets exactly one
 * type header as its demux hint. Duplicated rather than shared: the two
 * workers deploy independently, and a shared package for twelve lines
 * would couple their releases. */
function sniffAudio(bytes: Uint8Array): string {
  const head = (n: number) => String.fromCharCode(...bytes.slice(0, n));
  if (head(4) === "fLaC") return "audio/flac";
  if (head(4) === "OggS") return "audio/ogg";
  if (head(4) === "RIFF" && head(12).slice(8) === "WAVE") return "audio/wav";
  if (head(3) === "ID3") return "audio/mpeg";
  if (bytes[0] === 0xff && (bytes[1]! & 0xe0) === 0xe0) return "audio/mpeg";
  if (head(12).slice(4, 8) === "ftyp") return "audio/mp4";
  return "application/octet-stream";
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes as any);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Box -> edge audio backfill: one file per call, keyed by bare sha so the
 * fetch worker's R2 reads land on it.
 *
 * Same service key as the other internal routes. The bytes are hashed and
 * compared to the path before storing: a backfill that writes one corrupt
 * object poisons every future stream of that track, and the key is the only
 * identity the bytes will ever be served under. Oversize files are refused
 * rather than streamed: nothing in the library is near the cap, and a
 * truncated object is worse than a missing one. */
export async function handleAudioPut(req: Request, pathname: string, env: PublishEnv): Promise<Response> {
  if (req.method !== "PUT") return error(405);
  if (!checkAuth(req, env)) return error(401);
  const m = AUDIO_PATH.exec(pathname);
  if (!m?.[1]) return error(404);
  const sha = m[1]!;
  const cache = env.CACHE;
  if (!cache) return error(500);
  let bytes: Uint8Array;
  try {
    bytes = new Uint8Array(await req.arrayBuffer());
  } catch {
    return error(400);
  }
  if (bytes.length === 0 || bytes.length > MAX_AUDIO_BYTES) return error(413);
  if ((await sha256Hex(bytes)) !== sha) return error(422);
  await cache.put(sha, bytes, {
    httpMetadata: { contentType: sniffAudio(bytes) },
  });
  return new Response(JSON.stringify({ ok: true, sha, bytes: bytes.length }), {
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}
