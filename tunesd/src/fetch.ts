import type { Log } from "./logger.js";
import { ObjectStore } from "./store.js";
import { State } from "./state.js";
import { MtprotoClient } from "./telegram/mtproto.js";
import { RetryableError, sleep } from "./telegram/ports.js";

export interface ChannelConfig {
  id: number;
  title: string;
  enabled: boolean;
}

export interface CycleStats {
  channel: string;
  scanned: number;
  downloaded: number;
  skippedSeen: number;
  bytes: number;
  capReached: boolean;
  transportStopped: boolean;
}

export interface CycleResult {
  channels: CycleStats[];
  aborted: boolean;
  reason: string | null;
}

function jitterDelay(baseMs: number, jitterMs: number): number {
  return baseMs + Math.floor(Math.random() * (jitterMs + 1));
}

export class FetchEngine {
  constructor(
    private readonly client: MtprotoClient,
    private readonly store: ObjectStore,
    private readonly state: State,
    private readonly env: {
      dataDir: string;
      fetch: { perChannelDelayMs: number; jitterMs: number; dailyCapFiles: number };
    },
    private readonly log: Log
  ) {}

  async runCycle(channels: ChannelConfig[]): Promise<CycleResult> {
    const result: CycleResult = { channels: [], aborted: false, reason: null };

    for (const channel of channels) {
      if (!channel.enabled) continue;

      let remaining = this.state.dailyRemaining(this.env.fetch.dailyCapFiles);
      if (remaining <= 0) {
        result.aborted = true;
        result.reason = "DAILY_CAP_REACHED";
        this.log.warn({ event: "CAP_REACHED", channel: channel.id });
        break;
      }

      let alive: boolean;
      try {
        alive = await this.client.chatAlive(channel.id);
      } catch (e) {
        if (e instanceof RetryableError) {
          result.aborted = true;
          result.reason = "TRANSPORT_BROKEN";
          this.log.error({ event: "PROBE_FAILED", channel: channel.id, err: String(e) });
          break;
        }
        throw e;
      }
      if (!alive) {
        this.log.warn({ event: "CHANNEL_GONE", channel: channel.id });
        result.channels.push({
          channel: channel.title,
          scanned: 0,
          downloaded: 0,
          skippedSeen: 0,
          bytes: 0,
          capReached: false,
          transportStopped: false,
        });
        continue;
      }

      const cursor = this.state.cursorOf(String(channel.id));
      const stats: CycleStats = {
        channel: channel.title,
        scanned: 0,
        downloaded: 0,
        skippedSeen: 0,
        bytes: 0,
        capReached: false,
        transportStopped: false,
      };
      let maxSeen = cursor.headCursor;
      let floodSecondChance = false;

      try {
        for await (const ref of this.client.iterAudioMessages(channel.id, {
          minId: cursor.headCursor,
        })) {
          stats.scanned += 1;

          if (this.state.hasSeen(String(channel.id), ref.messageId)) {
            if (ref.messageId > maxSeen) maxSeen = ref.messageId;
            stats.skippedSeen += 1;
            continue;
          }

          remaining = this.state.dailyRemaining(this.env.fetch.dailyCapFiles);
          if (remaining <= 0) {
            stats.capReached = true;
            break;
          }

          const staging = await this.store.beginStaging();
          try {
            this.log.info({
              event: "DL_START",
              channel: channel.id,
              msg: ref.messageId,
              size: ref.size,
            });
            const got = await this.client.downloadAudioTo(channel.id, ref.messageId, staging.path);
            if (got !== ref.size) throw new RetryableError(`size mismatch: got ${got}, expected ${ref.size}`);
            const { sha, size } = await staging.done(ref.size);
            this.state.markSeen(String(channel.id), ref.messageId, sha);
            this.state.tallyFetch();
            stats.downloaded += 1;
            stats.bytes += size;
            if (ref.messageId > maxSeen) maxSeen = ref.messageId;
            this.log.info({
              event: "DL_DONE",
              channel: channel.id,
              msg: ref.messageId,
              sha,
              size,
            });
            await this.state.save();
          } catch (e) {
            await this.store.discardStaging(staging.path).catch(() => undefined);
            throw e;
          }

          await sleep(jitterDelay(this.env.fetch.perChannelDelayMs, this.env.fetch.jitterMs));
        }
      } catch (e) {
        if (e instanceof RetryableError) {
          const wait = e.retryAfterMs ?? null;
          if (wait != null && !floodSecondChance) {
            floodSecondChance = true;
            this.log.warn({
              event: "FLOOD_WAIT_RETRY",
              channel: channel.id,
              waitMs: Math.min(wait, 60_000),
            });
            await sleep(Math.min(wait, 60_000));
            continue;
          }
          stats.transportStopped = true;
          result.aborted = true;
          result.reason = "TRANSPORT_STOP";
          this.log.error({
            event: "TRANSPORT_STOP",
            channel: channel.id,
            err: String(e),
          });
        } else {
          throw e;
        }
      }

      if (maxSeen > cursor.headCursor || cursor.lastScanAt === null) {
        this.state.setCursor(String(channel.id), {
          headCursor: maxSeen,
          lastScanAt: new Date().toISOString(),
        });
        await this.state.save();
      }
      result.channels.push(stats);
      if (result.aborted) break;
    }

    return result;
  }
}