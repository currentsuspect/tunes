import type { DiscographyGroup } from "./discography.js";

export interface EntMember {
  id: string;
  position: number | null;
  disc: number | null;
}

export interface EnrichmentEntry {
  sha: string;
  artist: string | null;
  album: string | null;
  year: string | null;
  artSha: string | null;
  releaseId: string | null;
  releaseType: string | null;
  trackNumber: number | null;
  discNumber: number | null;
  totalTracks: number | null;
  membership: EntMember[];
  source: "musicbrainz" | "spotify" | "discogs" | null;
  enrichedAt: string;
}

/**
 * A record of the enrichment pass having tried a track and failed to resolve it.
 * Absent means "never tried"; present means "tried, still unresolved" — the two
 * states the pass gate could not previously tell apart.
 */
export interface EnrichAttempt {
  attempts: number;
  lastAttemptAt: string;
}

export const ENRICH_RETRY_BASE_MS = 30 * 60 * 1000;
export const ENRICH_RETRY_MAX_MS = 7 * 24 * 60 * 60 * 1000;

/** Exponential backoff: 30m, 1h, 2h, 4h … capped at a week. */
export function enrichBackoffMs(attempts: number): number {
  if (attempts <= 0) return 0;
  const steps = Math.min(attempts - 1, 20);
  return Math.min(ENRICH_RETRY_BASE_MS * 2 ** steps, ENRICH_RETRY_MAX_MS);
}

/** Whether an unresolved track is due for another cascade run. */
export function enrichRetryDue(attempt: EnrichAttempt | undefined, now: number): boolean {
  if (!attempt) return true;
  const last = Date.parse(attempt.lastAttemptAt);
  if (!Number.isFinite(last)) return true;
  return now - last >= enrichBackoffMs(attempt.attempts);
}

export interface ParsedName {
  artist: string;
  title: string;
}

/**
 * Splits a multi-artist tag into its individual names. Vorbis comments join
 * collaborators with ";" or "/", so "Yeat;Don Toliver" is two artists, not one
 * artist nobody can look up. Commas are left alone — they appear inside real
 * names far too often to treat as a separator.
 */
/** Spotify could not be consulted — distinct from "Spotify had no match". */
export class SpotifyUnavailable extends Error {
  constructor(message: string) {
    super(message);
    this.name = "SpotifyUnavailable";
  }
}

