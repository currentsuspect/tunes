import { readFileSync } from "node:fs";
import { mkdir, readFile, writeFile, rename, stat } from "node:fs/promises";
import { join } from "node:path";
import { loadEnv } from "./env.js";
import type { ArtistDiscography } from "./discography.js";
import {
  loadDiscographies,
  missingFromCollection,
  persistDiscographies,
} from "./discography.js";
import { parseCredits, releaseArtistOf, sameArtistName } from "./credits.js";
import { DiscogsClient, MusicBrainzClient, parseArtistTitle, SpotifyClient, storeCoverBytes } from "./enrich.js";
import { enrichBackoffMs, enrichRetryDue } from "./enrich.js";
import type { EnrichAttempt, EnrichmentEntry } from "./enrich.js";
import { FetchEngine } from "./fetch.js";
import type { ChannelConfig } from "./fetch.js";
import { makeLogger } from "./logger.js";
import { buildManifest, isCategoryRelease, releaseArtKey } from "./manifest.js";
import type { ReleaseLinkMeta, TrackEnrichment } from "./manifest.js";
import { DeezerClient, DeezerUnavailable } from "./deezer.js";
import { LastfmClient, LastfmUnavailable } from "./lastfm.js";
import { extractEmbeddedArt, PROBE_VERSION, probeFile } from "./probe.js";
import type { ProbeResult } from "./probe.js";
import { ManifestServer } from "./serve.js";
import { publishCloud } from "./cloudpublish.js";
import { publishAudioFile, selectAudioToBackfill, selectNewRows } from "./cloudpublish.js";
import { AudioPusher } from "./audiopush.js";
import { coalesce, Wake } from "./ingest.js";
import { OnDemandFetcher } from "./ondemand.js";
import { UpdateFeed } from "./updates.js";
import { State } from "./state.js";
import { ObjectStore } from "./store.js";
import { MtprotoClient } from "./telegram/mtproto.js";
import { PermanentError, sleep } from "./telegram/ports.js";

function channelsFromEnv(env: NodeJS.ProcessEnv): ChannelConfig[] {
  const raw = env["TUNESD_CHANNELS"];
  const list = raw
    ? raw
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean)
    : [];
  const out: ChannelConfig[] = [];
  for (const item of list) {
    const eq = item.indexOf("=");
    const id = Number(eq > 0 ? item.slice(0, eq) : item);
    if (!Number.isFinite(id)) throw new Error(`invalid TUNESD_CHANNELS entry: ${item}`);
    out.push({ id, title: eq > 0 ? item.slice(eq + 1) : String(id), enabled: true });
  }
  return out;
}

