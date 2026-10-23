import { mkdir, readdir, readFile, rename, rm, rmdir, stat, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";

import type { Log } from "./logger.js";
import type { ProbeResult } from "./probe.js";
import { rankCandidates, searchVariants, type Candidate, type SlskdApi, type Wanted } from "./soulseek.js";
import { sleep } from "./telegram/ports.js";

/** Songs found again after every copy of them was lost: lost sha -> the new
 * file's sha. The manifest lists the new file and names the lost sha in its
 * dupeShas, so likes, playlists and plays kept under it follow the song.
 *
 * This is a deliberate, recorded re-sourcing of one recording, not an
 * identity rule: two shas are never treated as the same file, and nothing
 * is ever matched automatically from metadata alone outside this ledger. */
export interface Replacements {
  bySha: Record<string, { sha: string; at: string; via: "soulseek" | "library" }>;
  /** Files kept on disk but not listed, because the library already holds
   * the same song: file sha -> the listed copy it stands behind. Never
   * deleted (dedupe is never destructive); the phone follows the pointer. */
  redundant: Record<string, string>;
  /** Songs searched for and not found, so they are not searched every pass. */
  misses: Record<string, string>;
  /** Downloads per day, for the daily cap. */
  daily: Record<string, number>;
  /** Albums looked at by the completion pass (complete.ts), id -> when. */
  albums: Record<string, string>;
}

export async function loadReplacements(path: string): Promise<Replacements> {
  try {
    const raw = JSON.parse(await readFile(path, "utf8")) as Partial<Replacements>;
    return {
      bySha: raw.bySha ?? {},
      redundant: raw.redundant ?? {},
      misses: raw.misses ?? {},
      daily: raw.daily ?? {},
      albums: raw.albums ?? {},
    };
  } catch {
    return { bySha: {}, redundant: {}, misses: {}, daily: {}, albums: {} };
  }
}

export async function saveReplacements(path: string, r: Replacements): Promise<void> {
  const tmp = `${path}.${process.pid}.tmp`;
  await writeFile(tmp, JSON.stringify(r, null, 1));
  await rename(tmp, path);
}

/** What a lost copy was, from its probe. Null when its tags are too thin to
 * search for safely. */
export function wantedFrom(p: ProbeResult): Wanted | null {
  const title = p.tags.title?.trim();
  const artist = (p.tags.artist ?? p.tags.albumArtist)?.trim();
  if (!title || !artist) return null;
  return { artist, title, album: p.tags.album ?? null, durationMs: p.durationMs };
}

export interface AcquireOptions {
  /** How long a peer gets before its rate is judged. */
  judgeAfterMs?: number;
  /** Below this, after [judgeAfterMs], try the next peer. */
  minBytesPerSec?: number;
  /** Peers tried per song. */
  maxTries?: number;
  /** Longest one download may take. */
  timeoutMs?: number;
  /** Poll interval. */
  pollMs?: number;
}

const FAILED = /Errored|Rejected|TimedOut|Cancelled|Aborted/;

/** Searches, then downloads from the best peer, switching peers when one
 * crawls (measured 16 Oct: advertised speeds said 12-15 MB/s, real ones ran
 * from 17 KB/s to 200 KB/s). Returns the downloaded file's path, or null. */
export async function acquire(
  api: SlskdApi,
  w: Wanted,
  downloadsDir: string,
  log: Log,
  opts: AcquireOptions = {}
): Promise<{ path: string; candidate: Candidate } | null> {
  const judgeAfter = opts.judgeAfterMs ?? 25_000;
  const minRate = opts.minBytesPerSec ?? 60 * 1024;
  const maxTries = opts.maxTries ?? 4;
  const timeout = opts.timeoutMs ?? 8 * 60_000;
  const poll = opts.pollMs ?? 3000;

  let cands: Candidate[] = [];
  for (const q of searchVariants(w)) {
    // Searches are flaky: a real album sometimes answers nothing once.
    for (let attempt = 0; attempt < 2 && cands.length === 0; attempt++) {
      cands = rankCandidates(await api.search(q), w);
    }
    if (cands.length > 0) break;
  }
  if (cands.length === 0) {
    log.info({ event: "SOULSEEK_NOT_FOUND" });
    return null;
  }

  for (const c of cands.slice(0, maxTries)) {
    const started = Date.now();
    try {
      await api.download(c.username, c.file);
    } catch (e) {
      log.warn({ event: "SOULSEEK_DOWNLOAD_REFUSED", err: String(e) });
      continue;
    }
    let judged = false;
    let ok = false;
    while (Date.now() - started < timeout) {
      await sleep(poll);
      const t = await api.transfer(c.username, c.file.filename).catch(() => null);
      if (!t) continue;
      if (t.state.includes("Succeeded")) {
        ok = true;
        break;
      }
      if (FAILED.test(t.state)) break;
      const elapsed = Date.now() - started;
      if (!judged && elapsed >= judgeAfter) {
        judged = true;
        const rate = (t.bytesTransferred ?? 0) / (elapsed / 1000);
        if (rate < minRate) {
          log.info({ event: "SOULSEEK_SLOW_PEER", bytesPerSec: Math.round(rate) });
          break;
        }
      }
    }
    if (!ok) {
      await api.cancel(c.username, c.file.filename);
      continue;
    }
    // slskd says Succeeded a moment before it moves the file out of its
    // incomplete folder; looking once at that instant found nothing and the
    // song was downloaded again from the next peer.
    let path: string | null = null;
    for (let i = 0; i < 20 && !path; i++) {
      path = await findDownloaded(downloadsDir, c.file.filename);
      if (!path) await sleep(Math.min(poll, 1000));
    }
    if (path) {
      log.info({ event: "SOULSEEK_DOWNLOADED", lossless: c.lossless, secs: Math.round((Date.now() - started) / 1000) });
      return { path, candidate: c };
    }
    log.warn({ event: "SOULSEEK_FILE_MISSING" });
  }
  return null;
}

/** slskd saves under downloads/<remote folder>/<name>; find it by name. */
export async function findDownloaded(dir: string, remoteName: string): Promise<string | null> {
  const base = remoteName.split(/[\\/]/).pop() ?? remoteName;
  let best: { path: string; at: number } | null = null;
  const walk = async (d: string, depth: number): Promise<void> => {
    let entries: import("node:fs").Dirent[];
    try {
      entries = await readdir(d, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      const p = join(d, e.name);
      if (e.isDirectory() && depth < 3) await walk(p, depth + 1);
      else if (e.isFile() && e.name === base) {
        const at = (await stat(p)).mtimeMs;
        if (!best || at > best.at) best = { path: p, at };
      }
    }
  };
  await walk(dir, 0);
  return (best as { path: string } | null)?.path ?? null;
}

export interface ResourceDeps {
  api: SlskdApi;
  downloadsDir: string;
  /** Probes a file that is not in the store yet. */
  probe: (path: string, size: number) => Promise<ProbeResult>;
  /** Moves a checked file into the store; returns its sha. */
  commit: (path: string, size: number) => Promise<string>;
  ledgerPath: string;
  log: Log;
  /** A listed track that is this song already (same artist and title,
   * length within 3 s), if any. Found, the lost copy points at it and
   * nothing is downloaded. */
  inLibrary?: (w: Wanted) => string | null;
  /** True when someone has asked for a song (getter.ts): the pass stops
   * between songs so the ask goes first, and picks up at the next pass. */
  shouldYield?: () => boolean;
  dailyCap?: number;
  acquireOptions?: AcquireOptions;
}

/** Finds each lost song again on Soulseek, one at a time.
 *
 * A download is only kept when it is audio and as long as the lost copy
 * (within 5 s); anything else is deleted. Songs not found are remembered for
 * a week so a pass does not search them over and over. */
export async function resourceLost(
  lost: ProbeResult[],
  deps: ResourceDeps,
  now: () => Date = () => new Date()
): Promise<{ found: number; missed: number; skipped: number }> {
  const ledger = await loadReplacements(deps.ledgerPath);
  const cap = deps.dailyCap ?? 40;
  // Only this pass writes here; anything left is from a pass that was cut
  // short (a restart mid-download) and is never going to be committed.
  await rm(deps.downloadsDir, { recursive: true, force: true });
  // And put the folder back: slskd will not start without it, and from
  // 18 Oct it failed every boot after a pass had removed it.
  await mkdir(deps.downloadsDir, { recursive: true });
  await deps.api.clearFinished?.().catch(() => undefined);
  let found = 0;
  let missed = 0;
  let skipped = 0;
  for (const p of lost) {
    if (deps.shouldYield?.()) {
      deps.log.info({ event: "SOULSEEK_PASS_YIELDS" });
      break;
    }
    if (ledger.bySha[p.sha]) continue;
    const missAt = ledger.misses[p.sha];
    if (missAt && now().getTime() - Date.parse(missAt) < 7 * 24 * 3600_000) {
      skipped += 1;
      continue;
    }
    const w = wantedFrom(p);
    if (!w) {
      skipped += 1;
      continue;
    }
    // The song may still be here in another file (another release, another
    // rip). Then there is nothing to fetch: point at it. Without this check
    // a second "180" was downloaded next to the one already playing.
    const have = deps.inLibrary?.(w);
    if (have) {
      ledger.bySha[p.sha] = { sha: have, at: now().toISOString(), via: "library" };
      delete ledger.misses[p.sha];
      await saveReplacements(deps.ledgerPath, ledger);
      deps.log.info({ event: "SOULSEEK_ALREADY_HERE" });
      found += 1;
      continue;
    }
    const day = now().toISOString().slice(0, 10);
    if ((ledger.daily[day] ?? 0) >= cap) {
      deps.log.info({ event: "SOULSEEK_DAILY_CAP" });
      break;
    }
    if (!(await deps.api.loggedIn())) {
      deps.log.warn({ event: "SOULSEEK_OFFLINE" });
      break;
    }
    const got = await acquire(deps.api, w, deps.downloadsDir, deps.log, deps.acquireOptions);
    if (!got) {
      ledger.misses[p.sha] = now().toISOString();
      missed += 1;
      await saveReplacements(deps.ledgerPath, ledger);
      continue;
    }
    ledger.daily[day] = (ledger.daily[day] ?? 0) + 1;
    const size = (await stat(got.path)).size;
    let checked: ProbeResult | null = null;
    try {
      checked = await deps.probe(got.path, size);
    } catch {
      checked = null;
    }
    const lengthOk =
      checked?.durationMs != null &&
      (p.durationMs == null || Math.abs(checked.durationMs - p.durationMs) <= 5000);
    if (!checked?.codec || !lengthOk) {
      deps.log.warn({ event: "SOULSEEK_REJECTED", codec: checked?.codec ?? null, durationMs: checked?.durationMs ?? null });
      await rm(got.path, { force: true });
      await rmdir(dirname(got.path)).catch(() => undefined);
      ledger.misses[p.sha] = now().toISOString();
      missed += 1;
      await saveReplacements(deps.ledgerPath, ledger);
      continue;
    }
    const sha = await deps.commit(got.path, size);
    await rmdir(dirname(got.path)).catch(() => undefined);
    ledger.bySha[p.sha] = { sha, at: now().toISOString(), via: "soulseek" };
    delete ledger.misses[p.sha];
    await saveReplacements(deps.ledgerPath, ledger);
    deps.log.info({ event: "SOULSEEK_RESOURCED", codec: checked.codec });
    found += 1;
  }
  return { found, missed, skipped };
}
