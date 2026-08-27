import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";

export interface SeenFile {
  channelId: string;
  messageId: number;
  sha: string;
  size: number;
  addedAt: string;
}

export interface ChannelCursor {
  headCursor: number;
  lastScanAt: string | null;
}

interface StateFile {
  schema: 1;
  channels: Record<string, ChannelCursor>;
  seen: Record<string, string>;
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
    const sha = this.data.seen[this.seenKey(channelId, messageId)];
    return Boolean(sha);
  }

  seenSha(channelId: string, messageId: number): string | null {
    return this.data.seen[this.seenKey(channelId, messageId)] ?? null;
  }

  markSeen(channelId: string, messageId: number, sha: string): void {
    this.data.seen[this.seenKey(channelId, messageId)] = sha;
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
    return [...new Set(Object.values(this.data.seen))];
  }
}