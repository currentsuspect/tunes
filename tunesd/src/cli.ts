import { readFileSync } from "node:fs";
import { mkdir, readFile, writeFile, rename } from "node:fs/promises";
import { join } from "node:path";
import { loadEnv } from "./env.js";
import { MusicBrainzClient, parseArtistTitle } from "./enrich.js";
import type { EnrichmentEntry } from "./enrich.js";
import { FetchEngine } from "./fetch.js";
import type { ChannelConfig } from "./fetch.js";
import { makeLogger } from "./logger.js";
import { buildManifest } from "./manifest.js";
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
    const mb = new MusicBrainzClient(
      "tunes/0.1 ( https://github.com/currentsuspect/tunes )",
      env.dataDir
    );
    const WEEK_MS = 7 * 24 * 60 * 60 * 1000;

    const manifestBuilder = async () => {
      const metaBySha = state.allSeenMeta();
      for (const obj of await store.listObjects()) {
        if (!probeCache.has(obj.sha)) {
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
        const existing = enrich.get(obj.sha);
        const stale = existing && Date.now() - Date.parse(existing.enrichedAt) > WEEK_MS;
        if (existing && !stale) continue;

        const probe = probeCache.get(obj.sha)!;
        const tagged = Boolean(probe.tags.title) || Boolean(probe.tags.artist) || Boolean(probe.tags.album);
        if (tagged) {
          enrich.set(obj.sha, {
            sha: obj.sha,
            artist: null,
            album: null,
            year: null,
            artSha: null,
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
            enrichedAt: new Date().toISOString(),
          });
          continue;
        }
        const hit = await mb.searchRecording(parsed);
        if (!hit || !hit.album) {
          log.info({ event: "ENRICH_MISS", sha: obj.sha.slice(0, 8), parsed });
          continue;
        }
        const cover = await mb.fetchCover(hit.album.releaseId);
        if (cover) log.info({ event: "ENRICH_ART", sha: obj.sha.slice(0, 8), artSha: cover.sha.slice(0, 8) });
        enrich.set(obj.sha, {
          sha: obj.sha,
          artist: hit.artist,
          album: hit.album.title,
          year: hit.album.year,
          artSha: cover?.sha ?? null,
          enrichedAt: new Date().toISOString(),
        });
        log.info({
          event: "ENRICH_OK",
          sha: obj.sha.slice(0, 8),
          artist: hit.artist,
          album: hit.album.title,
        });
        await persistEnrich();
      }
      const enrichForManifest = new Map<string, TrackEnrichment>();
      for (const [sha, e] of enrich) {
        enrichForManifest.set(sha, { artist: e.artist, album: e.album, year: e.year, artSha: e.artSha });
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