import { readFileSync } from "node:fs";
import { join } from "node:path";
import { loadEnv } from "../src/env.js";
import { makeLogger } from "../src/logger.js";
import { State } from "../src/state.js";
import { MtprotoClient } from "../src/telegram/mtproto.js";

async function main(): Promise<void> {
  const env = loadEnv();
  const log = makeLogger(env.logLevel);
  const chatRaw = process.env["TUNESD_CHANNELS"];
  if (!chatRaw) throw new Error("TUNESD_CHANNELS required");
  const eq = chatRaw.indexOf("=");
  const chatId = Number(eq > 0 ? chatRaw.slice(0, eq) : chatRaw);
  if (!Number.isFinite(chatId)) throw new Error(`invalid TUNESD_CHANNELS: ${chatRaw}`);

  const state = await new State(join(env.dataDir, "state.json")).load();
  const client = new MtprotoClient(
    { apiId: env.apiId, apiHash: env.apiHash, session: readFileSync(env.sessionFile, "utf8").trim() },
    log
  );

  let filled = 0;
  let preview = 0;
  for await (const ref of client.iterAudioMessages(chatId, {})) {
    const meta = state.seenMeta(String(chatId), ref.messageId);
    if (!meta || (meta.caption !== null && meta.fileName !== null)) continue;
    if (meta.caption === null && ref.caption === null && meta.fileName === null && ref.fileName === null) continue;
    state.markSeen(String(chatId), ref.messageId, meta.sha, ref.caption, ref.fileName);
    filled += 1;
    if (preview < 5) {
      console.log(`backfilled msg=${ref.messageId} sha=${meta.sha.slice(0, 8)} caption=${JSON.stringify(ref.caption)} fileName=${JSON.stringify(ref.fileName)}`);
      preview += 1;
    }
  }
  await state.save();
  console.log(`backfilled=${filled} entries`);
  await client.disconnect();
}

void main().catch((e: unknown) => {
  console.error(String(e));
  process.exit(1);
});