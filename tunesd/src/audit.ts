import type { Log } from "./logger.js";
import type { State } from "./state.js";
import { RetryableError, sleep } from "./telegram/ports.js";

/** What [auditSources] needs from Telegram: which of these ids in a chat no
 * longer hold audio. MtprotoClient.missingAudio, or a fake in tests. */
export interface SourceChecker {
  missingAudio(chatId: number, ids: number[]): Promise<number[]>;
}

export interface AuditOptions {
  channelIds: string[];
  /** Ids per call. Telegram takes up to 100 in one getMessages. */
  batch?: number;
  /** Pause between calls. Read-only and cheap, but paced like everything
   * else that talks to Telegram (SPEC §4): no bursts. */
  pause?: () => number;
}

/** Checks every source message the library knows of and records the ones
 * that are gone (State.markGone), so the manifest stops offering copies that
 * can never play and points them at a live copy of the same recording.
 *
 * Until now a deleted message was only found out when someone pressed play:
 * the song skipped, every time, while an identical copy sat in another
 * message. This finds them all in one pass of reads, with no downloads.
 *
 * Transport errors stop the pass and report; nothing is retried hot. Known
 * gone sources are not asked about again. State is saved after every batch,
 * so a pass cut short keeps what it learned.
 */
export async function auditSources(
  checker: SourceChecker,
  state: State,
  log: Log,
  opts: AuditOptions
): Promise<{ checked: number; gone: number; stopped: boolean }> {
  const batch = Math.min(Math.max(opts.batch ?? 100, 1), 100);
  const pause = opts.pause ?? (() => 4000 + Math.random() * 3000);
  const byChat = new Map<number, number[]>();
  for (const r of state.sightingsFor(opts.channelIds)) {
    if (state.isGone(String(r.chat), r.msg)) continue;
    const list = byChat.get(r.chat) ?? [];
    list.push(r.msg);
    byChat.set(r.chat, list);
  }
  let checked = 0;
  let gone = 0;
  let first = true;
  log.info({ event: "AUDIT_START", chats: byChat.size });
  for (const [chat, all] of byChat) {
    const ids = [...new Set(all)].sort((a, b) => a - b);
    for (let i = 0; i < ids.length; i += batch) {
      if (!first) await sleep(pause());
      first = false;
      const slice = ids.slice(i, i + batch);
      let missing: number[];
      try {
        missing = await checker.missingAudio(chat, slice);
      } catch (e) {
        const transport = e instanceof RetryableError;
        log.error({ event: "AUDIT_STOPPED", transport, err: String(e), checked, gone });
        return { checked, gone, stopped: true };
      }
      for (const id of missing) state.markGone(String(chat), id);
      checked += slice.length;
      gone += missing.length;
      await state.save();
    }
  }
  state.data.auditedAt = new Date().toISOString();
  await state.save();
  log.info({ event: "AUDIT_DONE", checked, gone });
  return { checked, gone, stopped: false };
}

/** Whether a full pass is due: never run, or older than [every]. */
export function auditDue(
  auditedAt: string | null | undefined,
  now: Date,
  every: number = 7 * 24 * 60 * 60 * 1000
): boolean {
  if (!auditedAt) return true;
  const at = Date.parse(auditedAt);
  return !Number.isFinite(at) || now.getTime() - at >= every;
}
