import { createServer } from "node:http";
import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import { extname, join } from "node:path";
import type { ObjectStore } from "./store.js";
import type { Log } from "./logger.js";
import type { ManifestV2 } from "./manifest.js";
import type {
  ArtistDiscography,
  DiscographyGroup,
  ExternalArtist,
  JoinedGroup,
} from "./discography.js";
import {
  dedupeExternalArtists,
  dedupeExternalReleases,
  joinDiscography,
  normName,
} from "./discography.js";

const MIME: Record<string, string> = {
  ".mp3": "audio/mpeg",
  ".flac": "audio/flac",
  ".ogg": "audio/ogg",
  ".opus": "audio/ogg",
  ".m4a": "audio/mp4",
  ".wav": "audio/wav",
  ".aac": "audio/aac",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".png": "image/png",
};

export class ManifestServer {
  private lastManifest: ManifestV2 | null = null;
  private lastBuiltAt = 0;

  constructor(
    private readonly store: ObjectStore,
    private readonly artDir: string,
    private readonly buildManifest: () => Promise<ManifestV2>,
    private readonly port: number,
    private readonly log: Log,
    private readonly getDiscographies: () => Map<string, ArtistDiscography> = () =>
      new Map(),
    private readonly searchExternalArtists:
      | ((q: string) => Promise<ExternalArtist[]>)
      | null = null,
    private readonly searchExternalReleases:
      | ((q: string) => Promise<DiscographyGroup[]>)
      | null = null,
    private readonly fetchDiscography:
      | ((name: string) => Promise<ArtistDiscography | null>)
      | null = null
  ) {
    this.externalCache = new Map();
  }

  private readonly externalCache: Map<
    string,
    { at: number; artists: ExternalArtist[]; releases: DiscographyGroup[] }
  >;

  private async getManifest(force = false): Promise<ManifestV2> {
    const now = Date.now();
    if (!force && this.lastManifest && now - this.lastBuiltAt < 30_000) {
      return this.lastManifest;
    }
    const m = await this.buildManifest();
    this.lastManifest = m;
    this.lastBuiltAt = now;
    return m;
  }

