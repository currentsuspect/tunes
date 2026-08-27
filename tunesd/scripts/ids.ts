import { loadEnv } from "../src/env.js";
import { makeLogger } from "../src/logger.js";
import { MtprotoClient } from "../src/telegram/mtproto.js";
import { readFileSync } from "node:fs";

async function main(): Promise<void> {
  const env = loadEnv();
  const log = makeLogger(env.logLevel);
  const client = new MtprotoClient(
    { apiId: env.apiId, apiHash: env.apiHash, session: readFileSync(env.sessionFile, "utf8").trim() },
    log
  );

  const me = await client.getMe();
  console.log(`You: ${me.firstName}${me.username ? ` (@${me.username})` : ""} (id ${me.id})`);

  const dialogs = await client.listDialogs();
  console.log("Dialogs:");
  for (const d of dialogs.sort((a, b) => a.title.localeCompare(b.title))) {
    console.log(`  ${d.type.padEnd(8)} ${String(d.id).padEnd(14)} ${d.title}`);
  }
  await client.disconnect();
}

void main().catch((err: unknown) => {
  console.error(String(err));
  process.exit(1);
});