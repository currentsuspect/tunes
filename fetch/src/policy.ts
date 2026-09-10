/**
 * R2 eviction policy: pure, unit-tested, no I/O.
 *
 * Budget ~3 GB (ORIGIN §4). Insertion order says nothing about value, so
 * victims are picked by last access: least-recently-used goes first. Two
 * rules matter more than the weights:
 *
 * - Hysteresis: crossing the budget evicts down to 90% of it, not to the
 *   line. Trimming to exactly the limit churns on every write.
 * - Never evict what is being streamed: the caller excludes in-flight shas
 *   before calling. An evicted object is re-fetchable, so a mistake costs a
 *   re-stream, never data loss.
 */
export interface CacheEntry {
  sha: string;
  size: number;
  /** Unix ms of last serve. Absent means never served: oldest rank. */
  accessed?: number;
}

export interface EvictionPlan {
  victims: string[];
  /** Bytes that remain after the victims go. */
  remaining: number;
}

export function pickVictims(
  entries: CacheEntry[],
  budgetBytes: number,
  exclude: Set<string> = new Set()
): EvictionPlan {
  const total = entries.reduce((a, e) => a + e.size, 0);
  if (total <= budgetBytes) return { victims: [], remaining: total };
  const floor = Math.floor(budgetBytes * 0.9);
  const candidates = entries
    .filter((e) => !exclude.has(e.sha))
    .sort((a, b) => (a.accessed ?? 0) - (b.accessed ?? 0));
  const victims: string[] = [];
  let remaining = total;
  for (const c of candidates) {
    if (remaining <= floor) break;
    // A lone entry bigger than the whole budget is kept: deleting the only
    // copy to satisfy the cap is the policy defeating its purpose.
    if (victims.length === entries.length - 1) break;
    victims.push(c.sha);
    remaining -= c.size;
  }
  return { victims, remaining };
}

/** Sniffs the container from magic bytes for the Content-Type we serve.
 *
 * mpv gets exactly one type header and uses it as the demux hint; a FLAC
 * labeled audio/mpeg still probes, but the opener has crashed on these
 * URLs twice, and a wrong hint is the cheapest suspect to eliminate. Only
 * the six containers the pipeline ever holds. */
export function sniffMime(bytes: Uint8Array): string {
  const head = (n: number) => String.fromCharCode(...bytes.slice(0, n));
  if (head(4) === "fLaC") return "audio/flac";
  if (head(4) === "OggS") return "audio/ogg";
  if (head(4) === "RIFF" && head(12).slice(8) === "WAVE") return "audio/wav";
  if (head(3) === "ID3") return "audio/mpeg";
  if (bytes[0] === 0xff && (bytes[1]! & 0xe0) === 0xe0) return "audio/mpeg";
  if (head(12).slice(4, 8) === "ftyp") return "audio/mp4";
  return "application/octet-stream";
}
