import { readFileSync } from "node:fs";
import { TelegramClient } from "teleproto";
import { StringSession } from "teleproto/sessions/index.js";
import { loadEnv } from "../src/env.js";

async function main(): Promise<void> {
  const env = loadEnv();
  const session = readFileSync(env.sessionFile, "utf8").trim();
  const client = new TelegramClient(new StringSession(session), env.apiId, env.apiHash, {
    connectionRetries: 3,
  });
  await client.connect();
  let count = 0;
  for await (const d of client.iterDialogs({ limit: 500 })) {
    count += 1;
    const t = (d.title ?? "").toLowerCase();
    if (t.includes("tune") || t.includes("stream")) {
      console.log("FOUND:", d.id, JSON.stringify(d.title));
    }
  }
  console.log("total dialogs iterated:", count);
  await client.disconnect();
}

void main().catch((e: unknown) => {
  console.error(String(e));
  process.exit(1);
});