import { readFileSync } from "node:fs";
import { mkdir } from "node:fs/promises";
import { join } from "node:path";
import { loadEnv } from "../src/env.js";
import { FetchEngine } from "../src/fetch.js";
import type { ChannelConfig } from "../src/fetch.js";
import { makeLogger } from "../src/logger.js";
import { State } from "../src/state.js";
import { ObjectStore } from "../src/store.js";
import { MtprotoClient } from "../src/telegram/mtproto.js";

const GATE_TAG = "E2E_GATE";

async function run(): Promise<void> {
  const env = loadEnv();
  const log = makeLogger(env.logLevel);
  const mode = process.argv[2] ?? "first";
  if (!["first", "replay", "rewind"].includes(mode)) {
    throw new Error(`unknown e2e mode: ${mode} (want first|replay|rewind)`);
  }

  const chatRaw = process.env["TUNESD_E2E_CHAT"];
  if (!chatRaw) throw new Error("TUNESD_E2E_CHAT required for the E2E gate");
  const eq = chatRaw.indexOf("=");
  const chatId = Number(eq > 0 ? chatRaw.slice(0, eq) : chatRaw);
  if (!Number.isFinite(chatId)) throw new Error(`invalid TUNESD_E2E_CHAT: ${chatRaw}`);
  const channels: ChannelConfig[] = [{ id: chatId, title: eq > 0 ? chatRaw.slice(eq + 1) : "e2e", enabled: true }];

  await mkdir(env.dataDir, { recursive: true });
  const state = await new State(join(env.dataDir, "state.json")).load();
  const store = new ObjectStore(env.dataDir);
  const client = new MtprotoClient(
    { apiId: env.apiId, apiHash: env.apiHash, session: readFileSync(env.sessionFile, "utf8").trim() },
    log
  );
  const engine = new FetchEngine(client, store, state, { dataDir: env.dataDir, fetch: env.fetch }, log);

  if (mode === "rewind") {
    state.setCursor(String(chatId), { headCursor: 0, lastScanAt: null });
    await state.save();
  }

  const result = await engine.runCycle(channels);
  const downloaded = result.channels.reduce((s, c) => s + c.downloaded, 0);
  const skipped = result.channels.reduce((s, c) => s + c.skippedSeen, 0);

  const shas = state.allSeenShas();
  let corrupt = 0;
  for (const sha of shas) {
    if (!(await store.verify(sha))) corrupt += 1;
  }
  console.log(`[${GATE_TAG}] ${mode}: downloaded=${downloaded} skippedSeen=${skipped} objects=${shas.length} corrupt=${corrupt}`);

  let pass: boolean;
  if (mode === "first") pass = downloaded > 0 && corrupt === 0;
  else if (mode === "replay") pass = downloaded === 0 && corrupt === 0;
  else pass = downloaded === 0 && skipped > 0 && corrupt === 0;

  console.log(`[${GATE_TAG}] ${pass ? "PASS" : "FAIL"}`);
  await client.disconnect();
  if (!pass) process.exit(1);
}

void run().catch((err: unknown) => {
  console.error(`[${GATE_TAG}] error:`, err instanceof Error ? err.message : String(err));
  process.exit(1);
});