function normTitle(s: string): string {
  return s.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
}
function bareTitle(s: string): string {
  const stripped = s.replace(/\s*\(.*?\)\s*/g, " ").replace(/\s*\(.*$/, " ");
  return normTitle(stripped);
}
function normName(s: string): string {
  return s.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
}

function readSession(path: string): string {
  try {
    return readFileSync(path, "utf8").trim();
  } catch {
    return "";
  }
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const mode = args[0] ?? "serve";
  const scanCadenceMs = Number(process.env["TUNESD_SCAN_CADENCE_MS"] ?? 300_000);
  const immediate = !args.includes("--no-immediate");

  try {
    const env = loadEnv();
    const log = makeLogger(env.logLevel);
    const channels = channelsFromEnv(process.env);
    if (channels.length === 0) throw new Error("TUNESD_CHANNELS required: <chatId>=<title>,...");
    await mkdir(env.dataDir, { recursive: true });

    const state = await new State(join(env.dataDir, "state.json")).load();
    const store = new ObjectStore(env.dataDir);
    const client = new MtprotoClient(
      { apiId: env.apiId, apiHash: env.apiHash, session: readSession(env.sessionFile) },
      log
    );
    // Filled in once publishing and the audio pusher exist (below); the engine
    // reads it at call time.
    const ingestHooks: { onDownloaded?: (d: { sha: string; size: number }) => void } = {};
    const engine = new FetchEngine(client, store, state, { dataDir: env.dataDir, fetch: env.fetch }, log, ingestHooks);
    // ORIGIN step 1: serve misses from Telegram through the fetcher instead
    // of 404. Same session the daemon already serves from -- a tap is
    // human-low-frequency and counts against the same daily cap.
    const onDemand = new OnDemandFetcher(client, store, state, {
      dailyCapFiles: env.fetch.dailyCapFiles,
    }, log);

    const probeCache = new Map<string, ProbeResult>();
    // Probe results are keyed by content hash, so they never go stale for a
    // given object. Without persisting them a restart blanked every track to
    // "unknown artist"/"unknown album" until the whole library was re-read,
    // and re-ran ffprobe over every file to learn what it already knew.
    const probeFile_ = join(env.dataDir, "probe.json");
    try {
      const raw = JSON.parse(await readFile(probeFile_, "utf8")) as {
        version?: number;
        entries: Record<string, ProbeResult>;
      };
      if (raw.version === PROBE_VERSION) {
        for (const [sha, p] of Object.entries(raw.entries ?? {})) probeCache.set(sha, p);
      }
    } catch {
      // fresh start
    }
    const persistProbes = async () => {
      await mkdir(env.dataDir, { recursive: true });
      const tmp = join(env.dataDir, `.probe-${process.pid}.tmp`);
      await writeFile(
        tmp,
        JSON.stringify({ version: PROBE_VERSION, entries: Object.fromEntries(probeCache) }, null, 1)
      );
      await rename(tmp, probeFile_);
    };
    const enrichFile = join(env.dataDir, "enrich.json");
    const enrich = new Map<string, EnrichmentEntry>();
    try {
      const raw = JSON.parse(await readFile(enrichFile, "utf8")) as {
        entries: Record<string, EnrichmentEntry>;
      };
      for (const [sha, e] of Object.entries(raw.entries ?? {})) {
        enrich.set(sha, { ...e, membership: e.membership ?? [] });
      }
    } catch {
      // fresh start
    }
    const persistEnrich = async () => {
      await mkdir(env.dataDir, { recursive: true });
      const tmp = join(env.dataDir, `.enrich-${process.pid}.tmp`);
      await writeFile(tmp, JSON.stringify({ entries: Object.fromEntries(enrich) }, null, 1));
      await rename(tmp, enrichFile);
    };
    // sha -> cover sha, for art lifted out of the file itself. Persisted so a
    // restart does not re-run ffmpeg over the whole library.
    const embeddedArtFile = join(env.dataDir, "embedded-art.json");
    const embeddedArt = new Map<string, string>();
    try {
      const raw = JSON.parse(await readFile(embeddedArtFile, "utf8")) as {
        art: Record<string, string>;
      };
      for (const [sha, artSha] of Object.entries(raw.art ?? {})) embeddedArt.set(sha, artSha);
    } catch {
      // fresh start
    }
    const persistEmbeddedArt = async () => {
      await mkdir(env.dataDir, { recursive: true });
      const tmp = join(env.dataDir, `.embedded-art-${process.pid}.tmp`);
      await writeFile(tmp, JSON.stringify({ art: Object.fromEntries(embeddedArt) }, null, 1));
      await rename(tmp, embeddedArtFile);
    };
    const enrichAttemptsFile = join(env.dataDir, "enrich-attempts.json");
    const enrichAttempts = new Map<string, EnrichAttempt>();
    try {
      const raw = JSON.parse(await readFile(enrichAttemptsFile, "utf8")) as {
        entries: Record<string, EnrichAttempt>;
      };
      for (const [sha, a] of Object.entries(raw.entries ?? {})) enrichAttempts.set(sha, a);
    } catch {
      // fresh start
    }
    const persistEnrichAttempts = async () => {
      await mkdir(env.dataDir, { recursive: true });
      const tmp = join(env.dataDir, `.enrich-attempts-${process.pid}.tmp`);
      await writeFile(tmp, JSON.stringify({ entries: Object.fromEntries(enrichAttempts) }, null, 1));
      await rename(tmp, enrichAttemptsFile);
    };
    // A pass that leaves a track unresolved must say so, or the next pass cannot
    // tell it apart from a track nobody has looked at yet (SPEC §4: never retry hot).
    const noteEnrichAttempt = async (sha: string) => {
      const prev = enrichAttempts.get(sha);
      enrichAttempts.set(sha, {
        attempts: (prev?.attempts ?? 0) + 1,
        lastAttemptAt: new Date().toISOString(),
      });
      await persistEnrichAttempts();
    };
    const clearEnrichAttempt = async (sha: string) => {
      if (enrichAttempts.delete(sha)) await persistEnrichAttempts();
    };
    // "<act>|<album>" -> cover sha, for releases whose files carry no picture at
    // all. CHROMAKOPIA's 13 tracks each hold one audio stream and nothing else.
    const releaseArtFile = join(env.dataDir, "release-art.json");
    const releaseArt = new Map<string, string>();
    const releaseArtMisses = new Map<string, string>();
    try {
      const raw = JSON.parse(await readFile(releaseArtFile, "utf8")) as {
        art: Record<string, string>;
        misses?: Record<string, string>;
      };
      for (const [k, v] of Object.entries(raw.art ?? {})) releaseArt.set(k, v);
      for (const [k, v] of Object.entries(raw.misses ?? {})) releaseArtMisses.set(k, v);
    } catch {
      // fresh start
    }
    const persistReleaseArt = async () => {
      await mkdir(env.dataDir, { recursive: true });
      const tmp = join(env.dataDir, `.release-art-${process.pid}.tmp`);
      await writeFile(
        tmp,
        JSON.stringify(
          { art: Object.fromEntries(releaseArt), misses: Object.fromEntries(releaseArtMisses) },
          null,
          1
        )
      );
      await rename(tmp, releaseArtFile);
    };
    const linkMetaFile = join(env.dataDir, "linkmeta.json");
    const linkMeta = new Map<string, ReleaseLinkMeta>();
    try {
      const raw = JSON.parse(await readFile(linkMetaFile, "utf8")) as {
        releases: Record<string, ReleaseLinkMeta>;
      };
      for (const [id, r] of Object.entries(raw.releases ?? {})) linkMeta.set(id, r);
    } catch {
      // fresh start
    }
    const persistLinkMeta = async () => {
      await mkdir(env.dataDir, { recursive: true });
      const tmp = join(env.dataDir, `.linkmeta-${process.pid}.tmp`);
      await writeFile(tmp, JSON.stringify({ releases: Object.fromEntries(linkMeta) }, null, 1));
      await rename(tmp, linkMetaFile);
    };
    const discographyFile = join(env.dataDir, "discography.json");
    const discographies = await loadDiscographies(discographyFile);
    let lastDiscographySweep = 0;
    const releaseGroupShas = (): Map<string, string[]> => {
      const groups = new Map<string, string[]>();
      for (const e of enrich.values()) {
        if (!e.releaseId) continue;
        const list = groups.get(e.releaseId) ?? [];
        list.push(e.sha);
        groups.set(e.releaseId, list);
      }
      return groups;
    };

    const tryReleaseMembership = async (
      parsed: { artist: string; title: string },
      sha: string
    ): Promise<{
      releaseId: string;
      album: string;
      type: string | null;
      position: number;
      discNumber: number;
    } | null> => {
      const mbReleases = new Map<string, string[]>();
      for (const e of enrich.values()) {
        if (e.artist === parsed.artist && e.releaseId?.startsWith("mb:")) {
          const list = mbReleases.get(e.releaseId) ?? [];
          list.push(e.sha);
          mbReleases.set(e.releaseId, list);
        }
      }
      const candidates = [...mbReleases.entries()]
        .sort((a, b) => b[1].length - a[1].length)
        .slice(0, 3);
      for (const [releaseId, _shas] of candidates) {
        const release = await mb.releaseWithRecordings(releaseId.slice(3));
        if (!release) continue;
        for (const t of release.tracks) {
          if (t.position <= 0) continue;
          const titleOk =
            bareTitle(t.title) === bareTitle(parsed.title) ||
            normTitle(t.title) === normTitle(parsed.title);
          const artistOk = t.artist == null || normName(t.artist) === normName(parsed.artist);
          const durMs = probeCache.get(sha)?.durationMs ?? null;
          const durOk = t.lengthMs == null || durMs == null || Math.abs(t.lengthMs - durMs) <= 4000;
          if (titleOk && artistOk && durOk) {
            return {
              releaseId: releaseId.slice(3),
              album: release.title,
              type: release.type,
              position: t.position,
              discNumber: t.discNumber,
            };
          }
        }
      }
      return null;
    };

    const mb = new MusicBrainzClient(
      "tunes/0.1 ( https://github.com/currentsuspect/tunes )",
      env.dataDir
    );
    const spotifyId = process.env["TUNESD_SPOTIFY_ID"];
    const spotifySecret = process.env["TUNESD_SPOTIFY_SECRET"];
    const spotify = spotifyId && spotifySecret
      ? new SpotifyClient(spotifyId, spotifySecret)
      : null;
    const discogsToken = process.env["TUNESD_DISCOGS_TOKEN"];
    const discogs = discogsToken
      ? new DiscogsClient(discogsToken, "tunes/0.1 ( https://github.com/currentsuspect/tunes )")
      : null;
    const lastfmKey = process.env["TUNESD_LASTFM_KEY"];
    const lastfm = lastfmKey
      ? new LastfmClient(lastfmKey, "tunes/0.1 ( https://github.com/currentsuspect/tunes )")
      : null;
    if (!spotify) log.warn({ event: "ENRICH_SPOTIFY_DISABLED" });
    if (!discogs) log.warn({ event: "ENRICH_DISCOGS_DISABLED" });
    if (!lastfm) log.warn({ event: "ENRICH_LASTFM_DISABLED" });
    // No key, no account, no auth. tunesd-side only: the app still talks to
    // nothing but the user-configured tunesd (SPEC §1.5, §2.4).
    const deezer = new DeezerClient("tunes/0.1 ( https://github.com/currentsuspect/tunes )");

    // name -> crowd tags + popularity, kept out of enrich.json because it is
    // about the artist, not the file.
    const artistMetaFile = join(env.dataDir, "artist-meta.json");
    const artistMeta = new Map<string, { tags: string[]; listeners: number | null; fetchedAt: string }>();
    try {
      const raw = JSON.parse(await readFile(artistMetaFile, "utf8")) as {
        artists: Record<string, { tags: string[]; listeners: number | null; fetchedAt: string }>;
      };
      for (const [name, m] of Object.entries(raw.artists ?? {})) artistMeta.set(name, m);
    } catch {
      // fresh start
    }
    const persistArtistMeta = async () => {
      await mkdir(env.dataDir, { recursive: true });
      const tmp = join(env.dataDir, `.artist-meta-${process.pid}.tmp`);
      await writeFile(tmp, JSON.stringify({ artists: Object.fromEntries(artistMeta) }, null, 1));
      await rename(tmp, artistMetaFile);
    };
    const WEEK_MS = 7 * 24 * 60 * 60 * 1000;
    // Covers fetched per cycle for albums we do not have. The rail shows a
    // handful at a time, so there is nothing to gain from fetching a whole
    // catalogue at once, and the negative cache means a run that finds
    // nothing does not repeat for a week.
    const MISSING_ART_PER_CYCLE = 12;
    const artistsFile = join(env.dataDir, "artists.json");
    const artists = new Map<string, string>();
    try {
      const raw = JSON.parse(await readFile(artistsFile, "utf8")) as {
        artists: Record<string, string>;
      };
      for (const [name, sha] of Object.entries(raw.artists ?? {})) artists.set(name, sha);
    } catch {
      // fresh start
    }
    const persistArtists = async () => {
      await mkdir(env.dataDir, { recursive: true });
      const tmp = join(env.dataDir, `.artists-${process.pid}.tmp`);
      await writeFile(tmp, JSON.stringify({ artists: Object.fromEntries(artists) }, null, 1));
      await rename(tmp, artistsFile);
    };
    const artistImageFor = async (artistId: string, artistName: string) => {
      if (artists.has(artistName)) return;
      const url = await spotify?.artistImage(artistId);
      if (!url) return;
      try {
        const res = await fetch(url, { signal: AbortSignal.timeout(15_000) });
        if (!res.ok) return;
        const bytes = new Uint8Array(await res.arrayBuffer());
        if (bytes.length < 1000) return;
        const { sha } = await storeCoverBytes(env.dataDir, bytes);
        artists.set(artistName, sha);
        log.info({ event: "ARTIST_IMAGE", artist: artistName, sha: sha.slice(0, 8) });
        await persistArtists();
      } catch {
        // never fail enrichment over an artist image
      }
    };
    // Names Spotify could not resolve. Without this only *successes* were
    // remembered, so an unmatchable name was looked up again on every single
    // call — two API round trips each, forever.
    const artistMissFile = join(env.dataDir, "artist-misses.json");
    const artistMisses = new Map<string, string>();
    try {
      const raw = JSON.parse(await readFile(artistMissFile, "utf8")) as {
        misses: Record<string, string>;
      };
      for (const [name, at] of Object.entries(raw.misses ?? {})) artistMisses.set(name, at);
    } catch {
      // fresh start
    }
    const persistArtistMisses = async () => {
      await mkdir(env.dataDir, { recursive: true });
      const tmp = join(env.dataDir, `.artist-misses-${process.pid}.tmp`);
      await writeFile(tmp, JSON.stringify({ misses: Object.fromEntries(artistMisses) }, null, 1));
      await rename(tmp, artistMissFile);
    };
    /** Stores an artist photo from a URL. Shared by the Spotify and Last.fm paths. */
    const storeArtistImage = async (url: string, artistName: string): Promise<boolean> => {
      try {
        const res = await fetch(url, { signal: AbortSignal.timeout(15_000) });
        if (!res.ok) return false;
        const bytes = new Uint8Array(await res.arrayBuffer());
        if (bytes.length < 1000) return false;
        const { sha } = await storeCoverBytes(env.dataDir, bytes);
        artists.set(artistName, sha);
        await persistArtists();
        return true;
      } catch {
        return false;
      }
    };
    const backfillArtistPhotos = async () => {
      // Deezer needs no credentials, so the sweep always has at least one
      // provider to try.
      const names = new Set<string>();
      // parseCredits, not splitArtistNames: a credit line separates its names
      // with commas as often as semicolons, and querying a provider for the
      // whole of "Fimiguerrero, Lancey Foux, Len" can only ever miss.
      const addCredit = (raw: string | null | undefined) => {
        if (raw == null || raw.trim() === "") return;
        const { primary, featured } = parseCredits(raw);
        for (const name of [primary, ...featured]) {
          if (name !== "") names.add(name);
        }
      };
      for (const t of probeCache.values()) {
        addCredit(t.tags.artist);
        addCredit(t.tags.albumArtist);
      }
      for (const e of enrich.values()) addCredit(e.artist);
      let missed = false;
      let metaChanged = false;
      let spotifyReported = false;
      let lastfmReported = false;
      let deezerReported = false;
      for (const name of names) {
        if (name === "unknown artist") continue;
        const havePicture = artists.has(name);
        const haveMeta = artistMeta.has(name);
        if (havePicture && haveMeta) continue;
        const missedAt = artistMisses.get(name);
        if (missedAt != null && Date.now() - Date.parse(missedAt) < WEEK_MS) continue;

        let resolved = havePicture;
        let couldNotLook = false;

        // Tags and popularity from Last.fm. Only accepted when the row it
        // answered with is actually this artist: asked for "Len" it returns the
        // 90s Canadian band, and asked for "Travis Scott" a near-namesake.
        if (!haveMeta && lastfm) {
          try {
            const info = await lastfm.artistInfo(name);
            if (info != null) {
              if (sameArtistName(info.name, name)) {
                artistMeta.set(name, {
                  tags: info.tags.slice(0, 6),
                  listeners: info.listeners,
                  fetchedAt: new Date().toISOString(),
                });
                metaChanged = true;
              } else {
                log.info({ event: "ARTIST_NAME_MISMATCH", source: "lastfm", asked: name, got: info.name });
              }
            }
          } catch (e) {
            if (!(e instanceof LastfmUnavailable)) throw e;
            if (!lastfmReported) {
              log.warn({ event: "LASTFM_UNAVAILABLE", err: String(e) });
              lastfmReported = true;
            }
            couldNotLook = true;
          }
        }

        if (!resolved && spotify) {
          try {
            const id =
              (await spotify.searchArtistId(name)) ?? (await spotify.artistIdFromTrack(name));
            if (id) {
              await artistImageFor(id, name);
              resolved = artists.has(name);
            }
          } catch (e) {
            // Could not consult Spotify at all. Recording this as "no such
            // artist" would bake a transport failure into a week-long lie.
            if (!spotifyReported) {
              log.warn({ event: "SPOTIFY_UNAVAILABLE", err: String(e) });
              spotifyReported = true;
            }
            couldNotLook = true;
          }
        }

        // Deezer is the working picture source. Last.fm has served one grey
        // star for every artist since 2019, so it is not tried for images.
        if (!resolved) {
          try {
            const candidates = await deezer.searchArtistCandidates(name);
            const match = candidates.find((c) => sameArtistName(c.name, name));
            if (match?.pictureUrl) {
              resolved = await storeArtistImage(match.pictureUrl, name);
              if (resolved) {
                log.info({ event: "ARTIST_IMAGE", source: "deezer", artist: name });
              }
            } else if (candidates.length > 0 && match == null) {
              log.info({
                event: "ARTIST_NAME_MISMATCH",
                source: "deezer",
                asked: name,
                got: candidates[0]?.name ?? null,
              });
            }
          } catch (e) {
            if (!(e instanceof DeezerUnavailable)) throw e;
            if (!deezerReported) {
              log.warn({ event: "DEEZER_UNAVAILABLE", err: String(e) });
              deezerReported = true;
            }
            couldNotLook = true;
          }
        }

        if (resolved) {
          if (artistMisses.delete(name)) missed = true;
          continue;
        }
        // Only a real "nobody has a picture of this artist" is worth caching.
        if (couldNotLook) continue;
        artistMisses.set(name, new Date().toISOString());
        missed = true;
      }
      if (metaChanged) await persistArtistMeta();
      if (missed) await persistArtistMisses();
    };

    let enrichPassRunning = false;
    const runEnrichPass = async () => {
      if (enrichPassRunning) return;
      enrichPassRunning = true;
      try {
      const metaBySha = state.allSeenMeta();
      const objects = await store.listObjects();
      const probedBefore = probeCache.size;
      for (const obj of objects) {
        if (probeCache.has(obj.sha)) continue;
        try {
          probeCache.set(obj.sha, await probeFile(obj.sha, obj.size, store.pathOf(obj.sha)));
        } catch {
          log.warn({ event: "PROBE_FAILED", sha: obj.sha });
          probeCache.set(obj.sha, {
            sha: obj.sha,
            size: obj.size,
            codec: null,
            sampleRate: null,
            channels: null,
            bitrate: null,
            durationMs: null,
            tags: {},
            hasEmbeddedArt: false,
            audioSha: null,
            probedAt: new Date().toISOString(),
          });
        }
      }
      if (probeCache.size !== probedBefore) await persistProbes();
      // Lift cover art out of the files that carry it. Costs one ffmpeg
      // stream-copy per object, once ever — the result is content-addressed
      // into the same cover store the providers write to.
      for (const obj of objects) {
        if (embeddedArt.has(obj.sha)) continue;
        if (!probeCache.get(obj.sha)?.hasEmbeddedArt) continue;
        const bytes = await extractEmbeddedArt(store.pathOf(obj.sha));
        if (!bytes) continue;
        const { sha: artSha } = await storeCoverBytes(env.dataDir, bytes);
        embeddedArt.set(obj.sha, artSha);
        await persistEmbeddedArt();
        log.info({
          event: "ART_EMBEDDED",
          sha: obj.sha.slice(0, 8),
          artSha: artSha.slice(0, 8),
          bytes: bytes.length,
        });
      }
      // Releases whose files carry no picture at all need one from somewhere.
      // One lookup per release, not per track, and only when every track in it
      // is bare.
      const bareReleases = new Map<string, { artist: string; album: string }>();
      for (const obj of objects) {
        const probe = probeCache.get(obj.sha);
        if (probe == null) continue;
        if (embeddedArt.has(obj.sha)) continue;
        const album = probe.tags.album?.trim();
        const artist = probe.tags.artist?.trim();
        if (!album || !artist) continue;
        const act = releaseArtistOf(probe.tags.albumArtist ?? null, artist);
        if (act === "") continue;
        const key = releaseArtKey(act, album);
        if (releaseArt.has(key)) continue;
        const missedAt = releaseArtMisses.get(key);
        if (missedAt != null && Date.now() - Date.parse(missedAt) < WEEK_MS) continue;
        if (!bareReleases.has(key)) bareReleases.set(key, { artist: act, album });
      }
      let releaseArtChanged = false;
      let releaseArtReported = false;
      for (const [key, { artist, album }] of bareReleases) {
        try {
          const candidates = await deezer.searchAlbumCandidates(artist, album);
          // Both names must match: a cover is a claim about which record this
          // is, and the wrong one is worse than none.
          const match = candidates.find(
            (c) => sameArtistName(c.artist, artist) && normName(c.title) === normName(album)
          );
          if (match?.coverUrl == null) {
            releaseArtMisses.set(key, new Date().toISOString());
            releaseArtChanged = true;
            if (candidates.length > 0) {
              log.info({
                event: "RELEASE_ART_MISMATCH",
                asked: `${artist} — ${album}`,
                got: `${candidates[0]?.artist ?? "?"} — ${candidates[0]?.title ?? "?"}`,
              });
            }
            continue;
          }
          const res = await fetch(match.coverUrl, { signal: AbortSignal.timeout(20_000) });
          if (!res.ok) continue;
          const bytes = new Uint8Array(await res.arrayBuffer());
          if (bytes.length < 1000) continue;
          const { sha } = await storeCoverBytes(env.dataDir, bytes);
          releaseArt.set(key, sha);
          releaseArtMisses.delete(key);
          releaseArtChanged = true;
          log.info({
            event: "RELEASE_ART",
            source: "deezer",
            release: `${artist} — ${album}`,
            artSha: sha.slice(0, 8),
          });
        } catch (e) {
          if (!(e instanceof DeezerUnavailable)) throw e;
          if (!releaseArtReported) {
            log.warn({ event: "DEEZER_UNAVAILABLE", err: String(e) });
            releaseArtReported = true;
          }
          break;
        }
      }
      if (releaseArtChanged) await persistReleaseArt();

      // Artist photos are network work: they belong on the pass timer, never
      // in the /manifest request path where the app waits on them. Run them
      // before the release-ordering loop so its long rate-limit sleeps cannot
      // starve the artist list.
      await backfillArtistPhotos();
      for (const obj of objects) {
        const existing = enrich.get(obj.sha);
        const stale = existing && Date.now() - Date.parse(existing.enrichedAt) > WEEK_MS;
        const needsReleaseId = existing && !existing.releaseId;
        const categoryStuck = existing && isCategoryRelease(existing.album ?? "");
        if (existing && !stale && !needsReleaseId && !categoryStuck) continue;
        // Unresolved tracks back off instead of re-running the cascade every pass.
        if (!enrichRetryDue(enrichAttempts.get(obj.sha), Date.now())) continue;
        if (categoryStuck) {
          const stuckMeta = metaBySha.get(obj.sha);
          const stuckSeed = stuckMeta?.fileName ?? stuckMeta?.caption ?? "";
          const stuckParsed = parseArtistTitle(stuckSeed);
          if (stuckParsed) {
            const member = await tryReleaseMembership(stuckParsed, obj.sha);
            if (member) {
              enrich.set(obj.sha, {
                sha: obj.sha,
                artist: stuckParsed.artist,
                album: member.album,
                year: null,
                artSha: null,
                releaseId: `mb:${member.releaseId}`,
                releaseType: member.type,
                trackNumber: member.position,
                discNumber: member.discNumber,
                totalTracks: null,
                                membership: [],
                                source: "musicbrainz",
                enrichedAt: new Date().toISOString(),
              });
              log.info({
                event: "ENRICH_REPARENT",
                sha: obj.sha.slice(0, 8),
                title: stuckParsed.title,
                into: member.album,
                track: member.position,
              });
              await persistEnrich();
              await clearEnrichAttempt(obj.sha);
              continue;
            }
          }
        }

        const probe = probeCache.get(obj.sha)!;
        const tagged = Boolean(probe.tags.title) || Boolean(probe.tags.artist) || Boolean(probe.tags.album);
        if (tagged) {
          enrich.set(obj.sha, {
            sha: obj.sha,
            artist: null,
            album: null,
            year: null,
            artSha: null,
            releaseId: null,
            releaseType: null,
            trackNumber: null,
            discNumber: null,
            totalTracks: null,
                        membership: [],
                        source: null,
            enrichedAt: new Date().toISOString(),
          });
          await noteEnrichAttempt(obj.sha);
          continue;
        }
        const meta = metaBySha.get(obj.sha);
        const seed = meta?.fileName ?? meta?.caption ?? "";
        const parsed = parseArtistTitle(seed);
        if (!parsed) {
          enrich.set(obj.sha, {
            sha: obj.sha,
            artist: null,
            album: null,
            year: null,
            artSha: null,
            releaseId: null,
            releaseType: null,
            trackNumber: null,
            discNumber: null,
            totalTracks: null,
                        membership: [],
                        source: null,
            enrichedAt: new Date().toISOString(),
          });
          await noteEnrichAttempt(obj.sha);
          continue;
        }
        const hit = await mb.searchRecording(parsed);
        if (hit && hit.album) {
          const cover = await mb.fetchCover(hit.album.releaseId);
          if (cover)
            log.info({ event: "ENRICH_ART", sha: obj.sha.slice(0, 8), artSha: cover.sha.slice(0, 8) });
          enrich.set(obj.sha, {
            sha: obj.sha,
            artist: hit.artist,
            album: hit.album.title,
            year: hit.album.year,
            artSha: cover?.sha ?? null,
            releaseId: `mb:${hit.album.releaseId}`,
            releaseType: hit.album.primaryType ?? null,
            trackNumber: null,
            discNumber: null,
            totalTracks: null,
                        membership: [],
                        source: "musicbrainz",
            enrichedAt: new Date().toISOString(),
          });
          log.info({
            event: "ENRICH_OK",
            source: "musicbrainz",
            sha: obj.sha.slice(0, 8),
            artist: hit.artist,
            album: hit.album.title,
          });
          await persistEnrich();
          await clearEnrichAttempt(obj.sha);
          continue;
        }
        if (spotify) {
          const sp = await spotify.search(parsed);
          if (sp) {
            let artSha: string | null = null;
            if (sp.artUrl) {
              try {
                const res = await fetch(sp.artUrl, { signal: AbortSignal.timeout(15_000) });
                if (res.ok) {
                  const bytes = new Uint8Array(await res.arrayBuffer());
                  if (bytes.length > 1000) {
                    artSha = (await storeCoverBytes(env.dataDir, bytes)).sha;
                  }
                }
              } catch {
                artSha = null;
              }
            }
            enrich.set(obj.sha, {
              sha: obj.sha,
              artist: sp.artist,
              album: sp.album,
              year: sp.year,
              artSha,
              releaseId: sp.albumId != null ? `sp:${sp.albumId}` : null,
              releaseType: sp.albumType ?? null,
              trackNumber: sp.trackNumber,
              discNumber: null,
              totalTracks: null,
                            membership: [],
                            source: "spotify",
              enrichedAt: new Date().toISOString(),
            });
            log.info({
              event: "ENRICH_OK",
              source: "spotify",
              sha: obj.sha.slice(0, 8),
              artist: sp.artist,
              album: sp.album,
              year: sp.year,
              artSha: artSha?.slice(0, 8) ?? null,
            });
            if (sp.artistId) await artistImageFor(sp.artistId, sp.artist);
            await persistEnrich();
            await clearEnrichAttempt(obj.sha);
            continue;
          }
        }
        const member = await tryReleaseMembership(parsed, obj.sha);
        if (member) {
          enrich.set(obj.sha, {
            sha: obj.sha,
            artist: parsed.artist,
            album: member.album,
            year: null,
            artSha: null,
            releaseId: `mb:${member.releaseId}`,
            releaseType: member.type,
            trackNumber: member.position,
            discNumber: member.discNumber,
            totalTracks: null,
                        membership: [],
                        source: "musicbrainz",
            enrichedAt: new Date().toISOString(),
          });
          log.info({
            event: "ENRICH_REPARENT",
            sha: obj.sha.slice(0, 8),
            title: parsed.title,
            into: member.album,
            track: member.position,
          });
          await persistEnrich();
          await clearEnrichAttempt(obj.sha);
          continue;
        }
        if (discogs) {
          const dg = await discogs.search(parsed);
          if (dg) {
            let artSha: string | null = null;
            if (dg.artUrl) {
              try {
                const res = await fetch(dg.artUrl, { signal: AbortSignal.timeout(15_000) });
                if (res.ok) {
                  const bytes = new Uint8Array(await res.arrayBuffer());
                  if (bytes.length > 1000) {
                    artSha = (await storeCoverBytes(env.dataDir, bytes)).sha;
                  }
                }
              } catch {
                artSha = null;
              }
            }
            enrich.set(obj.sha, {
              sha: obj.sha,
              artist: dg.artist,
              album: dg.album,
              year: dg.year,
              artSha,
              releaseId: dg.albumId,
              releaseType: null,
              trackNumber: null,
              discNumber: null,
              totalTracks: null,
                            membership: [],
                            source: "discogs",
              enrichedAt: new Date().toISOString(),
            });
            log.info({
              event: "ENRICH_OK",
              source: "discogs",
              sha: obj.sha.slice(0, 8),
              artist: dg.artist,
              album: dg.album,
              year: dg.year,
            });
            await persistEnrich();
            await clearEnrichAttempt(obj.sha);
            continue;
          }
        }
        await noteEnrichAttempt(obj.sha);
        const attempt = enrichAttempts.get(obj.sha)!;
        log.info({
          event: "ENRICH_MISS",
          sha: obj.sha.slice(0, 8),
          parsed,
          attempts: attempt.attempts,
          retryInMs: enrichBackoffMs(attempt.attempts),
        });
      }

      const releaseGroups = releaseGroupShas();
      for (const [releaseId, shas] of releaseGroups) {
        if (!releaseId.startsWith("mb:")) continue;
        let release = await mb.releaseWithRecordings(releaseId.slice(3));
        if (!release) {
          await sleep(12_000);
          release = await mb.releaseWithRecordings(releaseId.slice(3));
        }
        if (!release) {
          log.warn({ event: "ENRICH_ORDER_SKIP", release: releaseId.slice(0, 12) });
          continue;
        }
        await sleep(1_000);
        if (release.tracks.length > 0) {
          linkMeta.set(releaseId, {
            title: release.title,
            type: release.type,
            totalTracks: release.tracks.length,
            groupId: release.groupId,
            date: release.date,
          });
          await persistLinkMeta();
        }
        let changed = false;
        for (const sha of shas) {
          const entry = enrich.get(sha);
          if (entry && entry.totalTracks == null && release.tracks.length > 0) {
            enrich.set(sha, { ...entry, totalTracks: release.tracks.length });
            changed = true;
          }
          const e = enrich.get(sha);
          if (!e || e.trackNumber != null) continue;
          const probe = probeCache.get(sha);
          const meta = metaBySha.get(sha);
          const probeTitle = probe?.tags.title;
          const metaTitle = meta?.fileName
            ? meta.fileName.replace(/\.[^.]+$/, "").replace(/\s+/g, " ").trim()
            : null;
          const parsedTitle = metaTitle ? parseArtistTitle(metaTitle) : null;
          const title =
            probeTitle ??
            (parsedTitle && e.artist && normName(parsedTitle.artist) === normName(e.artist)
              ? parsedTitle.title
              : metaTitle);
          const durMs = probe?.durationMs ?? null;
          const candidates = [
            title,
            parsedTitle?.title ?? null,
            probeTitle,
            metaTitle,
          ].filter((t): t is string => t != null);
          const match = release.tracks.find((t) => {
            const titleOk = candidates.some(
              (c) =>
                bareTitle(t.title) === bareTitle(c) ||
                normTitle(t.title) === normTitle(c)
            );
            const durOk =
              t.lengthMs == null ||
              durMs == null ||
              Math.abs(t.lengthMs - durMs) <= 4000;
            return titleOk && durOk;
          });
          if (match && match.position > 0) {
            enrich.set(sha, {
              ...e,
              trackNumber: match.position,
              discNumber: match.discNumber,
            });
            changed = true;
            log.info({
              event: "ENRICH_ORDER",
              release: releaseId.slice(0, 12),
              track: match.position,
              title: match.title,
            });
          }
        }
        for (const [sha, e] of enrich) {
          if (!e.album || e.releaseId === releaseId) continue;
          const existing = e.membership.find((m) => m.id === releaseId);
          const probe = probeCache.get(sha);
          const meta = metaBySha.get(sha);
          const probeTitle = probe?.tags.title;
          const metaTitle = meta?.fileName
            ? meta.fileName.replace(/\.[^.]+$/, "").replace(/\s+/g, " ").trim()
            : null;
          const parsedTitle = metaTitle ? parseArtistTitle(metaTitle) : null;
          const title = probeTitle ?? parsedTitle?.title ?? metaTitle;
          if (!title) continue;
          const durMs = probe?.durationMs ?? null;
          const candidates = [
            title,
            parsedTitle?.title ?? null,
            probeTitle,
            metaTitle,
          ].filter((t): t is string => t != null);
          const match = release.tracks.find((t) => {
            const titleOk = candidates.some(
              (c) =>
                bareTitle(t.title) === bareTitle(c) ||
                normTitle(t.title) === normTitle(c)
            );
            const durOk =
              t.lengthMs == null ||
              durMs == null ||
              Math.abs(t.lengthMs - durMs) <= 4000;
            return titleOk && durOk;
          });
          if (match && match.position > 0) {
            if (
              existing &&
              existing.position === match.position &&
              existing.disc === match.discNumber
            ) {
              continue;
            }
            enrich.set(sha, {
              ...e,
              membership: existing
                ? e.membership.map((m) =>
                    m.id === releaseId
                      ? { id: releaseId, position: match.position, disc: match.discNumber }
                      : m
                  )
                : [
                    ...e.membership,
                    { id: releaseId, position: match.position, disc: match.discNumber },
                  ],
            });
            changed = true;
            log.info({
              event: "ENRICH_CROSSLINK",
              release: releaseId.slice(0, 12),
              track: match.position,
            });
          }
        }
        if (changed) await persistEnrich();
      }

      const refreshDiscographies = async () => {
        if (Date.now() - lastDiscographySweep < 3_600_000) return;
        lastDiscographySweep = Date.now();
        const names = [
          ...new Set(
            [...enrich.values()].map((e) => e.artist).filter((n): n is string => n != null)
          ),
        ];
        let changed = false;
        for (const name of names) {
          const cached = discographies.get(normName(name));
          if (cached && Date.now() - cached.fetchedAt < 7 * 86_400_000) continue;
          const d = await mb.artistDiscography(name);
          if (!d) continue;
          discographies.set(normName(name), { ...d, name, fetchedAt: Date.now() });
          changed = true;
          log.info({
            event: "DISC_GROUP_SYNCED",
            artist: normName(name).slice(0, 20),
            groups: d.groups.length,
          });
        }
        if (changed) await persistDiscographies(discographyFile, discographies);
      };
      await refreshDiscographies();

      // Covers for records we do not have. Without them the suggestion rail
      // is a wall of generated tiles; a real sleeve is what makes it read as
      // "go and get this". Stored in the same release-art map, keyed the same
      // way, so a cover fetched here is already in place if the album later
      // arrives.
      const refreshMissingArtwork = async (): Promise<void> => {
        const manifest = await manifestBuilder();
        const perArtist = new Map<string, number>();
        for (const t of manifest.tracks) {
          const act = (t.primaryArtist || t.artist || "").trim();
          if (act !== "") perArtist.set(act, (perArtist.get(act) ?? 0) + 1);
        }
        const wanted = missingFromCollection(
          [...perArtist].map(([name, tracks]) => ({ name, tracks })),
          discographies,
          manifest.releases,
          { limit: MISSING_ART_PER_CYCLE * 5 }
        );
        let changed = false;
        let reported = false;
        let fetched = 0;
        for (const g of wanted) {
          // Bounded per cycle: this is a nice-to-have rail, and the whole
          // catalogue of every act would be hundreds of lookups at once.
          if (fetched >= MISSING_ART_PER_CYCLE) break;
          const key = releaseArtKey(g.forArtist, g.title);
          if (releaseArt.has(key)) continue;
          const missedAt = releaseArtMisses.get(key);
          if (missedAt != null && Date.now() - Date.parse(missedAt) < WEEK_MS) {
            continue;
          }
          try {
            const candidates = await deezer.searchAlbumCandidates(
              g.forArtist,
              g.title
            );
            // Both names must match. A cover is a claim about which record
            // this is, and the wrong sleeve is worse than none -- more so
            // here, where the cover is the only thing identifying an album
            // the owner has never seen.
            const match = candidates.find(
              (c) =>
                sameArtistName(c.artist, g.forArtist) &&
                normName(c.title) === normName(g.title)
            );
            if (match?.coverUrl == null) {
              releaseArtMisses.set(key, new Date().toISOString());
              changed = true;
              continue;
            }
            const res = await fetch(match.coverUrl, {
              signal: AbortSignal.timeout(20_000),
            });
            if (!res.ok) continue;
            const bytes = new Uint8Array(await res.arrayBuffer());
            if (bytes.length < 1000) continue;
            const { sha } = await storeCoverBytes(env.dataDir, bytes);
            releaseArt.set(key, sha);
            releaseArtMisses.delete(key);
            changed = true;
            fetched += 1;
            log.info({
              event: "MISSING_ART",
              source: "deezer",
              release: `${g.forArtist} — ${g.title}`,
              artSha: sha.slice(0, 8),
            });
          } catch (e) {
            if (!(e instanceof DeezerUnavailable)) throw e;
            // Transport down: stop, and record nothing. A miss cached now
            // would read as "this album has no cover" for a week.
            if (!reported) {
              log.warn({ event: "DEEZER_UNAVAILABLE", err: String(e) });
              reported = true;
            }
            break;
          }
        }
        if (changed) await persistReleaseArt();
      };
      await refreshMissingArtwork();

      } finally {
        enrichPassRunning = false;
      }
    };

    const manifestBuilder = async () => {
      const metaBySha = state.allSeenMeta();
      const objects = await store.listObjects();
      const artistNames = new Set([...artists.keys(), ...artistMeta.keys()]);
      const artistList = [...artistNames].map((name) => {
        const meta = artistMeta.get(name);
        return {
          name,
          artSha: artists.get(name) ?? null,
          ...(meta && meta.tags.length > 0 ? { tags: meta.tags } : {}),
          ...(meta && meta.listeners != null ? { listeners: meta.listeners } : {}),
        };
      });
      const enrichForManifest = new Map<string, TrackEnrichment>();
      for (const [sha, e] of enrich) {
        enrichForManifest.set(sha, {
          artist: e.artist,
          album: e.album,
          year: e.year,
          artSha: e.artSha,
          releaseId: e.releaseId,
          releaseType: e.releaseType,
          trackNumber: e.trackNumber,
          discNumber: e.discNumber,
          totalTracks: e.totalTracks,
          membership: e.membership,
        });
      }
      return buildManifest(
        [...probeCache.values()],
        metaBySha,
        enrichForManifest,
        objects,
        artistList,
        linkMeta,
        state.allAddedAt(),
        embeddedArt,
        releaseArt
      );
    };

    // In-memory publish watermarks: rows newer than rowsSince, manifest when
    // its integrity moves. A restart re-sends the full set once, which is
    // hundreds of writes rarely -- against hundreds every five minutes
    // before, which tripped D1's free write cap.
    let rowsSince: string | null = null;
    let lastIntegrity: string | null = null;

    const channelIds = channels.map((c) => String(c.id));
    const publishNow = async (): Promise<void> => {
      if (!env.publishUrl || !env.publishKey) return;
      try {
        const manifest = await manifestBuilder();
        const integrity = (manifest as { integrity?: unknown }).integrity ?? null;
        // Every channel ever seen, not just the configured ones: tracks ingested
        // from a retired channel were never given a Telegram source in the
        // cloud, so they 404ed there ("skips until one lands").
        const { rows, watermark } = selectNewRows(
          state.sightingsFor([...new Set([...channelIds, ...state.channelIdsSeen()])]),
          rowsSince
        );
        const manifestChanged = typeof integrity === "string" && integrity !== lastIntegrity;
        if (rows.length === 0 && !manifestChanged) return;
        const done = await publishCloud({
          url: env.publishUrl,
          key: env.publishKey,
          manifest,
          rows,
          log,
        });
        if (done !== null) {
          rowsSince = watermark;
          if (manifestChanged && typeof integrity === "string") lastIntegrity = integrity;
        }
      } catch (e) {
        log.warn({ event: "PUBLISH_FAILED", err: String(e).slice(0, 200) });
      }
    };
    // As each file lands, show it: at most one publish per 30 s, never two at
    // once, and one trailing publish so the last file is never left unshown.
    // The download pacing is untouched; this only changes when results appear.
    const publishSoon = coalesce(publishNow, 30_000);

    // New audio goes up to R2 from the local copy straight away, so a friend's
    // first play of it is a cache hit rather than a cold Telegram fetch.
    const audioLedgerFile = join(env.dataDir, "audio-published.json");
    const audioLedger: Record<string, string> = {};
    try {
      const raw = JSON.parse(await readFile(audioLedgerFile, "utf8")) as { audio?: Record<string, string> };
      Object.assign(audioLedger, raw.audio ?? {});
    } catch {
      void undefined; // first run
    }
    const audioBase = env.publishUrl?.replace(/\/publish\/?$/, "/audio") ?? "";
    const audioPusher =
      env.publishUrl && env.publishKey && /\/audio$/.test(audioBase)
        ? new AudioPusher(audioLedger, {
            log,
            read: async (sha) => {
              if (!store.has(sha)) return null;
              return new Uint8Array(await readFile(store.pathOf(sha)));
            },
            put: (sha, bytes) =>
              publishAudioFile({
                baseUrl: audioBase,
                key: env.publishKey as string,
                sha,
                bytes,
                log,
              }),
            save: async (ledger) => {
              await writeFile(audioLedgerFile, JSON.stringify({ audio: ledger }, null, 1));
            },
          })
        : null;
    // Whatever the box holds that R2 has not been sent, newest first.
    const queueAudioBacklog = async (): Promise<void> => {
      if (!audioPusher) return;
      const held = await store.listObjects();
      const dated = await Promise.all(
        held.map(async (o) => {
          try {
            return { sha: o.sha, at: (await stat(store.pathOf(o.sha))).mtimeMs };
          } catch {
            return { sha: o.sha, at: 0 };
          }
        })
      );
      audioPusher.enqueue(selectAudioToBackfill(dated.sort((a, b) => b.at - a.at).map((d) => d.sha), audioLedger, () => true));
    };
    ingestHooks.onDownloaded = ({ sha }) => {
      audioPusher?.enqueue([sha]);
      publishSoon.request();
    };

    // Telegram tells us about new posts; the poll below is only the safety net.
    const wake = new Wake({ settleMs: 5_000, minGapMs: 20_000 });

    const run = async (): Promise<void> => {
      wake.started();
      const result = await engine.runCycle(channels);
      log.info({
        event: "CYCLE_DONE",
        channels: result.channels,
        aborted: result.aborted,
        reason: result.reason,
      });
      // Best effort and not awaited: the scan schedule is ban-safety, publishing
      // must not shift it, and a failure only logs.
      publishSoon.request();
      void queueAudioBacklog().catch((e) =>
        log.warn({ event: "AUDIO_BACKLOG_FAILED", err: String(e).slice(0, 160) })
      );
      return;
    };

    if (mode === "serve") {
      let shuttingDown = false;
      const shutdown = (sig: string) => {
        if (shuttingDown) return;
        shuttingDown = true;
        log.info({ event: "SHUTDOWN", signal: sig });
        void client
          .disconnect()
          .then(() => process.exit(0))
          .catch(() => process.exit(0));
      };
      process.on("SIGINT", () => shutdown("SIGINT"));
      process.on("SIGTERM", () => shutdown("SIGTERM"));
      log.info({ event: "TUNESD_START", channels: channels.map((c) => c.id) });

      // App updates. Null without a token, and the server simply reports "no
      // update" — a daemon that only serves music is unaffected.
      const updates = env.updateToken
        ? new UpdateFeed(
            env.updateRepo,
            env.updateToken,
            join(env.dataDir, "updates"),
            log,
          )
        : null;
      if (updates) {
        // Not awaited: the library must not wait on GitHub to start serving.
        void updates.poll();
        const updateTimer = setInterval(
          () => void updates.poll(),
          env.updatePollMs,
        );
        // Otherwise the interval keeps the process alive through a shutdown
        // that has already finished everything else.
        updateTimer.unref();
      }
      const server = new ManifestServer(
        store,
        join(env.dataDir, "covers"),
        manifestBuilder,
        env.port,
        log,
        () => discographies,
        (q) => mb.searchArtists(q),
        (q) => mb.searchReleaseGroups(q),
        async (name) => {
          const d = await mb.artistDiscography(name);
          if (!d) return null;
          const entry: ArtistDiscography = { ...d, name, fetchedAt: Date.now() };
          discographies.set(normName(name), entry);
          await persistDiscographies(discographyFile, discographies);
          return entry;
        },
        () => releaseArt,
        env.host,
        updates,
        onDemand
      );
      await server.start();
      void runEnrichPass()
        .then(() => publishSoon.request())
        .catch((e) => log.error({ event: "ENRICH_PASS_ERROR", err: String(e) }));
      const enrichTimer = setInterval(() => {
        void runEnrichPass()
          .then(() => publishSoon.request())
          .catch((e) => log.error({ event: "ENRICH_PASS_ERROR", err: String(e) }));
      }, 90_000);
      process.on("exit", () => clearInterval(enrichTimer));

      if (immediate) {
        try {
          await run();
        } catch (e) {
          log.error({ event: "CYCLE_FAILED", err: String(e) });
        }
      }
      for (const ch of channels) {
        void client
          .watchChannel(ch.id, () => wake.poke())
          .catch((e) => log.warn({ event: "WATCH_FAILED", channel: ch.id, err: String(e).slice(0, 160) }));
      }
      while (!shuttingDown) {
        const why = await wake.wait(scanCadenceMs);
        if (why === "push") log.info({ event: "SCAN_WAKE", reason: "telegram-push" });
        if (shuttingDown) break;
        try {
          await run();
        } catch (e) {
          if (e instanceof PermanentError) {
            log.error({ event: "FATAL", err: String(e) });
            process.exit(1);
          }
          log.error({ event: "CYCLE_FAILED", err: String(e) });
          await sleep(60_000);
        }
      }
    } else if (mode === "once") {
      await run();
      await client.disconnect();
    } else {
      throw new Error(`unknown mode: ${mode}`);
    }
  } catch (e) {
    console.error(String(e));
    process.exit(1);
  }
}

void main();