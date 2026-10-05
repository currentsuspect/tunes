import { statSync } from "node:fs";
import type { Log } from "../logger.js";
import { PermanentError, RetryableError } from "./ports.js";
import { TelegramClient, Api } from "teleproto";
import { StringSession } from "teleproto/sessions/index.js";
import { NewMessage } from "teleproto/events/index.js";
import { FloodWaitError, SlowModeWaitError } from "teleproto/errors/index.js";

export interface AudioRef {
  messageId: number;
  caption: string | null;
  mime: string | null;
  size: number;
  fileName: string | null;
}

const TRANSPORT_RE =
  /while disconnected|not connected|TIMEOUT|timed?[ _-]?out|ECONNRESET|ECONNREFUSED|ENOTFOUND|EPIPE|EHOSTUNREACH|reconnect/i;

export function isTransportError(e: unknown): boolean {
  if (e instanceof RetryableError) return true;
  const msg = e instanceof Error ? e.message : String(e);
  return TRANSPORT_RE.test(msg);
}

const DEFINITIVE_PEER_RE =
  /^(CHANNEL_INVALID|CHANNEL_PRIVATE|CHANNEL_DEACTIVATED|CHAT_ID_INVALID|PEER_ID_INVALID|CHAT_DELETED)/i;

export function isDefinitiveUnresolved(e: unknown): boolean {
  const rpcMsg = (e as { errorMessage?: string } | null)?.errorMessage;
  if (rpcMsg && DEFINITIVE_PEER_RE.test(rpcMsg)) return true;
  const msg = e instanceof Error ? e.message : String(e);
  return DEFINITIVE_PEER_RE.test(msg);
}

function mapMtprotoError(e: unknown): Error {
  if (e instanceof FloodWaitError || e instanceof SlowModeWaitError) {
    const seconds = Number((e as unknown as { seconds: number | bigint }).seconds ?? 30);
    return new RetryableError(`flood_wait ${seconds}s`, seconds * 1000 + 1000);
  }
  const msg = e instanceof Error ? e.message : String(e);
  const m = /FLOOD_WAIT_(\d+)/.exec(msg);
  if (m) return new RetryableError(msg, Number(m[1]) * 1000 + 1000);
  if (/AUTH_KEY_UNREGISTERED|SESSION_REVOKED|USER_DEACTIVATED/i.test(msg)) {
    return new PermanentError(msg);
  }
  if (e instanceof PermanentError || e instanceof RetryableError) return e;
  if (e instanceof Error && /timeout|ECONNRESET|ENOTFOUND|disconnect/i.test(msg)) {
    return new RetryableError(msg);
  }
  return new PermanentError(msg);
}

interface MtprotoCfg {
  apiId: number;
  apiHash: string;
  session: string;
}

export class MtprotoClient {
  private client: TelegramClient | null = null;
  private connectPromise: Promise<TelegramClient> | null = null;
  private poisoned = false;
  /** Channels whose new posts should wake the scanner. Re-attached whenever
   * the client is rebuilt, since handlers live on the client object. */
  private readonly watchers: Array<{ chatId: number; onPost: () => void }> = [];

  constructor(
    private readonly cfg: MtprotoCfg,
    private readonly log: Log
  ) {}

  async connect(): Promise<TelegramClient> {
    if (this.poisoned || (this.client && !this.client.connected)) {
      const dead = this.client;
      this.client = null;
      this.connectPromise = null;
      this.poisoned = false;
      void dead?.disconnect().catch(() => undefined);
    }
    if (this.client && this.client.connected) return this.client;
    if (!this.connectPromise) {
      this.connectPromise = (async () => {
        const session = new StringSession(this.cfg.session);
        const client = new TelegramClient(session, this.cfg.apiId, this.cfg.apiHash, {
          connectionRetries: 3,
          requestRetries: 2,
        });
        await client.connect();
        this.client = client;
        this.attachWatchers(client);
        this.log.info({ event: "MTPROTO_CONNECTED" });
        return client;
      })().catch((err) => {
        this.connectPromise = null;
        throw err;
      });
    }
    return this.connectPromise;
  }

  /** Asks Telegram to tell us when [chatId] gets a new post, so a scan can
   * start at once instead of at the next poll. The poll stays as the safety
   * net: a missed update only costs the old delay. */
  async watchChannel(chatId: number, onPost: () => void): Promise<void> {
    this.watchers.push({ chatId, onPost });
    const client = await this.connect();
    this.attachWatchers(client, [{ chatId, onPost }]);
  }

  private attachWatchers(
    client: TelegramClient,
    only: Array<{ chatId: number; onPost: () => void }> = this.watchers
  ): void {
    for (const { chatId, onPost } of only) {
      client.addEventHandler(() => {
        try {
          onPost();
        } catch {
          void undefined;
        }
      }, new NewMessage({ chats: [chatId] }));
    }
  }

  private invalidateClient(reason: string): void {
    if (!this.poisoned && (this.client !== null || this.connectPromise !== null)) {
      this.log.warn({ event: "MTPROTO_INVALIDATED", reason });
    }
    this.poisoned = true;
  }

  private onInvokeError(e: unknown): Error {
    const msg = e instanceof Error ? e.message : String(e);
    if (/while disconnected/i.test(msg) || (this.client && !this.client.connected)) {
      this.invalidateClient(msg);
    }
    return mapMtprotoError(e);
  }

