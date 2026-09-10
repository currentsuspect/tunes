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
  fetchFn?: typeof fetch;
  timeoutMs?: number;
}): Promise<{ rows: number; manifestBytes: number } | null> {
  const { url, key, manifest, rows, log } = opts;
  const body = JSON.stringify({ manifest, rows });
  try {
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
  } catch (e) {
    log.warn({ event: "PUBLISH_FAILED", err: String(e).slice(0, 200) });
    return null;
  }
}
