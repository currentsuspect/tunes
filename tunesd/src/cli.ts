import { readFileSync } from "node:fs";
import { mkdir, readFile, writeFile, rename } from "node:fs/promises";
import { join } from "node:path";
import { loadEnv } from "./env.js";
import { DiscogsClient, MusicBrainzClient, parseArtistTitle, SpotifyClient, storeCoverBytes } from "./enrich.js";
import type { EnrichmentEntry } from "./enrich.js";
import { FetchEngine } from "./fetch.js";
import type { ChannelConfig } from "./fetch.js";
import { makeLogger } from "./logger.js";
import { buildManifest, isCategoryRelease } from "./manifest.js";
import type { TrackEnrichment } from "./manifest.js";
import { probeFile } from "./probe.js";
import type { ProbeResult } from "./probe.js";
import { ManifestServer } from "./serve.js";
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
    const engine = new FetchEngine(client, store, state, { dataDir: env.dataDir, fetch: env.fetch }, log);

    const probeCache = new Map<string, ProbeResult>();
    const enrichFile = join(env.dataDir, "enrich.json");
    const enrich = new Map<string, EnrichmentEntry>();
    try {
      const raw = JSON.parse(await readFile(enrichFile, "utf8")) as {
        entries: Record<string, EnrichmentEntry>;
      };
      for (const [sha, e] of Object.entries(raw.entries ?? {})) enrich.set(sha, e);
    } catch {
      // fresh start
    }
    const persistEnrich = async () => {
      await mkdir(env.dataDir, { recursive: true });
      const tmp = join(env.dataDir, `.enrich-${process.pid}.tmp`);
      await writeFile(tmp, JSON.stringify({ entries: Object.fromEntries(enrich) }, null, 1));
      await rename(tmp, enrichFile);
    };
    const tryReleaseMembership = async (
      parsed: { artist: string; title: string },
      sha: string
    ): Promise<{ releaseId: string; album: string; type: string | null; position: number } | null> => {
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
          const titleOk = normTitle(t.title) === normTitle(parsed.title);
          const artistOk = t.artist == null || normName(t.artist) === normName(parsed.artist);
          const durMs = probeCache.get(sha)?.durationMs ?? null;
          const durOk = t.lengthMs == null || durMs == null || Math.abs(t.lengthMs - durMs) <= 4000;
          if (titleOk && artistOk && durOk) {
            return {
              releaseId: releaseId.slice(3),
              album: release.title,
              type: release.type,
              position: t.position,
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
    if (!spotify) log.warn({ event: "ENRICH_SPOTIFY_DISABLED" });
    if (!discogs) log.warn({ event: "ENRICH_DISCOGS_DISABLED" });
    const WEEK_MS = 7 * 24 * 60 * 60 * 1000;

    let enrichPassRunning = false;
    const runEnrichPass = async () => {
      if (enrichPassRunning) return;
      enrichPassRunning = true;
      try {
      const metaBySha = state.allSeenMeta();
      const objects = await store.listObjects();
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
            probedAt: new Date().toISOString(),
          });
        }
      }
      for (const obj of objects) {
        const existing = enrich.get(obj.sha);
        const stale = existing && Date.now() - Date.parse(existing.enrichedAt) > WEEK_MS;
        const needsReleaseId = existing && !existing.releaseId;
        const categoryStuck = existing && isCategoryRelease(existing.album ?? "");
        if (existing && !stale && !needsReleaseId && !categoryStuck) continue;
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
            source: null,
            enrichedAt: new Date().toISOString(),
          });
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
            source: null,
            enrichedAt: new Date().toISOString(),
          });
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
          continue;
        }
        if (spotify) {
          const sp = await spotify.search(parsed);
          if (sp) {
            let artSha: string | null = null;
            if (sp.artUrl) {
              try {
                const res = await fetch(sp.artUrl);
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
            await persistEnrich();
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
          continue;
        }
        if (discogs) {
          const dg = await discogs.search(parsed);
          if (dg) {
            let artSha: string | null = null;
            if (dg.artUrl) {
              try {
                const res = await fetch(dg.artUrl);
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
            continue;
          }
        }
        log.info({ event: "ENRICH_MISS", sha: obj.sha.slice(0, 8), parsed });
      }
      } finally {
        enrichPassRunning = false;
      }
    };

    const manifestBuilder = async () => {
      const metaBySha = state.allSeenMeta();
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
        });
      }
      return buildManifest([...probeCache.values()], metaBySha, enrichForManifest);
    };

    const run = async (): Promise<void> => {
      const result = await engine.runCycle(channels);
      log.info({
        event: "CYCLE_DONE",
        channels: result.channels,
        aborted: result.aborted,
        reason: result.reason,
      });
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
      const server = new ManifestServer(
        store,
        join(env.dataDir, "covers"),
        manifestBuilder,
        env.port,
        log
      );
      await server.start();
      void runEnrichPass();
      const enrichTimer = setInterval(() => void runEnrichPass(), 90_000);
      process.on("exit", () => clearInterval(enrichTimer));

      if (immediate) {
        try {
          await run();
        } catch (e) {
          log.error({ event: "CYCLE_FAILED", err: String(e) });
        }
      }
      while (!shuttingDown) {
        await sleep(scanCadenceMs);
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