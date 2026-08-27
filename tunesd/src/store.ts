import { createHash, randomBytes } from "node:crypto";
import { accessSync, createReadStream, statSync } from "node:fs";
import { mkdir, rename, rm, stat } from "node:fs/promises";
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