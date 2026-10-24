import { statSync } from "node:fs";
import type { Log } from "../logger.js";
import { PermanentError, RetryableError, SourceGoneError } from "./ports.js";
import { TelegramClient, Api } from "teleproto";
import { StringSession } from "teleproto/sessions/index.js";
import { NewMessage } from "teleproto/events/index.js";
import { FloodWaitError, SlowModeWaitError } from "teleproto/errors/index.js";
import { CustomFile } from "teleproto/client/uploads.js";

export interface AudioRef {
  messageId: number;
  caption: string | null;
  mime: string | null;
  size: number;
  fileName: string | null;
}

const TRANSPORT_RE =
  /while disconnected|not connected|disconnect|TIMEOUT|timed?[ _-]?out|deadline exceeded|ECONNRESET|ECONNREFUSED|ENOTFOUND|EPIPE|EHOSTUNREACH|ETIMEDOUT|reconnect/i;

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

export function mapMtprotoError(e: unknown): Error {
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
  // A slow or dropped connection is not a reason to stop. "Media request
  // deadline exceeded" and "Could not reconnect to dc 4" fell through to
  // PermanentError and took the daemon down four times in the week to 24
  // Oct, losing everyone's queued gets each time.
  if (isTransportError(msg)) return new RetryableError(msg);
  // Moving a download to another data centre exports the login there, and
  // that hand-over sometimes fails ("The provided authorization is invalid",
  // AUTH_BYTES_INVALID). The session itself is fine: a restart got straight
  // back in on 24 Oct. Asked again later, not fatal.
  if (/AUTH_BYTES_INVALID|provided authorization is invalid/i.test(msg)) {
    return new RetryableError(msg, 60_000);
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

  /** Which of [ids] in [chatId] no longer hold audio: deleted, emptied, or
   * edited to something else. One call for up to 100 ids, no downloads. */
  async missingAudio(chatId: number, ids: number[]): Promise<number[]> {
    try {
      const client = await this.connect();
      const peer = await this.peer(chatId);
      const fetched = await client.getMessages(peer, { ids });
      const present = new Set<number>();
      for (const m of fetched as unknown as Array<Api.Message | undefined>) {
        if (!m || (m as { className?: string }).className === "MessageEmpty") continue;
        if (MtprotoClient.audioDocOf(m) == null) continue;
        present.add(Number(m.id));
      }
      return ids.filter((id) => !present.has(id));
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
      if (!msg || (msg as { className?: string }).className === "MessageEmpty") {
        throw new SourceGoneError(`Source message ${messageId} not found in ${chatId}`);
      }
      const doc = MtprotoClient.audioDocOf(msg as Api.Message);
      if (!doc) throw new SourceGoneError(`Source message ${messageId} has no audio media`);
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

  /**
   * Uploads a file as an audio document (never re-encoded: Telegram keeps a
   * document's bytes as sent, so the copy hashes the same). Returns the new
   * message's id and the document's size as Telegram recorded it.
   */
  async uploadAudio(
    chatId: number,
    filePath: string,
    meta: { fileName: string; title?: string; performer?: string; durationSec?: number; caption?: string },
  ): Promise<{ messageId: number; size: number }> {
    try {
      const client = await this.connect();
      const peer = await this.peer(chatId);
      // Named, not a bare path: store objects are named by sha with no
      // extension, and the library takes the file type from the name. A bare
      // path went up as an untyped document (17 Oct).
      const file = new CustomFile(meta.fileName, statSync(filePath).size, filePath);
      const sent = (await client.sendFile(peer, {
        file,
        caption: meta.caption ?? "",
        forceDocument: false,
        attributes: [
          new Api.DocumentAttributeAudio({
            duration: Math.max(0, Math.round(meta.durationSec ?? 0)),
            title: meta.title,
            performer: meta.performer,
          }),
          new Api.DocumentAttributeFilename({ fileName: meta.fileName }),
        ],
      })) as Api.Message;
      // Judged on the message as Telegram holds it, read back, not on the
      // send's reply.
      const [back] = await client.getMessages(peer, { ids: [sent.id] });
      const doc = back ? MtprotoClient.audioDocOf(back as Api.Message) : null;
      if (!doc) {
        // Not playable as audio: take it down again so no stray copy is left.
        await client.deleteMessages(peer, [sent.id], { revoke: true }).catch(() => undefined);
        throw new Error("upload did not come back as an audio document");
      }
      return { messageId: sent.id, size: Number(doc.size) };
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