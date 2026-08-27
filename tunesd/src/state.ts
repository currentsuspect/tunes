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
}

interface StateFile {
  schema: 1;
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
    schema: 1,
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
      if (parsed.schema !== 1) throw new Error(`unsupported state schema ${parsed.schema}`);
      this.data = {
        schema: 1,
        channels: parsed.channels ?? {},
        seen: parsed.seen ?? {},
        dailyFetched: parsed.dailyFetched ?? 0,
        dailyDate: parsed.dailyDate ?? todayKey(),
      };
    } catch {
      this.data = {
        schema: 1,
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

  markSeen(
    channelId: string,
    messageId: number,
    sha: string,
    caption: string | null = null,
    fileName: string | null = null
  ): void {
    this.data.seen[this.seenKey(channelId, messageId)] = {
      sha,
      caption: caption !== "" ? caption : null,
      fileName,
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

  allSeenMeta(): Map<string, { caption: string | null; fileName: string | null }> {
    const out = new Map<string, { caption: string | null; fileName: string | null }>();
    for (const v of Object.values(this.data.seen)) {
      if (typeof v === "string") continue;
      if (!out.has(v.sha)) out.set(v.sha, { caption: v.caption ?? null, fileName: v.fileName ?? null });
    }
    return out;
  }
}