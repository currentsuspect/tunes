import { describe, expect, it } from 'vitest';
import { defaultConfig, defaultFetchDiscipline } from '../src/config.js';

describe('fetch discipline defaults (SPEC §4, AGENTS §5)', () => {
  it('keeps a sane 8–15 s per-channel window', () => {
    expect(defaultFetchDiscipline.perChannelDelayMs).toBeGreaterThanOrEqual(5_000);
    expect(defaultFetchDiscipline.jitterMs).toBeGreaterThanOrEqual(0);
    expect(defaultFetchDiscipline.perChannelDelayMs + defaultFetchDiscipline.jitterMs)
      .toBeGreaterThanOrEqual(12_000);
  });

  it('keeps the daily cap finite and positive', () => {
    expect(defaultFetchDiscipline.dailyCapFiles).toBeGreaterThan(0);
    expect(defaultFetchDiscipline.dailyCapFiles).toBeLessThanOrEqual(10_000);
  });

  it('scans incrementally, never hot', () => {
    expect(defaultFetchDiscipline.scanCadenceMs).toBeGreaterThanOrEqual(60_000);
  });

  it('never parallelizes bulk downloads beyond 1', () => {
    expect(defaultFetchDiscipline.maxConcurrentDownloads).toBe(1);
  });

  it('routes on-demand fetches around jitter but inside the cap', () => {
    expect(defaultFetchDiscipline.onDemandJitterExempt).toBe(true);
  });

  it('freezes the default config so modules cannot drift', () => {
    expect(Object.isFrozen(defaultConfig.fetch)).toBe(true);
  });
});