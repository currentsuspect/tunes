import { readFileSync } from "node:fs";
import { mkdir } from "node:fs/promises";
import { join } from "node:path";
import { loadEnv } from "./env.js";
import { FetchEngine } from "./fetch.js";
import type { ChannelConfig } from "./fetch.js";
import { makeLogger } from "./logger.js";
import { buildManifest } from "./manifest.js";
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
    const manifestBuilder = async () => {
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
      }
      return buildManifest([...probeCache.values()]);
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
      const server = new ManifestServer(store, manifestBuilder, env.port, log);
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