  async disconnect(): Promise<void> {
    if (this.client) {
      try {
        await this.client.disconnect();
      } catch {
        void undefined;
      }
      this.client = null;
      this.connectPromise = null;
    }
  }

  async getMe(): Promise<{ id: string; firstName: string; username: string | null }> {
    const client = await this.connect();
    const me = await client.getMe();
    return {
      id: String(me.id),
      firstName: me.firstName ?? "",
      username: me.username ?? null,
    };
  }

  private async peer(chatId: number): Promise<Awaited<ReturnType<TelegramClient["getInputEntity"]>>> {
    const client = await this.connect();
    let lastErr: unknown = null;
    for (let attempt = 0; attempt < 5; attempt++) {
      try {
        return await client.getInputEntity(chatId);
      } catch (err) {
        lastErr = err;
        if (isDefinitiveUnresolved(err)) break;
        await client.getDialogs({ limit: 200 }).catch(() => undefined);
      }
    }
    if (lastErr != null && isTransportError(lastErr)) {
      throw new RetryableError(`Cannot resolve peer ${chatId}: link down (${String(lastErr)})`);
    }
    throw new PermanentError(`Cannot resolve peer ${chatId}: user account is not a member?`);
  }

  static audioDocOf(msg: Api.Message): Api.Document | null {
    const anyMsg = msg as unknown as Record<string, unknown>;
    const doc = anyMsg.document;
    if (!(doc instanceof Api.Document)) return null;
    const attrs = (doc as unknown as { attributes?: Array<Record<string, unknown>> }).attributes ?? [];
    const hasVoice = attrs.some((a) => a.className === "DocumentAttributeVoice");
    const mime = doc.mimeType ?? "";
    const isAudio = mime.startsWith("audio/") || attrs.some((a) => a.className === "DocumentAttributeAudio");
    if (!isAudio || hasVoice) return null;
    return doc;
  }

  async *iterAudioMessages(
    chatId: number,
    opts: { minId?: number; limit?: number }
  ): AsyncGenerator<AudioRef> {
    const client = await this.connect();
    const peer = await this.peer(chatId);
    const params: Record<string, unknown> = {
      reverse: true,
      ...(opts.minId != null && opts.minId > 0 ? { minId: opts.minId } : {}),
      ...(opts.limit != null ? { limit: opts.limit } : {}),
    };
    this.log.debug({ event: "ITER_AUDIO_START", chat: chatId, ...params });
    try {
      for await (const msg of client.iterMessages(peer, params)) {
        const doc = MtprotoClient.audioDocOf(msg as Api.Message);
        if (!doc) continue;
        const attrs = (doc as unknown as { attributes?: Array<Record<string, unknown>> }).attributes ?? [];
        const fileName = attrs.find((a) => a.className === "DocumentAttributeFilename")?.fileName as
          | string
          | undefined;
        yield {
          messageId: Number(msg.id),
          caption: (msg as unknown as { message?: string }).message ?? null,
          mime: doc.mimeType ?? null,
          size: Number(doc.size?.toString() ?? 0),
          fileName: fileName ?? null,
        };
      }
    } catch (e) {
      throw this.onInvokeError(e);
    }
  }

  async downloadAudioTo(
    chatId: number,
    messageId: number,
    outPath: string
  ): Promise<number> {
    try {
      const client = await this.connect();
      const peer = await this.peer(chatId);
      const fetched = await client.getMessages(peer, { ids: [messageId] });
      const msg = fetched[0];
      if (!msg) throw new PermanentError(`Source message ${messageId} not found in ${chatId}`);
      const doc = MtprotoClient.audioDocOf(msg as Api.Message);
      if (!doc) throw new PermanentError(`Source message ${messageId} has no audio media`);
      await client.downloadMedia(msg as Api.Message, {
        outputFile: outPath,
        progressCallback: (downloaded: unknown) => {
          try {
            const n = Number(String(downloaded));
            if (n % 262144 === 0) {
              this.log.debug({ event: "DL_PROGRESS", chat: chatId, msg: messageId, bytes: n });
            }
          } catch {
            void undefined;
          }
        },
      });
      return statSync(outPath).size;
    } catch (e) {
      throw this.onInvokeError(e);
    }
  }

  async chatAlive(markedChatId: number): Promise<boolean> {
    const client = await this.connect();
    try {
      await this.peer(markedChatId);
      return true;
    } catch (e) {
      if (isTransportError(e)) throw e;
      return false;
    }
  }

  async findChannelByTitle(title: string): Promise<number | null> {
    const client = await this.connect();
    for await (const d of client.iterDialogs()) {
      if (d.entity instanceof Api.Channel && d.title === title) {
        return this.markedId(d.entity);
      }
    }
    return null;
  }

  private markedId(channel: Api.Channel): number {
    return Number(`-100${channel.id}`);
  }

  async listDialogs(): Promise<Array<{ id: number; title: string; type: string }>> {
    const client = await this.connect();
    const out: Array<{ id: number; title: string; type: string }> = [];
    for await (const d of client.iterDialogs()) {
      const ent = d.entity;
      if (ent instanceof Api.Channel) {
        out.push({ id: this.markedId(ent), title: ent.title ?? "", type: ent.megagroup ? "megagroup" : "channel" });
      } else if (ent instanceof Api.Chat) {
        out.push({ id: Number(d.id), title: d.title ?? "", type: "group" });
      }
    }
    return out;
  }
}