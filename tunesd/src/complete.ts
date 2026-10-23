/**
 * Albums held in part, filled in from Soulseek (owner, 17 Oct: "set up
 * Soulseek to pull missing tracks"). Lunchbox's New Jazz was 5 of 23.
 *
 * A pass picks the albums closest to complete, reads each one's track list
 * from Deezer, and fetches what the library lacks, one song at a time, under
 * the same daily cap as re-sourcing lost songs. A download is kept only if it
 * is audio and within 5 s of the track list's length. Albums are looked at
 * again at most weekly; a song not found waits a week before another search.
 */
import { rm, rmdir, stat } from "node:fs/promises";
import { dirname } from "node:path";

import type { DeezerAlbum, DeezerTrack } from "./deezer.js";
import type { Log } from "./logger.js";
import type { ProbeResult } from "./probe.js";
import { acquire, loadReplacements, saveReplacements, type AcquireOptions } from "./resource.js";
import type { SlskdApi, Wanted } from "./soulseek.js";

export interface PartialAlbum {
  id: string;
  title: string;
  artist: string;
  owned: number;
  total: number;
}

/** Releases held in part: at least [minOwned] songs, and a known total. The
 * nearest to complete first, because one or two songs finish them. */
export function partialAlbums(
  releases: Array<{ id: string; title: string; artist: string; totalTracks: number | null; trackShas: string[] }>,
  minOwned = 3,
): PartialAlbum[] {
  return releases
    .filter((r) => r.totalTracks != null && r.trackShas.length >= minOwned && r.trackShas.length < r.totalTracks)
    .map((r) => ({ id: r.id, title: r.title, artist: r.artist, owned: r.trackShas.length, total: r.totalTracks! }))
    .sort((a, b) => b.owned / b.total - a.owned / a.total || a.total - a.owned - (b.total - b.owned));
}

export function norm(s: string | null | undefined): string {
  return (s ?? "")
    .toLowerCase()
    .normalize("NFKD")
    .replace(/\(.*?\)|\[.*?\]/g, "")
    .replace(/[^a-z0-9]+/g, "");
}

/** The Deezer album that is this release: same title (bracketed edition notes
 * aside), same artist, and a track count close to the release's. */
export function matchAlbum(album: PartialAlbum, candidates: DeezerAlbum[]): DeezerAlbum | null {
  const t = norm(album.title);
  const a = norm(album.artist);
  return (
    candidates.find((c) => norm(c.title) === t && (norm(c.artist).includes(a) || a.includes(norm(c.artist)))) ?? null
  );
}

export interface CompleteDeps {
  deezer: {
    searchAlbumCandidates(artist: string, album: string): Promise<DeezerAlbum[]>;
    albumTracks(id: number): Promise<DeezerTrack[]>;
  };
  api: SlskdApi;
  downloadsDir: string;
  probe: (path: string, size: number) => Promise<ProbeResult>;
  commit: (path: string, size: number) => Promise<string>;
  /** The listed song this already is, if any (same check as re-sourcing). */
  inLibrary: (w: Wanted) => string | null;
  ledgerPath: string;
  log: Log;
  /** True when someone has asked for a song (getter.ts): the pass stops
   * between songs so the ask goes first, and picks up at the next pass. */
  shouldYield?: () => boolean;
  dailyCap?: number;
  acquireOptions?: AcquireOptions;
}

const WEEK = 7 * 24 * 3600_000;

/** Fills in up to [maxAlbums] albums per pass. */
export async function completeAlbums(
  albums: PartialAlbum[],
  deps: CompleteDeps,
  opts: { maxAlbums?: number; now?: () => Date } = {},
): Promise<{ albums: number; found: number; missed: number }> {
  const now = opts.now ?? (() => new Date());
  const ledger = await loadReplacements(deps.ledgerPath);
  const book = ledger.albums;
  const cap = deps.dailyCap ?? 40;
  let looked = 0;
  let found = 0;
  let missed = 0;
  for (const album of albums) {
    if (looked >= (opts.maxAlbums ?? 2)) break;
    const last = book[album.id];
    if (last && now().getTime() - Date.parse(last) < WEEK) continue;
    looked += 1;
    book[album.id] = now().toISOString();
    await saveReplacements(deps.ledgerPath, ledger);

    let tracks: DeezerTrack[];
    try {
      const match = matchAlbum(album, await deps.deezer.searchAlbumCandidates(album.artist, album.title));
      if (!match) {
        deps.log.info({ event: "COMPLETE_NO_MATCH", album: album.title });
        continue;
      }
      tracks = await deps.deezer.albumTracks(match.id);
    } catch (e) {
      deps.log.warn({ event: "COMPLETE_DEEZER_FAILED", err: String(e) });
      break;
    }
    // A very different count is another edition: do not guess.
    if (Math.abs(tracks.length - album.total) > 3) {
      deps.log.info({ event: "COMPLETE_EDITION_MISMATCH", album: album.title, deezer: tracks.length, total: album.total });
      continue;
    }
    for (const t of tracks) {
      if (deps.shouldYield?.()) {
        deps.log.info({ event: "COMPLETE_PASS_YIELDS" });
        return { albums: looked, found, missed };
      }
      const w: Wanted = {
        artist: t.artist || album.artist,
        title: t.title,
        album: album.title,
        durationMs: t.durationMs || null,
      };
      if (deps.inLibrary(w)) continue;
      const key = `${norm(w.artist)}|${norm(w.title)}`;
      const missAt = ledger.misses[key];
      if (missAt && now().getTime() - Date.parse(missAt) < WEEK) continue;
      const day = now().toISOString().slice(0, 10);
      if ((ledger.daily[day] ?? 0) >= cap) {
        deps.log.info({ event: "SOULSEEK_DAILY_CAP" });
        return { albums: looked, found, missed };
      }
      if (!(await deps.api.loggedIn())) {
        deps.log.warn({ event: "SOULSEEK_OFFLINE" });
        return { albums: looked, found, missed };
      }
      const got = await acquire(deps.api, w, deps.downloadsDir, deps.log, deps.acquireOptions);
      if (!got) {
        ledger.misses[key] = now().toISOString();
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
      const ok =
        checked?.codec != null &&
        checked.durationMs != null &&
        (w.durationMs == null || Math.abs(checked.durationMs - w.durationMs) <= 5000);
      if (!ok) {
        deps.log.warn({ event: "COMPLETE_REJECTED", title: w.title, durationMs: checked?.durationMs ?? null });
        await rm(got.path, { force: true });
        await rmdir(dirname(got.path)).catch(() => undefined);
        ledger.misses[key] = now().toISOString();
        missed += 1;
        await saveReplacements(deps.ledgerPath, ledger);
        continue;
      }
      await deps.commit(got.path, size);
      await rmdir(dirname(got.path)).catch(() => undefined);
      delete ledger.misses[key];
      await saveReplacements(deps.ledgerPath, ledger);
      deps.log.info({ event: "COMPLETE_FOUND", album: album.title, title: w.title });
      found += 1;
    }
  }
  return { albums: looked, found, missed };
}