export function splitArtistNames(raw: string | null | undefined): string[] {
  if (raw == null) return [];
  const names: string[] = [];
  for (const part of raw.split(/[;/]/)) {
    const name = part.trim();
    if (name !== "" && !names.includes(name)) names.push(name);
  }
  return names;
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

export interface ReleaseTrackRow {
  title: string;
  lengthMs: number | null;
  position: number;
  discNumber: number;
  artist: string | null;
}

export function flattenReleaseTracks(
  media: Array<{
    position?: number;
    tracks?: Array<{
      title?: string;
      length?: number;
      position?: number;
      recording?: { "artist-credit"?: Array<{ name?: string }> };
    }>;
  }>
): ReleaseTrackRow[] {
  const raw: Array<{
    disc: number;
    pos: number;
    title: string;
    lengthMs: number | null;
    artist: string | null;
  }> = [];
  let lastMax = 0;
  let monotonic = true;
  for (const m of media) {
    const disc = m.position ?? 1;
    for (const t of m.tracks ?? []) {
      const p = t.position ?? 0;
      if (p <= lastMax) monotonic = false;
      if (p > lastMax) lastMax = p;
      raw.push({
        disc,
        pos: p,
        title: t.title ?? "",
        lengthMs: t.length != null ? Number(t.length) : null,
        artist: t.recording?.["artist-credit"]?.[0]?.name ?? null,
      });
    }
  }
  return raw.map((t, i) => ({
    discNumber: t.disc,
    title: t.title,
    lengthMs: t.lengthMs,
    artist: t.artist,
    position: monotonic ? t.pos : i + 1,
  }));
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
        signal: AbortSignal.timeout(20_000),
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
      const res = await this.fetcher(url, {
        headers: { "User-Agent": this.userAgent },
        signal: AbortSignal.timeout(20_000),
      });
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

  async searchArtists(
    q: string,
    limit = 6
  ): Promise<Array<{
    name: string;
    mbid: string;
    type: string | null;
    disambiguation: string | null;
    score: number | null;
  }>> {
    const query = `artist:"${q.replace(/"/g, "")}"`;
    const url = `https://musicbrainz.org/ws/2/artist?query=${encodeURIComponent(query)}&fmt=json&limit=${limit}`;
    let body = await this.getJson<{
      artists?: Array<{
        id?: string;
        name?: string;
        type?: string | null;
        disambiguation?: string | null;
        score?: number | null;
      }>;
    }>(url);
    if (!body) {
      await new Promise((r) => setTimeout(r, 3_000));
      body = await this.getJson<{
        artists?: Array<{
          id?: string;
          name?: string;
          type?: string | null;
          disambiguation?: string | null;
          score?: number | null;
        }>;
      }>(url);
    }
    return (body?.artists ?? [])
      .filter((a) => a.id && a.name)
      .map((a) => ({
        name: a.name ?? "",
        mbid: a.id ?? "",
        type: a.type ?? null,
        disambiguation: a.disambiguation ?? null,
        score: a.score ?? null,
      }));
  }

  async searchReleaseGroups(
    q: string,
    limit = 6
  ): Promise<DiscographyGroup[]> {
    const terms = q
      .replace(/"/g, "")
      .split(/\s+/)
      .filter((t) => t !== "");
    if (terms.length === 0) return [];
    const query = terms.map((t) => `releasegroup:${t}`).join(" AND ");
    const url = `https://musicbrainz.org/ws/2/release-group?query=${encodeURIComponent(query)}&fmt=json&limit=${limit}`;
    let body = await this.getJson<{
      "release-groups"?: Array<{
        id?: string;
        title?: string;
        "primary-type"?: string | null;
        "first-release-date"?: string | null;
        "artist-credit"?: Array<{ name?: string }>;
      }>;
    }>(url);
    if (!body) {
      await new Promise((r) => setTimeout(r, 3_000));
      body = await this.getJson<{
        "release-groups"?: Array<{
          id?: string;
          title?: string;
          "primary-type"?: string | null;
          "first-release-date"?: string | null;
          "artist-credit"?: Array<{ name?: string }>;
        }>;
      }>(url);
    }
    return (body?.["release-groups"] ?? [])
      .filter((g) => g.id && g.title)
      .map((g) => ({
        id: g.id ?? "",
        title: g.title ?? "",
        type: g["primary-type"] ?? null,
        year: g["first-release-date"] ? g["first-release-date"].slice(0, 4) : null,
        date: g["first-release-date"] ?? null,
        artist: g["artist-credit"]?.[0]?.name ?? null,
      }));
  }

  async artistDiscography(
    name: string
  ): Promise<{ mbid: string; groups: DiscographyGroup[] } | null> {
    const q = `artist:"${name.replace(/"/g, "")}"`;
    let search = await this.getJson<{
      artists?: Array<{ id: string; name?: string }>;
    }>(
      `https://musicbrainz.org/ws/2/artist?query=${encodeURIComponent(q)}&fmt=json&limit=1`
    );
    if (!search) {
      await new Promise((r) => setTimeout(r, 3_000));
      search = await this.getJson<{
        artists?: Array<{ id: string; name?: string }>;
      }>(
        `https://musicbrainz.org/ws/2/artist?query=${encodeURIComponent(q)}&fmt=json&limit=1`
      );
    }
    const mbid = search?.artists?.[0]?.id;
    if (!mbid) return null;
    const url = `https://musicbrainz.org/ws/2/artist/${mbid}?inc=release-groups&fmt=json`;
    let body = await this.getJson<{
      "release-groups"?: Array<{
        id?: string;
        title?: string;
        "primary-type"?: string | null;
        "first-release-date"?: string | null;
      }>;
    }>(url);
    if (!body) {
      await new Promise((r) => setTimeout(r, 3_000));
      body = await this.getJson<{
        "release-groups"?: Array<{
          id?: string;
          title?: string;
          "primary-type"?: string | null;
          "first-release-date"?: string | null;
        }>;
      }>(url);
    }
    const groups = (body?.["release-groups"] ?? [])
      .map((g) => ({
        id: g.id ?? "",
        title: g.title ?? "",
        type: g["primary-type"] ?? null,
        year: g["first-release-date"] ? g["first-release-date"].slice(0, 4) : null,
        date: g["first-release-date"] ?? null,
      }))
      .filter((g) => g.id !== "" && g.title !== "");
    return { mbid, groups };
  }

  async fetchCover(releaseId: string): Promise<{ sha: string; bytes: Uint8Array } | null> {
    const bytes = await this.getBytes(
      `https://coverartarchive.org/release/${releaseId}/front-500`
    );
    if (!bytes) return null;
    return storeCoverBytes(this.cacheDir, bytes);
  }

  async releaseWithRecordings(
    releaseMbid: string
  ): Promise<{
    title: string;
    type: string | null;
    groupId: string | null;
    date: string | null;
    tracks: Array<{
      title: string;
      lengthMs: number | null;
      position: number;
      discNumber: number;
      artist: string | null;
    }>;
  } | null> {
    const url =
      `https://musicbrainz.org/ws/2/release/${releaseMbid}?inc=recordings+release-groups&fmt=json`;
    const body = await this.getJson<{
      title?: string;
      "release-group"?: {
        id?: string;
        "primary-type"?: string | null;
        "first-release-date"?: string | null;
      };
      media?: Array<{
        position?: number;
        tracks?: Array<{
          title?: string;
          length?: number;
          position?: number;
          recording?: { "artist-credit"?: Array<{ name?: string }> };
        }>;
      }>;
    }>(url);
    if (!body?.title) return null;
    const tracks = flattenReleaseTracks(body.media ?? []);
    return {
      title: body.title,
      type: body["release-group"]?.["primary-type"] ?? null,
      groupId: body["release-group"]?.id ?? null,
      date: body["release-group"]?.["first-release-date"] ?? null,
      tracks,
    };
  }
}

export async function storeCoverBytes(
  cacheDir: string,
  bytes: Uint8Array
): Promise<{ sha: string; bytes: Uint8Array }> {
  const { createHash } = await import("node:crypto");
  const sha = createHash("sha256").update(bytes).digest("hex");
  const { mkdir, writeFile } = await import("node:fs/promises");
  const { join } = await import("node:path");
  await mkdir(join(cacheDir, "covers", sha.slice(0, 2)), { recursive: true });
  await writeFile(join(cacheDir, "covers", sha.slice(0, 2), sha), bytes);
  return { sha, bytes };
}

export interface SpotifyLookup {
  artist: string;
  artistId: string | null;
  album: string | null;
  albumId: string | null;
  albumType: string | null;
  year: string | null;
  artUrl: string | null;
  trackNumber: number | null;
}

function norm(s: string): string {
  return s.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
}

export interface DiscogsLookup {
  artist: string;
  album: string | null;
  albumId: string | null;
  year: string | null;
  artUrl: string | null;
}

export class DiscogsClient {
  constructor(
    private readonly token: string,
    private readonly userAgent: string,
    private readonly fetcher: typeof fetch = fetch
  ) {}

  async search(parsed: ParsedName): Promise<DiscogsLookup | null> {
    const url =
      `https://api.discogs.com/database/search?` +
      `q=${encodeURIComponent(`${parsed.artist} ${parsed.title}`)}` +
      `&artist=${encodeURIComponent(parsed.artist)}` +
      `&track=${encodeURIComponent(parsed.title)}` +
      `&type=release&per_page=10`;
    try {
      const res = await this.fetcher(url, {
        headers: { "User-Agent": this.userAgent, Authorization: `Discogs token=${this.token}` },
      });
      if (!res.ok) return null;
      const body = (await res.json()) as {
        results?: Array<{
          id?: number;
          title?: string;
          year?: number | string;
          cover_image?: string;
          thumb?: string;
        }>;
      };
      const wantArtist = norm(parsed.artist);
      const wantTitle = norm(parsed.title);
      for (const r of body.results ?? []) {
        const title = r.title ?? "";
        const dash = title.indexOf(" - ");
        if (dash <= 0) continue;
        const artist = title.slice(0, dash).trim();
        const trackRaw = title.slice(dash + 3).trim();
        const track = trackRaw.split(" (")[0] ?? trackRaw;
        if (norm(artist) === wantArtist && norm(track) === wantTitle) {
          return {
            artist,
            album: track,
            albumId: r.id != null ? `discogs:${r.id}` : null,
            year: r.year != null ? String(r.year) : null,
            artUrl: r.cover_image && !r.cover_image.includes("spacer") ? r.cover_image : r.thumb ?? null,
          };
        }
      }
      return null;
    } catch {
      return null;
    }
  }
}

export class SpotifyClient {
  private token: string | null = null;
  private tokenExpiresAt = 0;

  constructor(
    private readonly clientId: string,
    private readonly clientSecret: string,
    private readonly fetcher: typeof fetch = fetch
  ) {}

  private async tokenFor(): Promise<string | null> {
    if (this.token && Date.now() < this.tokenExpiresAt) return this.token;
    try {
      const res = await this.fetcher("https://accounts.spotify.com/api/token", {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          Authorization: `Basic ${Buffer.from(`${this.clientId}:${this.clientSecret}`).toString("base64")}`,
        },
        body: "grant_type=client_credentials",
      });
      if (!res.ok) return null;
      const body = (await res.json()) as { access_token?: string; expires_in?: number };
      if (!body.access_token) return null;
      this.token = body.access_token;
      this.tokenExpiresAt = Date.now() + (body.expires_in ?? 3600) * 1000 - 60_000;
      return this.token;
    } catch {
      return null;
    }
  }

  async artistImage(artistId: string): Promise<string | null> {
    const token = await this.tokenFor();
    if (!token) return null;
    try {
      const res = await this.fetcher(
        `https://api.spotify.com/v1/artists/${artistId}`,
        { headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(15_000) }
      );
      if (!res.ok) return null;
      const body = (await res.json()) as { images?: Array<{ url?: string }> };
      return body.images?.find((i) => i.url)?.url ?? null;
    } catch {
      return null;
    }
  }

  async searchArtistId(name: string): Promise<string | null> {
    const token = await this.tokenFor();
    if (!token) throw new SpotifyUnavailable("no access token");
    let res: Response;
    try {
      const q = `artist:${name}`;
      const url = `https://api.spotify.com/v1/search?q=${encodeURIComponent(q)}&type=artist&limit=1`;
      res = await this.fetcher(url, {
        headers: { Authorization: `Bearer ${token}` },
        signal: AbortSignal.timeout(15_000),
      });
    } catch (e) {
      throw new SpotifyUnavailable(`search request failed: ${String(e)}`);
    }
    if (!res.ok) throw new SpotifyUnavailable(`search returned HTTP ${res.status}`);
    try {
      const body = (await res.json()) as {
        artists?: { items?: Array<{ id?: string; name?: string }> };
      };
      const hit = body.artists?.items?.[0];
      if (!hit?.id) return null;
      if (norm(hit.name ?? "") !== norm(name)) return null;
      return hit.id;
    } catch (e) {
      throw new SpotifyUnavailable(`search body unreadable: ${String(e)}`);
    }
  }

  async artistIdFromTrack(name: string): Promise<string | null> {
    const token = await this.tokenFor();
    if (!token) throw new SpotifyUnavailable("no access token");
    let res: Response;
    try {
      const q = `artist:${name}`;
      const url = `https://api.spotify.com/v1/search?q=${encodeURIComponent(q)}&type=track&limit=1`;
      res = await this.fetcher(url, {
        headers: { Authorization: `Bearer ${token}` },
        signal: AbortSignal.timeout(15_000),
      });
    } catch (e) {
      throw new SpotifyUnavailable(`track search request failed: ${String(e)}`);
    }
    if (!res.ok) throw new SpotifyUnavailable(`track search returned HTTP ${res.status}`);
    try {
      const body = (await res.json()) as {
        tracks?: { items?: Array<{ artists?: Array<{ id?: string; name?: string }> }> };
      };
      const hit = body.tracks?.items?.[0]?.artists?.[0];
      if (!hit?.id) return null;
      if (norm(hit.name ?? "") !== norm(name)) return null;
      return hit.id;
    } catch (e) {
      throw new SpotifyUnavailable(`track search body unreadable: ${String(e)}`);
    }
  }

  async search(parsed: ParsedName): Promise<SpotifyLookup | null> {
    const token = await this.tokenFor();
    if (!token) return null;
    const q = `artist:${parsed.artist} track:${parsed.title}`;
    const url = `https://api.spotify.com/v1/search?q=${encodeURIComponent(q)}&type=track&limit=10`;
    try {
      const res = await this.fetcher(url, { headers: { Authorization: `Bearer ${token}` } });
      if (!res.ok) return null;
      const body = (await res.json()) as {
        tracks?: {
          items?: Array<{
            id?: string;
            name?: string;
            track_number?: number;
            artists?: Array<{ id?: string; name?: string }>;
            album?: {
              id?: string;
              album_type?: string;
              name?: string;
              release_date?: string;
              images?: Array<{ url?: string }>;
            };
          }>;
        };
      };
      const items = body.tracks?.items ?? [];
      const wantArtist = norm(parsed.artist);
      const wantTitle = norm(parsed.title);
      for (const item of items) {
        const artist = item.artists?.[0]?.name ?? "";
        const title = item.name ?? "";
        if (norm(artist) === wantArtist && norm(title) === wantTitle) {
          const art = item.album?.images?.find((i) => i.url)?.url ?? null;
          return {
            artist,
            artistId: item.artists?.[0]?.id ?? null,
            album: item.album?.name ?? null,
            albumId: item.album?.id ?? null,
            albumType: item.album?.album_type ?? null,
            year: item.album?.release_date ? item.album.release_date.slice(0, 4) : null,
            artUrl: art,
            trackNumber: item.track_number ?? null,
          };
        }
      }
      return null;
    } catch {
      return null;
    }
  }
}