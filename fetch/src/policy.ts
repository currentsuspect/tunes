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
