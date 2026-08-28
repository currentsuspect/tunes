export interface EnrichmentEntry {
  sha: string;
  artist: string | null;
  album: string | null;
  year: string | null;
  artSha: string | null;
  enrichedAt: string;
}

export interface ParsedName {
  artist: string;
  title: string;
}

export function parseArtistTitle(fileName: string): ParsedName | null {
  const name = fileName.trim().replace(/\.[^.]+$/, "").replace(/\s+/g, " ").trim();
  if (name === "") return null;
  const dash = name.indexOf(" - ");
  if (dash <= 0 || dash >= name.length - 3) return null;
  const artist = name.slice(0, dash).trim();
  const title = name.slice(dash + 3).trim();
  if (artist === "" || title === "") return null;
  return { artist, title };
}

interface RecordingSearchHit {
  id: string;
  title: string;
  artist: string;
  releases: Array<{
    releaseId: string;
    title: string;
    year: string | null;
    primaryType: string | null;
    hasFrontArt: boolean;
  }>;
  album: {
    releaseId: string;
    title: string;
    year: string | null;
    primaryType: string | null;
    hasFrontArt: boolean;
  } | null;
}

interface MusicBrainzRecording {
  id: string;
  title: string;
  score?: number;
  "artist-credit"?: Array<{ name?: string }>;
  releases?: Array<{
    id: string;
    title: string;
    "primary-type"?: string | null;
    date?: string;
    "cover-art-archive"?: { front?: boolean; art_count?: number };
  }>;
}

export class MusicBrainzClient {
  private lastRequestAt = 0;

  constructor(
    private readonly userAgent: string,
    private readonly cacheDir: string,
    private readonly fetcher: typeof fetch = fetch
  ) {}

  private async rateLimit(): Promise<void> {
    const elapsed = Date.now() - this.lastRequestAt;
    const wait = Math.max(0, 1000 - elapsed);
    if (wait > 0) await new Promise((r) => setTimeout(r, wait));
    this.lastRequestAt = Date.now();
  }

  private async getJson<T>(url: string): Promise<T | null> {
    await this.rateLimit();
    try {
      const res = await this.fetcher(url, {
        headers: { "User-Agent": this.userAgent, Accept: "application/json" },
      });
      if (!res.ok) return null;
      return (await res.json()) as T;
    } catch {
      return null;
    }
  }

  private async getBytes(url: string): Promise<Uint8Array | null> {
    await this.rateLimit();
    try {
      const res = await this.fetcher(url, { headers: { "User-Agent": this.userAgent } });
      if (!res.ok) return null;
      return new Uint8Array(await res.arrayBuffer());
    } catch {
      return null;
    }
  }

  async searchRecording(parsed: ParsedName): Promise<RecordingSearchHit | null> {
    const stripped = parsed.title.replace(/\s*\(.*?\)\s*/g, " ").trim();
    const variants = [stripped, parsed.title].filter(
      (t, i, a) => t !== "" && a.indexOf(t) === i
    );
    for (const title of variants) {
      const query = `recording:"${title}" AND artist:"${parsed.artist}"`;
      const url = `https://musicbrainz.org/ws/2/recording?query=${encodeURIComponent(query)}&fmt=json&limit=5`;
      const body = await this.getJson<{ recordings?: MusicBrainzRecording[] }>(url);
      if (body?.recordings?.length) {
        const hit = body.recordings[0];
        if (!hit) continue;
        const artist = hit["artist-credit"]?.[0]?.name ?? null;
        const releases = (hit.releases ?? []).map((r) => ({
          releaseId: r.id,
          title: r.title ?? "",
          year: r.date ? r.date.slice(0, 4) : null,
          primaryType: r["primary-type"] ?? null,
          hasFrontArt: Boolean(r["cover-art-archive"]?.front),
        }));

        const candidate =
          releases.find((r) => r.primaryType === "Album") ??
          releases.find((r) => r.hasFrontArt) ??
          releases[0] ??
          null;

        return {
          id: hit.id,
          title: hit.title ?? parsed.title,
          artist: artist ?? parsed.artist,
          releases,
          album: candidate,
        };
      }
    }
    return null;
  }

  async fetchCover(releaseId: string): Promise<{ sha: string; bytes: Uint8Array } | null> {
    const bytes = await this.getBytes(
      `https://coverartarchive.org/release/${releaseId}/front-500`
    );
    if (!bytes) return null;
    const { createHash } = await import("node:crypto");
    const sha = createHash("sha256").update(bytes).digest("hex");
    const { mkdir, writeFile } = await import("node:fs/promises");
    const { join } = await import("node:path");
    await mkdir(join(this.cacheDir, "covers", sha.slice(0, 2)), { recursive: true });
    await writeFile(join(this.cacheDir, "covers", sha.slice(0, 2), sha), bytes);
    return { sha, bytes };
  }
}