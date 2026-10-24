import { gzipSync } from "node:zlib";
import type { Log } from "./logger.js";

export interface PublishRow {
  sha: string;
  chat: number;
  msg: number;
  addedAt?: string | null;
}

/** Rows newer than the watermark, and the new watermark.
 *
 * Pure so the delta rule is testable: a cycle with nothing new sends nothing
 * (D1 counts writes, and the free tier taught us that). Null watermark means
 * "everything" -- first run and restarts send the full set once, which is
 * hundreds of rows rarely instead of hundreds of rows every five minutes. */
export function selectNewRows<T extends { addedAt?: string | null }>(
  rows: T[],
  since: string | null
): { rows: T[]; watermark: string | null } {
  if (since === null) {
    return { rows, watermark: maxAddedAt(rows) };
  }
  const fresh = rows.filter((r) => (r.addedAt ?? "") > since);
  if (fresh.length === 0) return { rows: [], watermark: since };
  return { rows: fresh, watermark: maxAddedAt(fresh) ?? since };
}

function maxAddedAt<T extends { addedAt?: string | null }>(rows: T[]): string | null {
  let max: string | null = null;
  for (const r of rows) {
    const a = r.addedAt ?? null;
    if (a !== null && (max === null || a > max)) max = a;
  }
  return max;
}

/** Publishes one cycle's output to the edge: manifest JSON to R2, new
 * sightings to D1, in a single authenticated call.
 *
 * Best effort by contract: a failed publish changes nothing about serving --
 * the box still has everything, and the next cycle tries again. So this never
 * throws for transport or edge errors; it logs and returns null. Only a
 * programming error (unserializable manifest) escapes, and that is a bug to
 * hear about, not a state to serve through.
 */
export async function publishCloud(opts: {
  url: string;
  key: string;
  manifest: unknown;
  rows: PublishRow[];
  log: Log;
  /** The manifest without lyrics' words, published beside the full one. */
  lean?: unknown;
  fetchFn?: typeof fetch;
  timeoutMs?: number;
}): Promise<{ rows: number; manifestBytes: number } | null> {
  const { url, key, manifest, rows, log } = opts;
  const fetchFn = opts.fetchFn ?? fetch;
  const timeout = () => AbortSignal.timeout(opts.timeoutMs ?? 60_000);
  const auth = { authorization: `Bearer ${key}` };
  // The manifest goes raw to its own route, which the edge streams to R2
  // without parsing it; the rows go as a small JSON publish. Both together
  // in one JSON body made the Worker parse and re-encode the whole manifest,
  // and at 7.9 MB it ran out of CPU on every publish (23 Oct, from 23:53).
  const manifestText = JSON.stringify(manifest);
  try {
    if (rows.length > 0) {
      const res = await fetchFn(url, {
        method: "POST",
        headers: { ...auth, "content-type": "application/json; charset=utf-8" },
        body: JSON.stringify({ rows }),
        signal: timeout(),
      });
      if (!res.ok) {
        log.warn({ event: "PUBLISH_REJECTED", status: res.status, part: "rows" });
        return null;
      }
    }
    // Gzipped: 16 MB of JSON, mostly lyrics, is ~5 MB so, and it went up
    // ~500 times a day (24 Oct). The edge keeps and serves it gzipped.
    const manifestUrl = url.replace(/\/internal\/publish$/, "/internal/manifest");
    const gz = gzipSync(manifestText, { level: 6 });
    const put = (body: Uint8Array | string, gzipped: boolean, lean = false) =>
      fetchFn(lean ? `${manifestUrl}?lean=1` : manifestUrl, {
        method: "PUT",
        headers: {
          ...auth,
          "content-type": "application/json; charset=utf-8",
          "content-length": String(typeof body === "string" ? Buffer.byteLength(body) : body.byteLength),
          ...(gzipped ? { "x-tunes-encoding": "gzip" } : {}),
        },
        body: body as BodyInit,
        signal: timeout(),
      });
    let res = await put(gz, true);
    if (res.status === 404) {
      // An edge from before the raw route: the old combined publish.
      return await combined(opts, manifestText);
    }
    if (!res.ok) {
      log.warn({ event: "PUBLISH_REJECTED", status: res.status, part: "manifest" });
      return null;
    }
    // An edge from before gzip stored those bytes as JSON: send it plain at
    // once, so no phone is handed gzip it was not told about.
    const said = (await res.json().catch(() => ({}))) as { encoding?: string; lean?: string };
    let sent = gz.byteLength;
    if (said.encoding !== "gzip") {
      res = await put(manifestText, false);
      if (!res.ok) {
        log.warn({ event: "PUBLISH_REJECTED", status: res.status, part: "manifest" });
        return null;
      }
      sent = Buffer.byteLength(manifestText);
    }
    // And the lean copy, without the lyrics' words (manifest.ts
    // leanManifest), for devices that fetch words by stamp. Only to an edge
    // that says it keeps one apart: an older one would put it in the full
    // manifest's place, and devices not yet updated would lose their lyrics.
    if (opts.lean != null && said.lean === "supported") {
      const leanRes = await put(gzipSync(JSON.stringify(opts.lean), { level: 6 }), true, true);
      if (!leanRes.ok) log.warn({ event: "PUBLISH_REJECTED", status: leanRes.status, part: "lean" });
    }
    log.info({ event: "PUBLISH_DONE", rows: rows.length, manifestBytes: manifestText.length, sentBytes: sent });
    return { rows: rows.length, manifestBytes: manifestText.length };
  } catch (e) {
    log.warn({ event: "PUBLISH_FAILED", err: String(e).slice(0, 200) });
    return null;
  }
}

