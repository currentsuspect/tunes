import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { defaultFetchDiscipline } from "./config.js";
import type { FetchDisciplineConfig } from "./config.js";

export interface TunesdEnv {
  apiId: number;
  apiHash: string;
  sessionFile: string;
  dataDir: string;
  logLevel: "debug" | "info" | "warn" | "error";
  fetch: FetchDisciplineConfig;
  port: number;

  /// The interface the HTTP server binds to.
  ///
  /// Defaults to 0.0.0.0 — every interface — which is what it always did and
  /// what a single-machine setup wants. It is worth being able to change,
  /// because the server has no authentication of any kind: every device that
  /// can reach the port gets the whole library and can stream any track.
  ///
  /// On a laptop that joins other people's networks, or when the intended
  /// path in is a tailnet, bind the one interface you mean:
  ///
  ///     TUNESD_HOST=100.100.235.90   # this node's Tailscale address
  ///     TUNESD_HOST=127.0.0.1        # local only
  host: string;
}

function loadEnvFile(p: string): void {
  if (!existsSync(p)) return;
  const text = readFileSync(p, "utf8");
  for (const raw of text.split("\n")) {
    const line = raw.trim();
    if (line === "" || line.startsWith("#")) continue;
    const eq = line.indexOf("=");
    if (eq <= 0) continue;
    const key = line.slice(0, eq).trim();
    const value = line.slice(eq + 1).trim();
    if (process.env[key] === undefined) process.env[key] = value;
  }
}

export function loadEnv(env: NodeJS.ProcessEnv = process.env): TunesdEnv {
  const here = dirname(fileURLToPath(import.meta.url));
  const root = join(here, "..");
  loadEnvFile(join(root, ".env"));

  const dataDir = env["TUNESD_DATA_DIR"] ?? join(root, "data");
  const apiIdRaw = env["TUNESD_API_ID"];
  const apiHash = env["TUNESD_API_HASH"];
  if (!apiIdRaw || !apiHash) {
    throw new Error("TUNESD_API_ID and TUNESD_API_HASH required (from my.telegram.org)");
  }
  const apiId = Number(apiIdRaw);
  if (!Number.isFinite(apiId)) throw new Error("TUNESD_API_ID must be a number");

  const overrides: Partial<FetchDisciplineConfig> = {};
  const delay = Number(env["TUNESD_FETCH_DELAY_MS"]);
  const jitter = Number(env["TUNESD_FETCH_JITTER_MS"]);
  const cap = Number(env["TUNESD_FETCH_DAILY_CAP"]);
  if (Number.isFinite(delay)) overrides.perChannelDelayMs = delay;
  if (Number.isFinite(jitter)) overrides.jitterMs = jitter;
  if (Number.isFinite(cap)) overrides.dailyCapFiles = cap;

  return {
    apiId,
    apiHash,
    sessionFile: env["TUNESD_SESSION_FILE"] ?? join(dataDir, "session"),
    dataDir,
    logLevel: (env["TUNESD_LOG_LEVEL"] ?? "info") as TunesdEnv["logLevel"],
    fetch: { ...defaultFetchDiscipline, ...overrides },
    port: Number(env["TUNESD_PORT"] ?? 4780),
    host: env["TUNESD_HOST"] ?? "0.0.0.0",
  };
}