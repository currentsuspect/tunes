/**
 * Telegram as the library's home, the box as a cache (owner, 17 Oct: "move
 * that 25 GB over to Telegram").
 *
 * Two jobs, both careful with the only copy of anything:
 *
 * 1. Archive: songs held here with no live source in a channel tunesd reads
 *    (Soulseek re-sources, mostly) are uploaded to the archive channel and
 *    recorded as seen there, so they stream like everything else.
 * 2. Cache: the object store is held to a byte budget, evicting the least
 *    recently played first, but only songs Telegram is known to still hold:
 *    a live source in a read channel, confirmed by an audit within the last
 *    two weeks. Anything else is never evicted, whatever the budget says.
 */
import { stat } from "node:fs/promises";

import type { State } from "./state.js";
import type { ObjectStore } from "./store.js";

/** In every archive upload's caption. The scanner skips such messages: the
 * archiver records them itself, and a scan woken by the post would otherwise
 * download the song straight back before the archiver had. */
export const ARCHIVE_MARK = "#tunes-archive";

/** How old the last full source audit may be for eviction to trust it. */
export const AUDIT_TRUST_MS = 14 * 24 * 3600 * 1000;

/** Songs Telegram holds a live copy of, in the channels tunesd reads. */
export function liveShas(state: State, channelIds: string[]): Set<string> {
  return new Set(state.liveSightingsFor(channelIds).map((r) => r.sha));
}

/**
 * What eviction may touch: a live source, and a recent audit vouching for it.
 * Without a recent audit nothing is evictable: "seen once" is not "still
 * there" (16 Oct: 119 sources had quietly gone).
 */
export function evictable(
  state: State,
  channelIds: string[],
  now: Date = new Date(),
): (sha: string) => boolean {
  const audited = state.data.auditedAt ? Date.parse(state.data.auditedAt) : NaN;
  if (!Number.isFinite(audited) || now.getTime() - audited > AUDIT_TRUST_MS) {
    return () => false;
  }
  const live = liveShas(state, channelIds);
  return (sha) => live.has(sha);
}

export interface ArchiveCandidate {
  sha: string;
  size: number;
}

/**
 * Held here, with no live source and no live copy of the same audio. A file
 * whose audio already lives in Telegram under another sha is a duplicate the
 * manifest already points away from; uploading it would only make a second
 * copy.
 */
export function needsArchive(
  objects: ArchiveCandidate[],
  live: Set<string>,
  audioShaOf: (sha: string) => string | undefined,
  /** Files the library already stands behind another copy of (the
   * replacement ledger's `redundant`): never uploaded as a second copy. */
  skip: Set<string> = new Set(),
): ArchiveCandidate[] {
  const liveAudio = new Set<string>();
  for (const s of live) {
    const a = audioShaOf(s);
    if (a) liveAudio.add(a);
  }
  return objects.filter((o) => {
    if (live.has(o.sha) || skip.has(o.sha)) return false;
    const a = audioShaOf(o.sha);
    return !(a && liveAudio.has(a));
  });
}

export interface TrackMeta {
  title?: string;
  artist?: string;
  album?: string;
  durationMs?: number;
  codec?: string;
}

export interface Uploader {
  uploadAudio(
    chatId: number,
    filePath: string,
    meta: { fileName: string; title?: string; performer?: string; durationSec?: number; caption?: string },
  ): Promise<{ messageId: number; size: number }>;
}

export interface ArchiveDeps {
  store: Pick<ObjectStore, "pathOf">;
  state: State;
  tg: Uploader;
  /** Marked id of the channel to upload into; must be one tunesd reads. */
  archiveChat: number;
  meta: (sha: string) => TrackMeta | undefined;
  log: { info: (o: Record<string, unknown>) => void; warn: (o: Record<string, unknown>) => void };
  sleep: (ms: number) => Promise<void>;
}

/** A filename Telegram and people can read: "Artist - Title.flac". */
export function fileNameFor(sha: string, m: TrackMeta | undefined): string {
  const ext = (m?.codec ?? "audio").toLowerCase() === "flac" ? "flac" : (m?.codec ?? "bin").toLowerCase();
  const name = [m?.artist, m?.title].filter((x) => x && x.trim()).join(" - ");
  const safe = name.replace(/[\\/:*?"<>|\n\r]+/g, " ").replace(/\s+/g, " ").trim().slice(0, 120);
  return `${safe || sha.slice(0, 16)}.${ext}`;
}

/**
 * Uploads [candidates] one at a time, paced, recording each as seen in the
 * archive channel the moment Telegram confirms it. A size mismatch is
 * treated as a failed upload and not recorded. Stops at the first transport
 * error: the next pass carries on where this one stopped.
 */
export async function archiveAll(
  deps: ArchiveDeps,
  candidates: ArchiveCandidate[],
  opts: { max: number; pauseMs: number },
): Promise<{ uploaded: number; failed: number; bytes: number }> {
  let uploaded = 0;
  let failed = 0;
  let bytes = 0;
  for (const c of candidates.slice(0, opts.max)) {
    const path = deps.store.pathOf(c.sha);
    try {
      await stat(path);
    } catch {
      continue; // evicted or moved since the plan was made
    }
    const m = deps.meta(c.sha);
    const fileName = fileNameFor(c.sha, m);
    try {
      const r = await deps.tg.uploadAudio(deps.archiveChat, path, {
        fileName,
        title: m?.title,
        performer: m?.artist,
        durationSec: m?.durationMs ? m.durationMs / 1000 : undefined,
        caption: [[m?.artist, m?.title, m?.album].filter(Boolean).join(" · "), ARCHIVE_MARK]
          .filter(Boolean)
          .join("\n"),
      });
      if (r.size !== c.size) {
        failed += 1;
        deps.log.warn({ event: "ARCHIVE_SIZE_MISMATCH", sha: c.sha, sent: c.size, got: r.size, msg: r.messageId });
      } else {
        deps.state.markSeen(String(deps.archiveChat), r.messageId, c.sha, null, fileName);
        await deps.state.save();
        uploaded += 1;
        bytes += c.size;
        deps.log.info({ event: "ARCHIVED", sha: c.sha, msg: r.messageId, bytes: c.size });
      }
    } catch (e) {
      failed += 1;
      deps.log.warn({ event: "ARCHIVE_FAILED", sha: c.sha, err: String((e as Error).message ?? e) });
      break;
    }
    await deps.sleep(opts.pauseMs);
  }
  return { uploaded, failed, bytes };
}
