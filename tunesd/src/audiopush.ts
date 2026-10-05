/**
 * Pushes audio the box holds into R2, one file at a time.
 *
 * A freshly ingested track would otherwise be a cold Telegram fetch the first
 * time a friend plays it. The box already has the bytes, so it sends them up
 * right after the download and the track is warm for everyone from the start.
 *
 * Sequential on purpose: this shares the home uplink with everything else the
 * box does. Failures never block ingest and are retried later, not hammered.
 */
import type { Log } from "./logger.js";

export interface AudioPushDeps {
  /** Contents of a held file, or null if it is not held. */
  read(sha: string): Promise<Uint8Array | null>;
  /** True on acceptance by the edge. */
  put(sha: string, bytes: Uint8Array): Promise<boolean>;
  /** Persist the ledger (sha -> ISO time). */
  save(ledger: Record<string, string>): Promise<void>;
  log: Log;
  now?: () => number;
  /** How long a failed sha is left alone before it is tried again. */
  retryAfterMs?: number;
}

export class AudioPusher {
  private readonly queue: string[] = [];
  private readonly queued = new Set<string>();
  private readonly failedAt = new Map<string, number>();
  private running: Promise<void> | null = null;
  private readonly now: () => number;

  constructor(
    private readonly ledger: Record<string, string>,
    private readonly deps: AudioPushDeps
  ) {
    this.now = deps.now ?? Date.now;
  }

  /** Newest first: callers pass what they want sent first at the front. */
  enqueue(shas: string[]): void {
    const fresh = shas.filter((s) => this.wanted(s));
    for (const s of [...fresh].reverse()) {
      this.queued.add(s);
      this.queue.unshift(s);
    }
    if (fresh.length > 0) this.run();
  }

  private wanted(sha: string): boolean {
    if (this.ledger[sha] !== undefined || this.queued.has(sha)) return false;
    const failed = this.failedAt.get(sha);
    return (
      failed === undefined ||
      this.now() - failed >= (this.deps.retryAfterMs ?? 10 * 60_000)
    );
  }

  private run(): void {
    if (this.running) return;
    this.running = this.drain().finally(() => {
      this.running = null;
      if (this.queue.length > 0) this.run();
    });
  }

  private async drain(): Promise<void> {
    while (this.queue.length > 0) {
      const sha = this.queue.shift()!;
      this.queued.delete(sha);
      try {
        const bytes = await this.deps.read(sha);
        if (!bytes) continue; // not held here: nothing to send
        if (await this.deps.put(sha, bytes)) {
          this.ledger[sha] = new Date(this.now()).toISOString();
          this.failedAt.delete(sha);
          await this.deps.save(this.ledger);
          this.deps.log.info({ event: "AUDIO_PUSHED", sha, bytes: bytes.length });
        } else {
          this.failedAt.set(sha, this.now());
        }
      } catch (e) {
        this.failedAt.set(sha, this.now());
        this.deps.log.warn({ event: "AUDIO_PUSH_ERROR", err: String(e).slice(0, 160) });
      }
    }
  }

  async idle(): Promise<void> {
    while (this.running) await this.running;
  }
}