/** The publish as it was: manifest and rows in one JSON body. */
async function combined(
  opts: { url: string; key: string; rows: PublishRow[]; log: Log; fetchFn?: typeof fetch; timeoutMs?: number },
  manifestText: string,
): Promise<{ rows: number; manifestBytes: number } | null> {
  const { url, key, rows, log } = opts;
  const body = `{"manifest":${manifestText},"rows":${JSON.stringify(rows)}}`;
  const res = await (opts.fetchFn ?? fetch)(url, {
    method: "POST",
    headers: {
      authorization: `Bearer ${key}`,
      "content-type": "application/json; charset=utf-8",
    },
    body,
    signal: AbortSignal.timeout(opts.timeoutMs ?? 60_000),
  });
  if (!res.ok) {
    log.warn({ event: "PUBLISH_REJECTED", status: res.status });
    return null;
  }
  const answer = (await res.json()) as { rows?: number; manifestBytes?: number };
  log.info({
    event: "PUBLISH_DONE",
    rows: answer.rows ?? rows.length,
    manifestBytes: answer.manifestBytes ?? body.length,
  });
  return {
    rows: answer.rows ?? rows.length,
    manifestBytes: answer.manifestBytes ?? body.length,
  };
}

const SHA_RE = /^[0-9a-f]{64}$/;

/** Which audio files still need backfilling to R2, in reference order.
 *
 * Same shape as the art selector, minus the cap: a backfill is a bounded
 * one-shot run, not a per-cycle trickle, so the caller pages it instead.
 * Priority ordering (dead pockets first) belongs to the caller: put those
 * shas first in `referenced` and they stay first here. */
export function selectAudioToBackfill(
  referenced: (string | null | undefined)[],
  published: Record<string, string>,
  present: (sha: string) => boolean,
): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  for (const sha of referenced) {
    if (typeof sha !== "string" || !SHA_RE.test(sha)) continue;
    if (seen.has(sha)) continue;
    seen.add(sha);
    if (published[sha] !== undefined) continue;
    if (!present(sha)) continue;
    out.push(sha);
  }
  return out;
}

/** PUTs one audio file to the edge audio route. True on acceptance.
 *
 * Best effort: a rejection or transport error logs and returns false, and
 * the sha stays off the ledger so a later run retries it. Oversize files
 * are refused client-side before any bytes move. Never throws for
 * edge/transport failures. */
export async function publishAudioFile(opts: {
  baseUrl: string;
  key: string;
  sha: string;
  bytes: Uint8Array;
  log: Log;
  fetchFn?: typeof fetch;
  timeoutMs?: number;
}): Promise<boolean> {
  const { baseUrl, key, sha, bytes, log } = opts;
  if (!SHA_RE.test(sha)) return false;
  if (bytes.length === 0 || bytes.length > 64 * 1024 * 1024) return false;
  try {
    const res = await (opts.fetchFn ?? fetch)(`${baseUrl}/audio/${sha}`, {
      method: "PUT",
      headers: {
        authorization: `Bearer ${key}`,
        "content-type": "application/octet-stream",
      },
      body: bytes as BodyInit,
      signal: AbortSignal.timeout(opts.timeoutMs ?? 300_000),
    });
    if (!res.ok) {
      log.warn({ event: "AUDIO_PUBLISH_REJECTED", status: res.status });
      return false;
    }
    return true;
  } catch (e) {
    log.warn({ event: "AUDIO_PUBLISH_FAILED", err: String(e).slice(0, 200) });
    return false;
  }
}
