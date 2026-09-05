/**
 * Last.fm enrichment provider.
 *
 * Added because Spotify's search endpoint answers 403 to this app's
 * client-credentials token, leaving the artist tier dead. Last.fm needs only a
 * static API key, no OAuth dance and no per-request token.
 *
 * Inert without TUNESD_LASTFM_KEY — the client is simply not constructed.
 */

/**
 * Last.fm could not be consulted, as opposed to Last.fm having no match.
 * Callers must never record the former as the latter: a negative cache built
 * over an ambiguous null turns a transient outage into durable wrong data.
 */
export class LastfmUnavailable extends Error {
  constructor(message: string) {
    super(message);
    this.name = "LastfmUnavailable";
  }
}

/**
 * Since 2019 Last.fm returns the same grey star for every artist image. Storing
 * it would put an identical placeholder on every artist in the library, which
 * looks worse than no image at all.
 */
export const LASTFM_PLACEHOLDER_IMAGE = "2a96cbd8b46e442fc41c2b86b821562f";

export function isPlaceholderImage(url: string | null | undefined): boolean {
  return url != null && url.includes(LASTFM_PLACEHOLDER_IMAGE);
}

interface LastfmImage {
  "#text"?: string;
  size?: string;
}

/** Largest usable image, skipping Last.fm's placeholder. */
export function pickImage(images: LastfmImage[] | undefined): string | null {
  if (!Array.isArray(images)) return null;
  const order = ["mega", "extralarge", "large", "medium", "small"];
  for (const size of order) {
    const hit = images.find((i) => i.size === size)?.["#text"];
    if (hit != null && hit !== "" && !isPlaceholderImage(hit)) return hit;
  }
  const any = images.map((i) => i["#text"]).find((u) => u != null && u !== "" && !isPlaceholderImage(u));
  return any ?? null;
}

export interface LastfmArtist {
  name: string;
  mbid: string | null;
  tags: string[];
  listeners: number | null;
  summary: string | null;
  similar: string[];
  imageUrl: string | null;
}

export interface LastfmAlbum {
  title: string;
  artist: string;
  mbid: string | null;
  tags: string[];
  imageUrl: string | null;
}

export interface LastfmTrack {
  title: string;
  artist: string;
  album: string | null;
  albumArtist: string | null;
  mbid: string | null;
  tags: string[];
  listeners: number | null;
  imageUrl: string | null;
}

function toStringArray(value: unknown): string[] {
  if (value == null) return [];
  const raw = Array.isArray(value) ? value : [value];
  const out: string[] = [];
  for (const item of raw) {
    const name = (item as { name?: unknown })?.name;
    if (typeof name === "string" && name.trim() !== "") out.push(name.trim());
  }
  return out;
}

function toCount(value: unknown): number | null {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

export class LastfmClient {
  private lastRequestAt = 0;

  constructor(
    private readonly apiKey: string,
    private readonly userAgent: string,
    private readonly fetcher: typeof fetch = fetch
  ) {}

  /** Last.fm asks for no more than ~5 requests/second from one IP. */
  private async rateLimit(): Promise<void> {
    const elapsed = Date.now() - this.lastRequestAt;
    const wait = Math.max(0, 250 - elapsed);
    if (wait > 0) await new Promise((r) => setTimeout(r, wait));
    this.lastRequestAt = Date.now();
  }

  private async call<T>(method: string, params: Record<string, string>): Promise<T | null> {
    await this.rateLimit();
    const query = new URLSearchParams({
      method,
      api_key: this.apiKey,
      format: "json",
      autocorrect: "1",
      ...params,
    });
    const url = `https://ws.audioscrobbler.com/2.0/?${query.toString()}`;
    let res: Response;
    try {
      res = await this.fetcher(url, {
        headers: { "User-Agent": this.userAgent, Accept: "application/json" },
        signal: AbortSignal.timeout(20_000),
      });
    } catch (e) {
      throw new LastfmUnavailable(`${method} request failed: ${String(e)}`);
    }
    if (!res.ok) throw new LastfmUnavailable(`${method} returned HTTP ${res.status}`);
    let body: unknown;
    try {
      body = await res.json();
    } catch (e) {
      throw new LastfmUnavailable(`${method} body unreadable: ${String(e)}`);
    }
    const err = (body as { error?: number; message?: string }).error;
    if (err != null) {
      // 6 is "not found" — a real answer. Everything else (rate limit, bad key,
      // service offline) means we could not look.
      if (err === 6) return null;
      throw new LastfmUnavailable(
        `${method} error ${err}: ${(body as { message?: string }).message ?? "unknown"}`
      );
    }
    return body as T;
  }

  async artistInfo(name: string): Promise<LastfmArtist | null> {
    const body = await this.call<{
      artist?: {
        name?: string;
        mbid?: string;
        stats?: { listeners?: string };
        bio?: { summary?: string };
        tags?: { tag?: unknown };
        similar?: { artist?: unknown };
        image?: LastfmImage[];
      };
    }>("artist.getinfo", { artist: name });
    const a = body?.artist;
    if (a?.name == null || a.name.trim() === "") return null;
    return {
      name: a.name.trim(),
      mbid: a.mbid != null && a.mbid !== "" ? a.mbid : null,
      tags: toStringArray(a.tags?.tag),
      listeners: toCount(a.stats?.listeners),
      summary: a.bio?.summary?.trim() || null,
      similar: toStringArray(a.similar?.artist),
      imageUrl: pickImage(a.image),
    };
  }

  async albumInfo(artist: string, album: string): Promise<LastfmAlbum | null> {
    const body = await this.call<{
      album?: {
        name?: string;
        artist?: string;
        mbid?: string;
        tags?: { tag?: unknown };
        image?: LastfmImage[];
      };
    }>("album.getinfo", { artist, album });
    const al = body?.album;
    if (al?.name == null || al.name.trim() === "") return null;
    return {
      title: al.name.trim(),
      artist: (al.artist ?? artist).trim(),
      mbid: al.mbid != null && al.mbid !== "" ? al.mbid : null,
      tags: toStringArray(al.tags?.tag),
      imageUrl: pickImage(al.image),
    };
  }

  async trackInfo(artist: string, title: string): Promise<LastfmTrack | null> {
    const body = await this.call<{
      track?: {
        name?: string;
        mbid?: string;
        listeners?: string;
        artist?: { name?: string };
        album?: { title?: string; artist?: string; image?: LastfmImage[] };
        toptags?: { tag?: unknown };
      };
    }>("track.getinfo", { artist, track: title });
    const t = body?.track;
    if (t?.name == null || t.name.trim() === "") return null;
    return {
      title: t.name.trim(),
      artist: t.artist?.name?.trim() ?? artist,
      album: t.album?.title?.trim() || null,
      albumArtist: t.album?.artist?.trim() || null,
      mbid: t.mbid != null && t.mbid !== "" ? t.mbid : null,
      tags: toStringArray(t.toptags?.tag),
      listeners: toCount(t.listeners),
      imageUrl: pickImage(t.album?.image),
    };
  }
}
