/**
 * Fetch discipline — the single source of truth for ban-safety defaults
 * (SPEC §4, AGENTS §5). Never spread these across modules; never "optimize
 * away" delays for speed. All values are overridable via config file, but
 * the defaults below are the spec'd baseline.
 */
export interface FetchDisciplineConfig {
  /** Minimum gap between bulk-scan downloads per channel (ms). */
  perChannelDelayMs: number;
  /** Added jitter range on top of the delay (ms) — 8–15 s nominal window. */
  jitterMs: number;
  /** Hard daily cap across all channels (files). Enforced in-process AND by the health probe. */
  dailyCapFiles: number;
  /** Incremental channel scan cadence (ms). */
  scanCadenceMs: number;
  /** Bulk scans only: this many concurrent downloads at most. */
  maxConcurrentDownloads: number;
  /** On-demand (user-initiated streaming) fetches skip jitter but still count against the cap. */
  onDemandJitterExempt: boolean;
}

export const defaultFetchDiscipline: FetchDisciplineConfig = Object.freeze({
  perChannelDelayMs: 8_000,
  jitterMs: 7_000,
  dailyCapFiles: 1_500,
  scanCadenceMs: 300_000,
  maxConcurrentDownloads: 1,
  onDemandJitterExempt: true,
});

export interface TunesdConfig {
  fetch: FetchDisciplineConfig;
}

export const defaultConfig: TunesdConfig = Object.freeze({
  fetch: defaultFetchDiscipline,
});