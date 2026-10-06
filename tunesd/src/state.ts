import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";

export interface SeenFile {
  channelId: string;
  messageId: number;
  sha: string;
  caption: string | null;
  fileName: string | null;
  addedAt: string;
}

export interface ChannelCursor {
  headCursor: number;
  lastScanAt: string | null;
}

export interface SeenEntry {
  sha: string;
  caption: string | null;
  fileName: string | null;
  addedAt?: string;
}

interface StateFile {
  schema: 1 | 2;
  channels: Record<string, ChannelCursor>;
  seen: Record<string, string | SeenEntry>;
  dailyFetched: number;
  dailyDate: string;
}

function todayKey(): string {
  return new Date().toISOString().slice(0, 10);
}

export class State {
  data: StateFile = {
    schema: 2,
    channels: {},
    seen: {},
    dailyFetched: 0,
    dailyDate: todayKey(),
  };

  constructor(private readonly path: string) {}

  async load(): Promise<State> {
    try {
      const raw = await readFile(this.path, "utf8");
      const parsed = JSON.parse(raw) as StateFile;
      if (parsed.schema !== 1 && parsed.schema !== 2) {
        throw new Error(`unsupported state schema ${parsed.schema}`);
      }
      this.data = {
        schema: 2,
        channels: parsed.channels ?? {},
        seen: parsed.seen ?? {},
        dailyFetched: parsed.dailyFetched ?? 0,
        dailyDate: parsed.dailyDate ?? todayKey(),
      };
    } catch {
      this.data = {
        schema: 2,
        channels: {},
        seen: {},
        dailyFetched: 0,
        dailyDate: todayKey(),
      };
    }
    return this;
  }

  async save(): Promise<void> {
    await mkdir(dirname(this.path), { recursive: true });
    const tmp = join(dirname(this.path), `.state-${process.pid}.tmp`);
    await writeFile(tmp, JSON.stringify(this.data, null, 1));
    await rename(tmp, this.path);
  }

  seenKey(channelId: string, messageId: number): string {
    return `${channelId}:${messageId}`;
  }

  hasSeen(channelId: string, messageId: number): boolean {
    const entry = this.data.seen[this.seenKey(channelId, messageId)];
    return entry !== undefined;
  }

  seenSha(channelId: string, messageId: number): string | null {
    const entry = this.data.seen[this.seenKey(channelId, messageId)];
    return entry === undefined ? null : (typeof entry === "string" ? entry : entry.sha);
  }

  seenMeta(
    channelId: string,
    messageId: number
  ): { sha: string; caption: string | null; fileName: string | null } | null {
    const entry = this.data.seen[this.seenKey(channelId, messageId)];
    if (entry === undefined) return null;
    if (typeof entry === "string") return { sha: entry, caption: null, fileName: null };
    return { sha: entry.sha, caption: entry.caption ?? null, fileName: entry.fileName ?? null };
  }

  /** Every sighting in the given channels, for the cloud publish.
   *
   * Oldest first, each carrying its first-seen stamp: the publisher sends
   * only rows newer than its watermark, so a cycle is usually an empty diff
   * instead of 637 upserts. D1's free tier counts writes, and a full rewrite
   * every five minutes tripped it. */
  /** Every channel a track was ever seen in, including ones no longer
   * configured. A retired channel's tracks still live in Telegram, and the
   * cloud fetcher can only play what it has a source for. */
  channelIdsSeen(): string[] {
    const ids = new Set<string>();
    for (const key of Object.keys(this.data.seen)) {
      const i = key.lastIndexOf(":");
      if (i > 0) ids.add(key.slice(0, i));
    }
    return [...ids];
  }

  sightingsFor(channelIds: string[]): { sha: string; chat: number; msg: number; addedAt: string | null }[] {
    const live = new Set(channelIds);
    const out: { sha: string; chat: number; msg: number; addedAt: string | null }[] = [];
    for (const [key, v] of Object.entries(this.data.seen)) {
      const i = key.lastIndexOf(":");
      if (i < 0) continue;
      const channelId = key.slice(0, i);
      if (!live.has(channelId)) continue;
      const messageId = Number(key.slice(i + 1));
      if (!Number.isInteger(messageId)) continue;
      const sha = typeof v === "string" ? v : v.sha;
      const addedAt = typeof v === "string" ? null : (v.addedAt ?? null);
      out.push({ sha, chat: Number(channelId), msg: messageId, addedAt });
    }
    out.sort((a, b) => (a.addedAt ?? "").localeCompare(b.addedAt ?? ""));
    return out;
  }

