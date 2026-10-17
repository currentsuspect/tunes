import { createHash, randomBytes } from "node:crypto";
import { accessSync, createReadStream, statSync } from "node:fs";
import { mkdir, rename, rm, stat, utimes } from "node:fs/promises";
import { dirname, join } from "node:path";
import { RetryableError } from "./telegram/ports.js";

export class ObjectStore {
  constructor(private readonly rootDir: string) {}

  private stagingDir(): string {
    return join(this.rootDir, "objects", ".staging");
  }

  private objectPath(sha: string): string {
    return join(this.rootDir, "objects", sha.slice(0, 2), sha);
  }

  has(sha: string): boolean {
    try {
      accessSync(this.objectPath(sha));
      return true;
    } catch {
      return false;
    }
  }

  pathOf(sha: string): string {
    return this.objectPath(sha);
  }

  /** Reference counts, not a set: one listener stopping must not unpin a
   * second streaming the same song. */
  private readonly activeReads = new Map<string, number>();

  /** Marks a song as just played, for the cache's least-recent order. */
  async touch(sha: string): Promise<void> {
    const now = new Date();
    try {
      await utimes(this.objectPath(sha), now, now);
    } catch {
      // Evicted meanwhile: the same as a miss for the caller.
    }
  }

  /** Pins a song while it streams; call the returned function when done. */
  beginRead(sha: string): () => void {
    this.activeReads.set(sha, (this.activeReads.get(sha) ?? 0) + 1);
    void this.touch(sha);
    let released = false;
    return () => {
      if (released) return;
      released = true;
      const n = this.activeReads.get(sha) ?? 0;
      if (n <= 1) this.activeReads.delete(sha);
      else this.activeReads.set(sha, n - 1);
    };
  }

  /**
   * Holds the store to [maxBytes], least recently played first, evicting only
   * what [evictable] allows (archive.ts: a live, recently audited Telegram
   * source). Songs that are only here stay, even over budget. Streaming
   * songs and [protect] stay too.
   */
  async prune(
    maxBytes: number,
    evictable: (sha: string) => boolean,
    protect: Iterable<string> = [],
  ): Promise<{ bytes: number; removed: number; freed: number; kept: number }> {
    const keep = new Set([...protect, ...this.activeReads.keys()]);
    const entries: Array<{ sha: string; size: number; at: number }> = [];
    for (const o of await this.listObjects()) {
      try {
        const info = await stat(this.objectPath(o.sha));
        entries.push({ sha: o.sha, size: info.size, at: info.mtimeMs });
      } catch {
        // Gone meanwhile.
      }
    }
    let bytes = entries.reduce((sum, e) => sum + e.size, 0);
    let removed = 0;
    let freed = 0;
    entries.sort((a, b) => a.at - b.at || a.sha.localeCompare(b.sha));
    for (const e of entries) {
      if (bytes <= maxBytes) break;
      if (keep.has(e.sha) || !evictable(e.sha)) continue;
      await rm(this.objectPath(e.sha), { force: true });
      bytes -= e.size;
      freed += e.size;
      removed += 1;
    }
    return { bytes, removed, freed, kept: entries.length - removed };
  }

  sizeOf(sha: string): number {
    try {
      return statSync(this.objectPath(sha)).size;
    } catch {
      return -1;
    }
  }

  async beginStaging(): Promise<{
    path: string;
    done: (expectedSize: number) => Promise<{ sha: string; size: number }>;
  }> {
    const dir = this.stagingDir();
    await mkdir(dir, { recursive: true });
    const path = join(dir, `${Date.now()}-${randomBytes(6).toString("hex")}.part`);

    const hashAndFinalize = async (expectedSize: number) => {
      let size: number;
      try {
        size = (await stat(path)).size;
      } catch {
        throw new RetryableError("staging file disappeared before finalize");
      }
      if (size !== expectedSize) {
        await rm(path, { force: true });
        throw new RetryableError(`size mismatch: got ${size}, expected ${expectedSize}`);
      }
      const sha = await this.hashFile(path);
      const dest = this.objectPath(sha);
      if (!this.has(sha)) {
        await mkdir(dirname(dest), { recursive: true });
        await rename(path, dest);
      } else {
        await rm(path, { force: true });
      }
      return { sha, size };
    };

    return { path, done: hashAndFinalize };
  }

  discardStaging(path: string): Promise<void> {
    return rm(path, { force: true });
  }

  async verify(sha: string): Promise<boolean> {
    try {
      accessSync(this.objectPath(sha));
    } catch {
      return false;
    }
    const actual = await this.hashFile(this.objectPath(sha));
    return actual === sha;
  }

  async listObjects(): Promise<Array<{ sha: string; size: number }>> {
    const { readdir } = await import("node:fs/promises");
    const root = join(this.rootDir, "objects");
    const out: Array<{ sha: string; size: number }> = [];
    let prefixDirs: string[] = [];
    try {
      prefixDirs = await readdir(root);
    } catch {
      return out;
    }
    for (const prefix of prefixDirs) {
      if (prefix.startsWith(".")) continue;
      try {
        const files = await readdir(join(root, prefix));
        for (const f of files) {
          if (!/^[0-9a-f]{64}$/.test(f)) continue;
          try {
            const s = statSync(join(root, prefix, f));
            out.push({ sha: f, size: s.size });
          } catch {
            // unreadable object: skip, sync layer flags it later
          }
        }
      } catch {
        // unreadable prefix dir: skip
      }
    }
    return out.sort((a, b) => (a.sha < b.sha ? -1 : 1));
  }

  private async hashFile(p: string): Promise<string> {
    return new Promise((resolve, reject) => {
      const hash = createHash("sha256");
      const stream = createReadStream(p);
      stream.on("error", reject);
      stream.on("data", (chunk) => hash.update(chunk));
      stream.on("end", () => resolve(hash.digest("hex")));
    });
  }
}