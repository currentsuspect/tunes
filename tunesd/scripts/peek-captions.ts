import { readFileSync } from "node:fs";
import { loadEnv } from "../src/env.js";
import { makeLogger } from "../src/logger.js";
import { MtprotoClient } from "../src/telegram/mtproto.js";

async function main(): Promise<void> {
  const env = loadEnv();
  const log = makeLogger("error");
  const client = new MtprotoClient(
    { apiId: env.apiId, apiHash: env.apiHash, session: readFileSync(env.sessionFile, "utf8").trim() },
    log
  );
  for await (const ref of client.iterAudioMessages(-5381888073, {})) {
    console.log(JSON.stringify({ msg: ref.messageId, caption: ref.caption, fileName: ref.fileName, size: ref.size, mime: ref.mime }));
  }
  await client.disconnect();
}
void main().catch((e: unknown) => { console.error(String(e)); process.exit(1); });
