/**
 * Serves a cached track straight from R2, without the Durable Object.
 *
 * The DO holds the one Telegram connection and does CPU-heavy work on a
 * cold download (joining chunks, hashing 30 MB, writing R2). Anything that
 * shares its event loop stalls while that runs, so warm playback used to
 * hiccup whenever anybody else fetched a cold track. A cache hit needs none
 * of the DO's state, so it never goes there.
 */

export interface R2Like {
  head(key: string): Promise<{ size: number; httpMetadata?: { contentType?: string } } | null>;
  get(
    key: string,
    opts?: { range?: { offset: number; length: number } }
  ): Promise<{
    body: ReadableStream;
    size: number;
    httpMetadata?: { contentType?: string };
  } | null>;
}

/** Parses a closed `bytes=start-end` range or open `bytes=start-`. Anything
 * else (suffix, multi-range) is answered with the whole object, which is
 * always a valid response. */
export function parseRange(
  header: string | null,
  size: number
): { start: number; end: number } | "unsatisfiable" | null {
  if (!header) return null;
  const m = /^bytes=(\d+)-(\d*)$/.exec(header.trim());
  if (!m) return null;
  const start = Number(m[1]);
  if (!Number.isSafeInteger(start)) return null;
  if (start >= size) return "unsatisfiable";
  const end = m[2] === "" ? size - 1 : Number(m[2]);
  if (!Number.isSafeInteger(end) || start > end) return null;
  return { start, end: Math.min(end, size - 1) };
}

export async function serveHit(
  cache: R2Like,
  sha: string,
  rangeHeader: string | null,
  headOnly: boolean
): Promise<{ response: Response; size: number } | null> {
  const meta = await cache.head(sha);
  if (!meta) return null;
  const size = meta.size;
  const type = meta.httpMetadata?.contentType ?? "application/octet-stream";
  const base = { "content-type": type, "accept-ranges": "bytes", "x-tunes-src": "r2" };
  const range = parseRange(rangeHeader, size);

  if (range === "unsatisfiable") {
    return {
      size,
      response: new Response(null, {
        status: 416,
        headers: { ...base, "content-range": `bytes */${size}` },
      }),
    };
  }
  if (headOnly) {
    return {
      size,
      response: new Response(null, {
        headers: { ...base, "content-length": String(size) },
      }),
    };
  }
  if (range) {
    const length = range.end - range.start + 1;
    const obj = await cache.get(sha, { range: { offset: range.start, length } });
    if (!obj) return null; // evicted between head and get: fall back to the DO
    return {
      size,
      response: new Response(obj.body, {
        status: 206,
        headers: {
          ...base,
          "content-range": `bytes ${range.start}-${range.end}/${size}`,
          "content-length": String(length),
        },
      }),
    };
  }
  const obj = await cache.get(sha);
  if (!obj) return null;
  return {
    size,
    response: new Response(obj.body, {
      headers: { ...base, "content-length": String(size) },
    }),
  };
}