  async start(): Promise<void> {
    const server = createServer(async (req, res) => {
      try {
        const url = new URL(req.url ?? "/", `http://${req.headers.host ?? "localhost"}`);
        if (url.pathname === "/manifest") {
          const manifest = await this.getManifest();
          res.writeHead(200, { "content-type": "application/json; charset=utf-8" });
          res.end(JSON.stringify(manifest));
          return;
        }

        const trackMatch = /^\/track\/([0-9a-f]{64})$/.exec(url.pathname);
        if (trackMatch) {
          const sha = trackMatch[1] ?? "";
          await this.serveRange(res, req, this.store.pathOf(sha), null);
          return;
        }

        const artMatch = /^\/art\/([0-9a-f]{64})$/.exec(url.pathname);
        if (artMatch) {
          const sha = artMatch[1] ?? "";
          await this.serveRange(res, req, join(this.artDir, sha.slice(0, 2), sha), "sha");
          return;
        }

        if (url.pathname === "/search") {
          const q = (url.searchParams.get("q") ?? "").trim();
          const limit = Math.min(Math.max(Number(url.searchParams.get("limit") ?? "10") || 10, 1), 20);
          if (q === "") {
            res.writeHead(400, { "content-type": "text/plain" });
            res.end("missing q");
            return;
          }
          const manifest = await this.getManifest();
          const norm = (s: string) => s.toLowerCase().replace(/\s+/g, " ").trim();
          const qn = norm(q);
          const tracks = manifest.tracks
            .filter(
              (t) =>
                norm(t.title).includes(qn) ||
                norm(t.artist).includes(qn) ||
                norm(t.album).includes(qn)
            )
            .slice(0, limit);
          const releases = manifest.releases
            .filter((r) => norm(r.title).includes(qn) || norm(r.artist).includes(qn))
            .slice(0, limit);
          const artists = manifest.artists.filter((a) => norm(a.name).includes(qn)).slice(0, limit);
          let externalArtists: ExternalArtist[] = [];
          let externalReleases: JoinedGroup[] = [];
          const artistSearcher = this.searchExternalArtists;
          const releaseSearcher = this.searchExternalReleases;
          if (artistSearcher && releaseSearcher) {
            let artists: ExternalArtist[] = [];
            let rg: DiscographyGroup[] = [];
            const cached = this.externalCache.get(qn);
            if (cached && Date.now() - cached.at < 30 * 60_000) {
              artists = cached.artists;
              rg = cached.releases;
            } else {
              try {
                [artists, rg] = await Promise.all([
                  artistSearcher(q),
                  releaseSearcher(q),
                ]);
                if (artists.length > 0 || rg.length > 0) {
                  this.externalCache.set(qn, { at: Date.now(), artists, releases: rg });
                }
                if (this.externalCache.size > 64) {
                  const oldest = [...this.externalCache.entries()].sort(
                    (a, b) => a[1].at - b[1].at
                  )[0]?.[0];
                  if (oldest) this.externalCache.delete(oldest);
                }
              } catch {
                // both stay empty; search still answers with local results
              }
            }
            const localNames = [
              ...manifest.artists.map((a) => a.name),
              ...manifest.tracks.map((t) => t.artist),
            ];
            const localTitles = manifest.releases.map((r) => r.title);
            externalArtists = dedupeExternalArtists(artists, localNames);
            externalReleases = joinDiscography(
              dedupeExternalReleases(rg, localTitles),
              manifest.releases
            );
          }
          res.end(
            JSON.stringify({ tracks, releases, artists, externalArtists, externalReleases })
          );
          return;
        }

        if (url.pathname === "/discography") {
          const name = (url.searchParams.get("artist") ?? "").trim();
          if (name === "") {
            res.writeHead(400, { "content-type": "text/plain" });
            res.end("missing artist");
            return;
          }
          const manifest = await this.getManifest();
          let d: ArtistDiscography | undefined = this.getDiscographies().get(
            normName(name)
          );
          if (!d && this.fetchDiscography) {
            try {
              const fresh = await this.fetchDiscography(name);
              if (fresh) d = fresh;
            } catch {
              // on-demand fetch failed — serve empty
            }
          }
          const groups: JoinedGroup[] = d
            ? joinDiscography(d.groups, manifest.releases)
            : [];
          res.writeHead(200, { "content-type": "application/json; charset=utf-8" });
          res.end(
            JSON.stringify({
              artist: d?.name ?? name,
              mbid: d?.mbid ?? null,
              fetchedAt: d?.fetchedAt ?? null,
              groups,
            })
          );
          return;
        }

        res.writeHead(404, { "content-type": "text/plain" });
        res.end("not found");
      } catch (e) {
        this.log.error({ event: "HTTP_ERROR", err: String(e) });
        if (!res.headersSent) {
          res.writeHead(500, { "content-type": "text/plain" });
          res.end("internal error");
        }
      }
    });

    server.listen(this.port, "0.0.0.0", () => {
      this.log.info({ event: "HTTP_LISTEN", port: this.port });
    });
  }

  private async serveRange(
    res: import("node:http").ServerResponse,
    req: import("node:http").IncomingMessage,
    path: string,
    _art: string | null
  ): Promise<void> {
    let info;
    try {
      info = await stat(path);
      if (!info.isFile()) throw new Error("not a file");
    } catch {
      res.writeHead(404, { "content-type": "text/plain" });
      res.end("not found");
      return;
    }
    const range = req.headers.range;
    const mime = MIME[extname(path)] ?? "application/octet-stream";
    if (range) {
      const m = /^bytes=(\d*)-(\d*)$/.exec(range);
      if (m) {
        const start = m[1] === "" ? 0 : Number(m[1] ?? 0);
        const requestedEnd = m[2] === "" ? info.size - 1 : Number(m[2] ?? info.size - 1);
        const end = Math.min(requestedEnd, info.size - 1);
        if (start <= end && start < info.size) {
          res.writeHead(206, {
            "content-type": mime,
            "accept-ranges": "bytes",
            "content-range": `bytes ${start}-${end}/${info.size}`,
            "content-length": String(end - start + 1),
          });
          createReadStream(path, { start, end }).pipe(res);
          return;
        }
      }
      res.writeHead(416, { "content-range": `bytes */${info.size}` });
      res.end();
      return;
    }
    res.writeHead(200, {
      "content-type": mime,
      "accept-ranges": "bytes",
      "content-length": String(info.size),
    });
    createReadStream(path).pipe(res);
    return;
  }
}