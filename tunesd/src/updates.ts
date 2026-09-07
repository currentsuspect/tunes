import { createWriteStream } from "node:fs";
import { mkdir, rename, stat, unlink } from "node:fs/promises";
import { join } from "node:path";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import type { Log } from "./logger.js";

/**
 * App updates, served to phones from here rather than from GitHub.
 *
 * The repository is private, so a phone cannot ask GitHub anything without a
 * token — and a token shipped inside an APK is a token anybody can read out of
 * it. The daemon already holds credentials for other services and is already
 * the one thing every phone talks to, so it does the asking: it polls the
 * releases API, caches the APK, and serves both without authentication, on the
 * same footing as the rest of the library.
 *
 * That also means an update reaches a phone over the tailnet exactly like the
 * music does. Nothing new has to be reachable, and nothing new has to be
 * trusted.
 */

export interface UpdateInfo {
  /** CI run number, which is what the app carries as BUILD_NUMBER. */
  build: number;
  /** Release title, for showing a human something. */
  name: string;
  /** First line of the release notes — the commit subject. */
  notes: string;
  /** Bytes, so a phone on mobile data can be told what it is agreeing to. */
  size: number;
  /** When this release was published, ISO8601. */
  publishedAt: string | null;
}

/** Parsed from a `build-<n>` tag. Null for anything else, so hand-made tags are ignored rather than crashing the poll. */
export function buildNumberFromTag(tag: string): number | null {
  const m = /^build-(\d+)$/.exec(tag.trim());
  if (!m) return null;
  const n = Number(m[1]);
  return Number.isSafeInteger(n) && n > 0 ? n : null;
}

/**
 * Picks the newest usable release from the API payload.
 *
 * "Newest" is by build number, not by publish date or list order: a re-run of
 * an older commit publishes later but is not a newer app. Releases without a
 * `build-<n>` tag, without an APK asset, or marked draft are skipped — each of
 * those would otherwise become an update the phone cannot install.
 */
export function newestRelease(
  releases: unknown,
): { info: UpdateInfo; assetUrl: string } | null {
  if (!Array.isArray(releases)) return null;
  let best: { info: UpdateInfo; assetUrl: string } | null = null;
  for (const raw of releases) {
    const r = raw as Record<string, unknown>;
    if (r["draft"] === true) continue;
    const tag = typeof r["tag_name"] === "string" ? r["tag_name"] : "";
    const build = buildNumberFromTag(tag);
    if (build === null) continue;
    const assets = Array.isArray(r["assets"]) ? r["assets"] : [];
    const apk = assets.find((a) => {
      const asset = a as Record<string, unknown>;
      return typeof asset["name"] === "string" && asset["name"].endsWith(".apk");
    }) as Record<string, unknown> | undefined;
    if (!apk) continue;
    const url = typeof apk["url"] === "string" ? apk["url"] : null;
    if (!url) continue;
    if (best && build <= best.info.build) continue;
    best = {
      info: {
        build,
        name: typeof r["name"] === "string" && r["name"] ? r["name"] : tag,
        notes:
          typeof r["body"] === "string" ? r["body"].split("\n")[0]!.trim() : "",
        size: typeof apk["size"] === "number" ? apk["size"] : 0,
        publishedAt:
          typeof r["published_at"] === "string" ? r["published_at"] : null,
      },
      assetUrl: url,
    };
  }
  return best;
}

export class UpdateFeed {
  private current: UpdateInfo | null = null;
  private apkPath: string | null = null;
  private polling = false;

  constructor(
    private readonly repo: string,
    private readonly token: string | null,
    private readonly cacheDir: string,
    private readonly log: Log,
    private readonly fetcher: typeof fetch = fetch,
  ) {}

  /** What to tell a phone, or null when there is nothing cached yet. */
  latest(): UpdateInfo | null {
    return this.current;
  }

  /** The cached APK, or null when it has not been downloaded. */
  apk(): string | null {
    return this.apkPath;
  }

  /**
   * Asks GitHub what the newest release is and downloads it if it is new.
   *
   * Silent on failure by design: the daemon's job is serving music, and a
   * GitHub outage or an expired token must not take that with it. A failed
   * poll leaves the previous answer in place, so phones keep seeing the last
   * update that really existed rather than being told there is none.
   */
  async poll(): Promise<void> {
    if (!this.token) return;
    if (this.polling) return;
    this.polling = true;
    try {
      const res = await this.fetcher(
        `https://api.github.com/repos/${this.repo}/releases?per_page=10`,
        {
          headers: {
            Authorization: `Bearer ${this.token}`,
            Accept: "application/vnd.github+json",
            "User-Agent": "tunesd",
          },
        },
      );
      if (!res.ok) {
        this.log.warn({ event: "UPDATE_POLL_HTTP", status: res.status });
        return;
      }
      const found = newestRelease(await res.json());
      if (!found) return;
      if (this.current && found.info.build <= this.current.build) return;

      const path = join(this.cacheDir, `tunes-${found.info.build}.apk`);
      await this.download(found.assetUrl, path);
      const previous = this.apkPath;
      this.current = found.info;
      this.apkPath = path;
      this.log.info({ event: "UPDATE_READY", build: found.info.build });
      // Only after the new one is in place, so a failed download never leaves
      // the daemon advertising an update it cannot serve.
      if (previous && previous !== path) {
        await unlink(previous).catch(() => {});
      }
    } catch (e) {
      this.log.warn({ event: "UPDATE_POLL_FAILED", error: String(e) });
    } finally {
      this.polling = false;
    }
  }

  /** Downloads to a temporary name and renames, so a partial file is never served. */
  private async download(assetUrl: string, path: string): Promise<void> {
    await mkdir(this.cacheDir, { recursive: true });
    const res = await this.fetcher(assetUrl, {
      headers: {
        Authorization: `Bearer ${this.token}`,
        // The asset endpoint returns metadata as JSON unless the bytes are
        // asked for explicitly. Without this the daemon caches a JSON blob and
        // serves it as an APK, which installs as nothing at all.
        Accept: "application/octet-stream",
        "User-Agent": "tunesd",
      },
    });
    if (!res.ok || !res.body) {
      throw new Error(`asset download failed: ${res.status}`);
    }
    const tmp = `${path}.part`;
    await pipeline(
      Readable.fromWeb(res.body as Parameters<typeof Readable.fromWeb>[0]),
      createWriteStream(tmp),
    );
    const size = (await stat(tmp)).size;
    if (size === 0) {
      await unlink(tmp).catch(() => {});
      throw new Error("asset download was empty");
    }
    await rename(tmp, path);
  }
}
