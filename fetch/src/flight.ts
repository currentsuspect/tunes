/**
 * One in-progress download, shared by every request for the same track.
 *
 * Why this exists: the fetcher used to download the whole file from Telegram,
 * hash it, write it to R2, and only then send the first byte. Cold tracks sat
 * silent for 10+ seconds, mpv gave up and reopened, and every reopen started
 * another full download of the same file. A Flight fixes both: bytes are
 * handed to listeners as they arrive, and a second request for the same track
 * joins the first instead of starting its own.
 *
 * Pure and I/O-free so the failure paths (stall, dropped connection, resume)
 * can be tested without Telegram.
 */

export class Flight {
  private readonly chunks: Uint8Array[] = [];
  private readonly starts: number[] = [];
  received = 0;
  done = false;
  error: Error | null = null;
  private waiters: Array<() => void> = [];

  constructor(readonly total: number) {}

  push(chunk: Uint8Array): void {
    if (chunk.byteLength === 0) return;
    this.starts.push(this.received);
    this.chunks.push(chunk);
    this.received += chunk.byteLength;
    this.wake();
  }

  finish(): void {
    this.done = true;
    this.wake();
  }

  fail(err: Error): void {
    this.error = err;
    this.wake();
  }

  private wake(): void {
    const w = this.waiters;
    this.waiters = [];
    for (const f of w) f();
  }

  private changed(): Promise<void> {
    return new Promise((r) => this.waiters.push(r));
  }

  /** Resolves once at least [bytes] are buffered, or the flight has ended. */
  async ready(bytes: number): Promise<void> {
    while (this.received < bytes && !this.done && !this.error) {
      await this.changed();
    }
    if (this.error && this.received < bytes) throw this.error;
  }

  /** Resolves when the whole file is in, throws if the flight failed. */
  async complete(): Promise<void> {
    while (!this.done && !this.error) await this.changed();
    if (this.error) throw this.error;
  }

  /** Index of the chunk holding byte [pos]; -1 if not received yet. */
  private locate(pos: number): number {
    let lo = 0;
    let hi = this.chunks.length - 1;
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      const s = this.starts[mid]!;
      const e = s + this.chunks[mid]!.byteLength;
      if (pos < s) hi = mid - 1;
      else if (pos >= e) lo = mid + 1;
      else return mid;
    }
    return -1;
  }

  /** Bytes [start, end] inclusive, delivered as they arrive. Cancelling the
   * reader never cancels the download: the cache still fills. */
  stream(start: number, end: number): ReadableStream<Uint8Array> {
    let pos = start;
    return new ReadableStream<Uint8Array>({
      pull: async (controller) => {
        while (true) {
          if (pos > end) {
            controller.close();
            return;
          }
          const i = pos < this.received ? this.locate(pos) : -1;
          if (i >= 0) {
            const c = this.chunks[i]!;
            const from = pos - this.starts[i]!;
            const to = Math.min(c.byteLength, end - this.starts[i]! + 1);
            controller.enqueue(c.subarray(from, to));
            pos = this.starts[i]! + to;
            return;
          }
          if (this.error) {
            controller.error(this.error);
            return;
          }
          if (this.done) {
            controller.error(new Error("short download"));
            return;
          }
          await this.changed();
        }
      },
    });
  }

  /** The first [n] bytes received so far, for sniffing the container. */
  head(n: number): Uint8Array {
    const out = new Uint8Array(Math.min(n, this.received));
    let at = 0;
    for (const c of this.chunks) {
      if (at >= out.length) break;
      const take = c.subarray(0, out.length - at);
      out.set(take, at);
      at += take.byteLength;
    }
    return out;
  }

  /** The whole file as one buffer. Only valid once [done]. */
  bytes(): Uint8Array {
    const out = new Uint8Array(this.received);
    for (let i = 0; i < this.chunks.length; i++) {
      out.set(this.chunks[i]!, this.starts[i]!);
    }
    return out;
  }
}

export interface RunOptions {
  /** Longest wait for the next chunk before the connection is treated as dead. */
  stallMs: number;
  /** Total attempts, first included. Each retry resumes where the last stopped. */
  attempts: number;
  /** Called between attempts so the caller can throw away a dead client. */
  onRetry?: (attempt: number, err: unknown) => void | Promise<void>;
}

class Stalled extends Error {
  constructor(ms: number) {
    super(`no data for ${ms}ms`);
  }
}

function nextWithin<T>(
  it: AsyncIterator<T>,
  ms: number
): Promise<IteratorResult<T>> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, rej) => {
    timer = setTimeout(() => rej(new Stalled(ms)), ms);
  });
  return Promise.race([it.next(), timeout]).finally(() => {
    if (timer !== undefined) clearTimeout(timer);
  });
}

/**
 * Fills [flight] from [open], resuming at the byte already received after a
 * stall or a dropped connection. A connection that dies mid-download used to
 * leave the dead client cached forever; here a failed attempt reports itself
 * through [onRetry] so the caller replaces the client, and the next attempt
 * starts from where this one stopped instead of from zero.
 */
export async function runDownload(
  flight: Flight,
  open: (offset: number) => AsyncIterable<Uint8Array> | Promise<AsyncIterable<Uint8Array>>,
  opts: RunOptions
): Promise<void> {
  let lastErr: unknown;
  for (let attempt = 1; attempt <= opts.attempts; attempt++) {
    try {
      const src = await open(flight.received);
      const it = src[Symbol.asyncIterator]();
      try {
        while (true) {
          const r = await nextWithin(it, opts.stallMs);
          if (r.done) break;
          flight.push(r.value);
        }
      } finally {
        // Best effort: a stalled iterator may never settle.
        void Promise.resolve(it.return?.()).catch(() => {});
      }
      if (flight.received >= flight.total) {
        flight.finish();
        return;
      }
      throw new Error(`stopped at ${flight.received}/${flight.total}`);
    } catch (e) {
      lastErr = e;
      if (attempt < opts.attempts) await opts.onRetry?.(attempt, e);
    }
  }
  const err = lastErr instanceof Error ? lastErr : new Error(String(lastErr));
  flight.fail(err);
}

/** Caps how many downloads run at once on the one Telegram connection. */
export class Gate {
  private active = 0;
  private queue: Array<() => void> = [];
  constructor(private readonly limit: number) {}

  get busy(): boolean {
    return this.active >= this.limit;
  }

  async run<T>(fn: () => Promise<T>): Promise<T> {
    if (this.active >= this.limit) {
      // The slot is handed over by the releaser, so a newcomer cannot slip in
      // between the release and the waiter resuming.
      await new Promise<void>((r) => this.queue.push(r));
    } else {
      this.active++;
    }
    try {
      return await fn();
    } finally {
      const next = this.queue.shift();
      if (next) next();
      else this.active--;
    }
  }
}
