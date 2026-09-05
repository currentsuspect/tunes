/**
 * Deezer artist lookup — artist pictures only.
 *
 * Spotify's search endpoint 403s this app, and Last.fm has served one grey star
 * for every artist since 2019 (verified against 40 artists from this library:
 * every single one was the placeholder). Deezer's public API needs no key, no
 * account and no auth, and returned a real picture for all 12 artists tried.
 *
 * tunesd-side only. The app's single network endpoint is still the
 * user-configured tunesd (SPEC §1.5, §2.4) — that boundary is untouched.
 */

/** Deezer could not be consulted, as opposed to Deezer having no match. */
export class DeezerUnavailable extends Error {
  constructor(message: string) {
    super(message);
    this.name = "DeezerUnavailable";
  }
}

export interface DeezerArtist {
  id: number;
  name: string;
  pictureUrl: string | null;
  fans: number | null;
}

interface DeezerArtistRow {
  id?: number;
  name?: string;
  picture_xl?: string;
  picture_big?: string;
  picture_medium?: string;
  nb_fan?: number;
}

/**
 * Deezer serves a generic silhouette from a path ending in the empty artist
 * slug when it has no real picture. Those are worth no more than Last.fm's
 * grey star, so they are treated as "no image".
 */
export function isGenericPicture(url: string | null | undefined): boolean {
  if (url == null || url.trim() === "") return true;
  return url.includes("/artist//") || /\/artist\/?$/.test(url);
}

export function pickPicture(row: DeezerArtistRow): string | null {
  for (const url of [row.picture_xl, row.picture_big, row.picture_medium]) {
    if (url != null && url !== "" && !isGenericPicture(url)) return url;
  }
  return null;
}

export class DeezerClient {
  private lastRequestAt = 0;

  constructor(
    private readonly userAgent: string,
    private readonly fetcher: typeof fetch = fetch
  ) {}

  /** Deezer's public quota is generous; stay well inside it anyway. */
  private async rateLimit(): Promise<void> {
    const elapsed = Date.now() - this.lastRequestAt;
    const wait = Math.max(0, 250 - elapsed);
    if (wait > 0) await new Promise((r) => setTimeout(r, wait));
    this.lastRequestAt = Date.now();
  }

  /**
   * Best candidate for a name. The caller is responsible for deciding whether
   * the returned name is actually the artist it asked for — Deezer will
   * happily answer "Le N'" for "Len" and "HVN & ERTH" for "HVN".
   */
  async searchArtist(name: string): Promise<DeezerArtist | null> {
    await this.rateLimit();
    const url = `https://api.deezer.com/search/artist?q=${encodeURIComponent(name)}&limit=5`;
    let res: Response;
    try {
      res = await this.fetcher(url, {
        headers: { "User-Agent": this.userAgent, Accept: "application/json" },
        signal: AbortSignal.timeout(20_000),
      });
    } catch (e) {
      throw new DeezerUnavailable(`artist search failed: ${String(e)}`);
    }
    if (!res.ok) throw new DeezerUnavailable(`artist search returned HTTP ${res.status}`);
    let body: { data?: DeezerArtistRow[]; error?: { message?: string; code?: number } };
    try {
      body = (await res.json()) as typeof body;
    } catch (e) {
      throw new DeezerUnavailable(`artist search body unreadable: ${String(e)}`);
    }
    // Deezer reports quota and service errors in the body with HTTP 200.
    if (body.error != null) {
      throw new DeezerUnavailable(
        `artist search error ${body.error.code ?? "?"}: ${body.error.message ?? "unknown"}`
      );
    }
    const rows = Array.isArray(body.data) ? body.data : [];
    for (const row of rows) {
      if (row.id == null || row.name == null || row.name.trim() === "") continue;
      return {
        id: row.id,
        name: row.name.trim(),
        pictureUrl: pickPicture(row),
        fans: typeof row.nb_fan === "number" ? row.nb_fan : null,
      };
    }
    return null;
  }

  /** Every candidate, so a caller can pick the one whose name actually matches. */
  async searchArtistCandidates(name: string): Promise<DeezerArtist[]> {
    await this.rateLimit();
    const url = `https://api.deezer.com/search/artist?q=${encodeURIComponent(name)}&limit=5`;
    let res: Response;
    try {
      res = await this.fetcher(url, {
        headers: { "User-Agent": this.userAgent, Accept: "application/json" },
        signal: AbortSignal.timeout(20_000),
      });
    } catch (e) {
      throw new DeezerUnavailable(`artist search failed: ${String(e)}`);
    }
    if (!res.ok) throw new DeezerUnavailable(`artist search returned HTTP ${res.status}`);
    let body: { data?: DeezerArtistRow[]; error?: { message?: string; code?: number } };
    try {
      body = (await res.json()) as typeof body;
    } catch (e) {
      throw new DeezerUnavailable(`artist search body unreadable: ${String(e)}`);
    }
    if (body.error != null) {
      throw new DeezerUnavailable(
        `artist search error ${body.error.code ?? "?"}: ${body.error.message ?? "unknown"}`
      );
    }
    const out: DeezerArtist[] = [];
    for (const row of Array.isArray(body.data) ? body.data : []) {
      if (row.id == null || row.name == null || row.name.trim() === "") continue;
      out.push({
        id: row.id,
        name: row.name.trim(),
        pictureUrl: pickPicture(row),
        fans: typeof row.nb_fan === "number" ? row.nb_fan : null,
      });
    }
    return out;
  }
}