  /** Reverse lookup: which message holds `sha`, if any.
   *
   * The seen index runs message → sha; the on-demand fetcher needs the other
   * direction. A linear scan over hundreds of entries per miss is nothing
   * next to the Telegram round trip that follows, so no second index is kept
   * in sync -- one source of truth, read both ways. */
  findMessage(sha: string): { channelId: string; messageId: number } | null {
    return this.findMessages(sha)[0] ?? null;
  }

  /** Every message holding `sha`, oldest first.
   *
   * A track re-posted across channels (or surviving an account swap in one
   * channel but not the other) has several rows; the fetcher tries each in
   * turn, so one dead source does not doom the rest. */
  findMessages(sha: string): { channelId: string; messageId: number }[] {
    const out: { channelId: string; messageId: number }[] = [];
    for (const [key, v] of Object.entries(this.data.seen)) {
      const s = typeof v === "string" ? v : v.sha;
      if (s !== sha) continue;
      const i = key.lastIndexOf(":");
      if (i < 0) continue;
      const messageId = Number(key.slice(i + 1));
      if (!Number.isInteger(messageId)) continue;
      out.push({ channelId: key.slice(0, i), messageId });
    }
    return out;
  }

  markSeen(
    channelId: string,
    messageId: number,
    sha: string,
    caption: string | null = null,
    fileName: string | null = null
  ): void {
    const key = this.seenKey(channelId, messageId);
    const existing = this.data.seen[key];
    const sameSha =
      typeof existing === "object" && existing !== null && existing.sha === sha;
    const existingAddedAt = sameSha ? existing.addedAt ?? null : null;
    this.data.seen[key] = {
      sha,
      caption: caption !== "" ? caption : null,
      fileName,
      addedAt: existingAddedAt ?? new Date().toISOString(),
    };
  }

  cursorOf(channelId: string): ChannelCursor {
    return (
      this.data.channels[channelId] ?? { headCursor: 0, lastScanAt: null }
    );
  }

  setCursor(channelId: string, cursor: ChannelCursor): void {
    this.data.channels[channelId] = cursor;
  }

  dailyRemaining(cap: number): number {
    if (this.data.dailyDate !== todayKey()) {
      this.data.dailyDate = todayKey();
      this.data.dailyFetched = 0;
    }
    return Math.max(0, cap - this.data.dailyFetched);
  }

  tallyFetch(): number {
    if (this.data.dailyDate !== todayKey()) {
      this.data.dailyDate = todayKey();
      this.data.dailyFetched = 0;
    }
    this.data.dailyFetched += 1;
    return this.data.dailyFetched;
  }

  allSeenShas(): string[] {
    return [
      ...new Set(
        Object.values(this.data.seen).map((v) => (typeof v === "string" ? v : v.sha))
      ),
    ];
  }

  addedAtFor(sha: string): string | null {
    for (const v of Object.values(this.data.seen)) {
      if (typeof v === "string") continue;
      if (v.sha === sha) return v.addedAt ?? null;
    }
    return null;
  }

  allAddedAt(): Map<string, string> {
    const out = new Map<string, string>();
    for (const v of Object.values(this.data.seen)) {
      if (typeof v === "string") continue;
      if (v.addedAt && !out.has(v.sha)) out.set(v.sha, v.addedAt);
    }
    return out;
  }

  allSeenMeta(): Map<string, { caption: string | null; fileName: string | null }> {
    const out = new Map<string, { caption: string | null; fileName: string | null }>();
    for (const v of Object.values(this.data.seen)) {
      if (typeof v === "string") continue;
      if (!out.has(v.sha)) out.set(v.sha, { caption: v.caption ?? null, fileName: v.fileName ?? null });
    }
    return out;
  }
}