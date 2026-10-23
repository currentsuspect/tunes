import { createServer } from "node:http";
import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import { extname, join } from "node:path";
import type { ObjectStore } from "./store.js";
import type { Log } from "./logger.js";
import type { OnDemandFetcher } from "./ondemand.js";
import type { Getter, GetRequest } from "./getter.js";
import type { ManifestV3 } from "./manifest.js";
import { releaseArtKey } from "./manifest.js";
import type { UpdateFeed } from "./updates.js";
import { kMaxLyricChars, type LyricStore } from "./lyricstore.js";
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
  missingFromCollection,
  normName,
} from "./discography.js";

/** How long /search will wait on external discovery before answering local-only. */
const EXTERNAL_SEARCH_BUDGET_MS = 1500;

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
  private lastManifest: ManifestV3 | null = null;
  private lastBuiltAt = 0;

  constructor(
    private readonly store: ObjectStore,
    private readonly artDir: string,
    private readonly buildManifest: () => Promise<ManifestV3>,
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
      | null = null,
    /// Release-level cover art, keyed by `releaseArtKey(act, album)`. The
    /// same map the daemon fills for releases we hold, reused for the ones we
    /// only know about — a cover is a cover regardless of whether the audio
    /// is here.
    private readonly getReleaseArt: () => Map<string, string> = () => new Map(),
    /// Interface to bind. Last and defaulted so no existing caller changes:
    /// 0.0.0.0 is what this always did. See TunesdEnv.host for why narrowing
    /// it is sometimes the point.
    private readonly host: string = "0.0.0.0",
    /// App updates, or null when no token is configured. Optional so a daemon
    /// that only serves music is unchanged.
    private readonly updates: UpdateFeed | null = null,
    /// On-demand fetch for store misses (ORIGIN step 1). Null serves the old
    /// way: a miss is a 404. Optional so existing callers and tests that only
    /// serve music are unchanged.
    private readonly onDemand: OnDemandFetcher | null = null,
    /// Where listeners' lyrics live, so one person adding them adds them for
    /// everyone. Null leaves PUT /lyrics unavailable and /changes unchanged.
    private readonly lyrics: LyricStore | null = null,
    /// Told after a listener's lyrics are stored, so the daemon can put the new
    /// manifest on the edge now instead of at the next cycle.
    private readonly onLyricsChanged: (() => void) | null = null,
    /// Soulseek search and gets on request (getter.ts), or null when slskd is
    /// not set up: those routes then answer 503.
    private readonly getter: Getter | null = null
  ) {
    this.externalCache = new Map();
  }

  private readonly externalCache: Map<
    string,
    { at: number; artists: ExternalArtist[]; releases: DiscographyGroup[] }
  >;

  private async getManifest(force = false): Promise<ManifestV3> {
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

        // What the newest app build is, so a phone can tell whether it is
        // behind without a GitHub account. 204 when there is nothing to
        // report — no token configured, or the first poll has not landed —
        // which the app reads as "no update" rather than as an error.
        if (url.pathname === "/update") {
          const info = this.updates?.latest() ?? null;
          if (!info) {
            res.writeHead(204);
            res.end();
            return;
          }
          res.writeHead(200, { "content-type": "application/json; charset=utf-8" });
          res.end(JSON.stringify(info));
          return;
        }

        // The APK itself. Range-served like audio, so a download resumes
        // rather than restarting -- these are 100 MB over a phone connection.
        if (url.pathname === "/update/apk") {
          const path = this.updates?.apk() ?? null;
          if (!path) {
            res.writeHead(404, { "content-type": "text/plain" });
            res.end("no update");
            return;
          }
          await this.serveRange(res, req, path, null);
          return;
        }

        if (url.pathname === "/changes") {
          // /changes?since=<iso8601>
          // Returns the set of tracks whose addedAt is strictly greater
          // than the cutoff. The full tracks/releases/artists array is
          // returned when `since` is missing or invalid (i.e. cold
          // start). The app uses this to avoid re-downloading the
          // entire manifest on every poll.
          const since = url.searchParams.get("since");
          const cutoff = since ? Date.parse(since) : NaN;
          const manifest = await this.getManifest();
          const cutoffMs = Number.isFinite(cutoff) ? cutoff : -Infinity;
          const added = manifest.tracks
            .filter((t) => {
              const ts = t.addedAt ? Date.parse(t.addedAt) : NaN;
              return Number.isFinite(ts) && ts > cutoffMs;
            })
            .map((t) => t.sha);
          // Tracks whose lyrics were added or changed since the phone last
          // looked. A new lyric adds no track, so addedShas alone would tell a
          // phone nothing had happened.
          const lyricsChanged = this.lyrics
            ? this.lyrics.changedSince(cutoffMs)
            : [];
          res.writeHead(200, { "content-type": "application/json; charset=utf-8" });
          res.end(
            JSON.stringify({
              generatedAt: manifest.generatedAt,
              integrity: manifest.integrity,
              addedShas: added,
              lyricsChanged,
            }),
          );
          return;
        }

        // A listener's lyrics for a track, shared with everyone through the
        // manifest. PUT { "lyrics": "<text>" }; empty text takes the
        // listener's version away.
        const lyricMatch = /^\/lyrics\/([0-9a-f]{64})$/.exec(url.pathname);
        if (lyricMatch) {
          if (req.method !== "PUT") {
            res.writeHead(405, { allow: "PUT", "content-type": "text/plain" });
            res.end("PUT only");
            return;
          }
          if (!this.lyrics) {
            res.writeHead(503, { "content-type": "text/plain" });
            res.end("lyrics are not available");
            return;
          }
          const sha = lyricMatch[1]!;
          const manifest = await this.getManifest();
          if (!manifest.tracks.some((t) => t.sha === sha)) {
            res.writeHead(404, { "content-type": "text/plain" });
            res.end("no such track");
            return;
          }
          const body = await readBody(req, kMaxLyricChars * 4 + 1024);
          let text: unknown;
          try {
            text = (JSON.parse(body ?? "") as { lyrics?: unknown }).lyrics;
          } catch {
            text = undefined;
          }
          if (
            body === null ||
            typeof text !== "string" ||
            text.length > kMaxLyricChars
          ) {
            res.writeHead(400, { "content-type": "text/plain" });
            res.end("expected { lyrics: string } of reasonable length");
            return;
          }
          await this.lyrics.setUser(sha, text);
          // The 30-second manifest cache would otherwise hide it from the next
          // phone to ask.
          this.lastManifest = null;
          this.onLyricsChanged?.();
          res.writeHead(204);
          res.end();
          return;
        }

        const trackMatch = /^\/track\/([0-9a-f]{64})$/.exec(url.pathname);
        if (trackMatch) {
          const sha = trackMatch[1] ?? "";
          // ORIGIN step 1: a miss resolves through Telegram instead of 404.
          // The first tap on a never-fetched track pays the download once;
          // after that it is a store hit like anything else.
          if (this.onDemand && !this.store.has(sha)) {
            const fetched = await this.onDemand.fetchTrack(sha);
            if (fetched === null) {
              res.writeHead(404, { "content-type": "text/plain" });
              res.end("not found");
              return;
            }
          }
          // Pinned while it streams, so the cache never evicts a song from
          // under a listener; touched, so it counts as recently played.
          const release = this.store.beginRead(sha);
          res.on("close", release);
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
              // Discovery is a bonus on top of the library the user already
              // has. The local answer is ready in microseconds, so it must
              // never wait on Spotify and MusicBrainz round trips — a cold
              // query used to hold the whole response for tens of seconds.
              // Give them a short budget; whatever misses it still lands in
              // the cache and shows up on the next keystroke.
              const pending = Promise.all([artistSearcher(q), releaseSearcher(q)])
                .then(([a, r]) => {
                  if (a.length > 0 || r.length > 0) {
                    this.externalCache.set(qn, { at: Date.now(), artists: a, releases: r });
                  }
                  if (this.externalCache.size > 64) {
                    const oldest = [...this.externalCache.entries()].sort(
                      (x, y) => x[1].at - y[1].at
                    )[0]?.[0];
                    if (oldest) this.externalCache.delete(oldest);
                  }
                  return { artists: a, releases: r };
                })
                .catch(() => null);
              const settled = await Promise.race([
                pending,
                new Promise<null>((resolve) => {
                  setTimeout(() => resolve(null), EXTERNAL_SEARCH_BUDGET_MS).unref();
                }),
              ]);
              if (settled) {
                artists = settled.artists;
                rg = settled.releases;
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

        // Songs out there, getting one, how gets are going, an album's full
        // track list, and filling an album in (getter.ts).
        if (
          url.pathname === "/soulseek/search" ||
          url.pathname === "/soulseek/get" ||
          url.pathname === "/soulseek/jobs" ||
          url.pathname === "/soulseek/complete" ||
          url.pathname === "/tracklist"
        ) {
          const json = (code: number, body: unknown) => {
            res.writeHead(code, { "content-type": "application/json; charset=utf-8" });
            res.end(JSON.stringify(body));
          };
          const getter = this.getter;
          if (!getter) return json(503, { error: "soulseek is not set up" });
          if (url.pathname === "/soulseek/search") {
            const q = (url.searchParams.get("q") ?? "").trim();
            if (q.length < 2) return json(400, { error: "missing q" });
            try {
              return json(200, { songs: await getter.search(q) });
            } catch (e) {
              return json(503, { error: String(e) });
            }
          }
          if (url.pathname === "/soulseek/jobs") return json(200, { jobs: getter.list() });
          if (url.pathname === "/tracklist") {
            const id = url.searchParams.get("release") ?? "";
            const tracks = await getter.tracklist(id).catch(() => null);
            return tracks ? json(200, { tracks }) : json(404, { error: "no track list" });
          }
          if (req.method !== "POST") return json(405, { error: "POST only" });
          const body = await readBody(req, 16 * 1024);
          let parsed: Record<string, unknown> = {};
          try {
            parsed = JSON.parse(body ?? "") as Record<string, unknown>;
          } catch {
            return json(400, { error: "expected JSON" });
          }
          if (url.pathname === "/soulseek/complete") {
            const id = typeof parsed.release === "string" ? parsed.release : "";
            return json(200, { jobs: await getter.complete(id).catch(() => []) });
          }
          const str = (k: string) => (typeof parsed[k] === "string" ? (parsed[k] as string) : null);
          const num = (k: string) => (typeof parsed[k] === "number" ? (parsed[k] as number) : null);
          const title = str("title");
          const artist = str("artist");
          if (!title || !artist) return json(400, { error: "title and artist" });
          const reqBody: GetRequest = {
            title,
            artist,
            album: str("album"),
            durationMs: num("durationMs"),
            release: str("release"),
            username: str("username"),
            filename: str("filename"),
            size: num("size"),
          };
          return json(200, { job: getter.get(reqBody) });
        }

        if (url.pathname === "/missing") {
          const limitRaw = Number(url.searchParams.get("limit"));
          const limit =
            Number.isFinite(limitRaw) && limitRaw > 0
              ? Math.min(Math.trunc(limitRaw), 200)
              : 40;
          const manifest = await this.getManifest();
          // Weight by the act, not the raw credit line, so a guest verse does
          // not rank an artist the owner barely listens to above one they do.
          const tracksPerArtist = new Map<string, number>();
          for (const t of manifest.tracks) {
            const act = (t.primaryArtist || t.artist || "").trim();
            if (act === "") continue;
            tracksPerArtist.set(act, (tracksPerArtist.get(act) ?? 0) + 1);
          }
          const found = missingFromCollection(
            [...tracksPerArtist].map(([name, tracks]) => ({ name, tracks })),
            this.getDiscographies(),
            manifest.releases,
            { limit }
          );
          // Attach a cover when the daemon has already fetched one. Absent is
          // normal -- the fetch happens on the enrichment cycle, not here, so
          // that answering this route never waits on Deezer.
          const art = this.getReleaseArt();
          const groups = found.map((g) => ({
            ...g,
            artSha: art.get(releaseArtKey(g.forArtist, g.title)) ?? null,
          }));
          res.writeHead(200, {
            "content-type": "application/json; charset=utf-8",
          });
          res.end(JSON.stringify({ groups }));
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

    server.listen(this.port, this.host, () => {
      // The host is logged, not just the port. There is no authentication on
      // any route here, so "which interfaces is this on" is the entire access
      // control story -- it belongs in the log rather than in someone's memory
      // of how the service was started.
      this.log.info({
        event: "HTTP_LISTEN",
        port: this.port,
        host: this.host,
        exposure: this.host === "127.0.0.1" || this.host === "::1"
          ? "local-only"
          : this.host === "0.0.0.0" || this.host === "::"
            ? "all-interfaces (no auth: anyone who can reach this port has the library)"
            : `bound to ${this.host}`,
      });
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

/** The body of a request as text, or null when it is larger than [limit]. */
async function readBody(
  req: import("node:http").IncomingMessage,
  limit: number,
): Promise<string | null> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of req) {
    const buf = chunk as Buffer;
    size += buf.length;
    if (size > limit) return null;
    chunks.push(buf);
  }
  return Buffer.concat(chunks).toString("utf8");
}
