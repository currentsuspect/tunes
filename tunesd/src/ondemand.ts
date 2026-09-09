import { rm } from "node:fs/promises";

import type { Log } from "./logger.js";
import { ObjectStore } from "./store.js";
import { State } from "./state.js";
import type { MtprotoClient } from "./telegram/mtproto.js";
import { RetryableError } from "./telegram/ports.js";

export interface OnDemandEnv {
  dailyCapFiles: number;
  /** How many Telegram fetches may run at once. Past that, serve 404 rather
   * than queue: a miss that waits behind five downloads is not the honest
   * 1–3 s latency SPEC §1.8 promises, it is a stall wearing its name. */
  maxInflight?: number;
}

/** Serves store misses from Telegram instead of answering 404.
 *
 * ORIGIN step 1: SPEC §2.1 always specified on-demand fetch, but serve.ts
 * never called it -- a miss was a `stat` failure, so the box had to hold the
 * whole library to serve anything. This wires the specified path: resolve
 * the sha to its source message through the seen index, download it, commit
 * it to the store, and serve it like anything else.
 *
 * Ban-safety is inherited, not re-decided: a tap is human-low-frequency by
 * nature and exempt from jitter, but every fetch counts against the daily
 * cap, and transport errors stop and report -- never retry hot.
 */
export class OnDemandFetcher {
  private readonly inflight = new Map<string, Promise<string | null>>();
  private readonly maxInflight: number;

  constructor(
    private readonly client: MtprotoClient,
    private readonly store: ObjectStore,
    private readonly state: State,
    private readonly env: OnDemandEnv,
    private readonly log: Log,
  ) {
    this.maxInflight = env.maxInflight ?? 2;
  }

  /** Local path for `sha`, fetching from Telegram on a miss. Null means 404:
   * unknown sha, exhausted cap, busy fetcher, or a failed download. Never
   * throws for any of those -- the HTTP layer turns null into "not found". */
  async fetchTrack(sha: string): Promise<string | null> {
    if (!/^[0-9a-f]{64}$/.test(sha)) return null;
    if (this.store.has(sha)) return this.store.pathOf(sha);
    const running = this.inflight.get(sha);
    if (running) return running;
    if (this.inflight.size >= this.maxInflight) {
      this.log.warn({ event: "ONDEMAND_BUSY", inflight: this.inflight.size });
      return null;
    }
    const p = this.doFetch(sha).finally(() => {
      if (this.inflight.get(sha) === p) this.inflight.delete(sha);
    });
    this.inflight.set(sha, p);
    return p;
  }

  private async doFetch(sha: string): Promise<string | null> {
    const sources = this.state.findMessages(sha);
    if (sources.length === 0) {
      // No message holds this sha: deleted upstream, or a sha that was never
      // ours. A 404 is the honest answer, not a fetch of something else.
      this.log.info({ event: "ONDEMAND_UNKNOWN" });
      return null;
    }
    if (this.state.dailyRemaining(this.env.dailyCapFiles) <= 0) {
      this.log.warn({ event: "ONDEMAND_CAP_REACHED" });
      return null;
    }
    // One row per source: a re-posted track, or an account swap that orphaned
    // the old channel's rows, leaves several. A dead source fails fast and
    // the next is tried -- seen live when the pre-swap channel's messages
    // answered "not found" while the bytes were reachable elsewhere.
    for (const src of sources) {
      const got = await this.trySource(sha, src.channelId, src.messageId);
      if (got !== null) return got;
    }
    return null;
  }

  private async trySource(
    sha: string,
    channelId: string,
    messageId: number,
  ): Promise<string | null> {
    this.log.info({ event: "ONDEMAND_START", msg: messageId });
    const staging = await this.store.beginStaging();
    try {
      const got = await this.client.downloadAudioTo(
        Number(channelId),
        messageId,
        staging.path,
      );
      const { sha: gotSha, size } = await staging.done(got);
      if (gotSha !== sha) {
        // Bytes for somebody else (re-uploaded message, moved file). The
        // store filed them under their own sha, correctly -- but serving
        // them for the requested one would be a lie, so this is still a miss.
        this.log.warn({ event: "ONDEMAND_MISMATCH", bytes: size });
        return null;
      }
      this.state.tallyFetch();
      await this.state.save();
      this.log.info({ event: "ONDEMAND_DONE", bytes: size });
      return this.store.pathOf(sha);
    } catch (e) {
      await rm(staging.path, { force: true });
      if (e instanceof RetryableError) {
        this.log.error({ event: "ONDEMAND_TRANSPORT", err: String(e) });
        return null;
      }
      this.log.warn({ event: "ONDEMAND_FAILED", err: String(e) });
      return null;
    }
  }
}
