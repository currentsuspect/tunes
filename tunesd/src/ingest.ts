/**
 * Scheduling for faster ingest. Pure timing logic, no Telegram or HTTP, so
 * the rules that keep it polite can be tested without a clock or a network.
 *
 * What this does NOT touch: the delay between downloads. That discipline
 * (config.ts, SPEC §4) exists to keep the Telegram session safe and stays
 * exactly as it is. This only changes *when a scan starts* and *when the
 * result is shown*.
 */

export interface WakeOptions {
  /** Wait this long after the last push before scanning, so a multi-file
   * post lands as one scan rather than several. */
  settleMs: number;
  /** Never start scans closer together than this, whatever pushes arrive. */
  minGapMs: number;
  now?: () => number;
}

/** An interruptible sleep: wakes on a push from Telegram, or on the fallback
 * poll if no push comes (updates can be missed; the poll is the safety net). */
export class Wake {
  private poked = false;
  private pokedAt = 0;
  private lastStart = -Infinity;
  private resolver: (() => void) | null = null;
  private readonly now: () => number;

  constructor(private readonly opts: WakeOptions) {
    this.now = opts.now ?? Date.now;
  }

  /** Telegram says there is something new. */
  poke(): void {
    this.poked = true;
    this.pokedAt = this.now();
    this.resolver?.();
  }

  /** Call when a scan begins, to enforce the minimum gap. */
  started(): void {
    this.lastStart = this.now();
  }

  /** Resolves "push" once a push has settled and the gap has passed, or
   * "poll" after [fallbackMs]. A push that arrived mid-scan is kept. */
  async wait(fallbackMs: number): Promise<"push" | "poll"> {
    const deadline = this.now() + fallbackMs;
    for (;;) {
      if (this.poked) {
        const ready = Math.max(
          this.pokedAt + this.opts.settleMs,
          this.lastStart + this.opts.minGapMs
        );
        const until = Math.min(ready, deadline);
        const ms = until - this.now();
        if (ms <= 0) {
          if (ready <= this.now()) {
            this.poked = false;
            return "push";
          }
          return "poll";
        }
        await this.sleepInterruptibly(ms);
        continue;
      }
      const ms = deadline - this.now();
      if (ms <= 0) return "poll";
      await this.sleepInterruptibly(ms);
    }
  }

  private sleepInterruptibly(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      const t = setTimeout(done, ms);
      const self = this;
      function done(): void {
        clearTimeout(t);
        self.resolver = null;
        resolve();
      }
      this.resolver = done;
    });
  }
}

/** Runs [fn] at most once at a time and at most once per [minGapMs],
 * collapsing any number of requests into one trailing run. Used to publish the
 * manifest as each file lands without publishing once per file. */
export function coalesce(
  fn: () => Promise<void>,
  minGapMs: number,
  now: () => number = Date.now
): { request(): void; idle(): Promise<void> } {
  let running: Promise<void> | null = null;
  let again = false;
  let lastStart = -Infinity;
  let timer: ReturnType<typeof setTimeout> | null = null;

  const kick = (): void => {
    if (running || timer) return;
    const wait = Math.max(0, lastStart + minGapMs - now());
    timer = setTimeout(() => {
      timer = null;
      lastStart = now();
      again = false;
      running = fn()
        .catch(() => undefined)
        .finally(() => {
          running = null;
          if (again) kick();
        });
    }, wait);
  };

  return {
    request(): void {
      again = true;
      kick();
    },
    async idle(): Promise<void> {
      while (running || timer || again) {
        await (running ?? new Promise((r) => setTimeout(r, 5)));
      }
    },
  };
}

/**
 * Keeps only what can actually be played: held on the box, or still
 * reachable at a Telegram source the fetcher can read. Tracks ingested from a
 * retired channel the fetcher cannot open were listed anyway, and the player
 * skipped from one dead entry to the next until a playable one came up.
 *
 * Hiding is not deleting: state.json, the probe cache and any files stay as
 * they are, so a channel that becomes readable again brings its tracks back.
 */
export function playableOnly<T extends { sha: string }>(
  items: T[],
  heldLocally: (sha: string) => boolean,
  liveShas: Set<string>
): { kept: T[]; dropped: number } {
  const kept = items.filter((i) => heldLocally(i.sha) || liveShas.has(i.sha));
  return { kept, dropped: items.length - kept.length };
}
