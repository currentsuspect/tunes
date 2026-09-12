import { readFileSync, writeFileSync } from "node:fs";
import { mkdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { createInterface } from "node:readline/promises";
import { stdin, stdout } from "node:process";
import { TelegramClient } from "teleproto";
import { StringSession } from "teleproto/sessions/index.js";
import { loadEnv } from "../src/env.js";

async function ask(q: string): Promise<string> {
  const rl = createInterface({ input: stdin, output: stdout });
  try {
    return (await rl.question(q)).trim();
  } finally {
    rl.close();
  }
}

async function main(): Promise<void> {
  const env = loadEnv();

  // Optional destination. Without it this overwrites the session tunesd is
  // serving from, which is correct for a first login and catastrophic while
  // the daemon is running: a concurrent MTProto connection on the same auth
  // key can invalidate it, and the box stops serving for everyone.
  //
  //   npx tsx scripts/login.ts                      -> data/session (production)
  //   npx tsx scripts/login.ts data/session-spike   -> an isolated second session
  //
  // A second session is the same account with an independent key, so an
  // experiment against it cannot damage the running service.
  const target = process.argv[2]?.trim();
  const sessionFile = target && target.length > 0 ? target : env.sessionFile;
  if (target) {
    console.log(`Writing to ${sessionFile} — the production session is untouched.`);
  }
  const client = new TelegramClient(new StringSession(""), env.apiId, env.apiHash, {
    connectionRetries: 3,
  });

  await client.start({
    phoneNumber: () => ask("Phone number (international format, e.g. +2547…): "),
    phoneCode: () => ask("Login code Telegram sent you: "),
    password: () => ask("2FA password (if enabled): "),
    onError: (err: unknown) => {
      console.error("Login failed:", err instanceof Error ? err.message : String(err));
      process.exit(1);
    },
  });

  const session = client.session.save();
  await mkdir(dirname(sessionFile), { recursive: true });
  writeFileSync(sessionFile, String(session), { mode: 0o600 });
  console.log(`Session written to ${sessionFile} (gitignored, mode 600).`);
  console.log("It is a credential for this account: never paste it anywhere.");

  const me = await client.getMe();
  console.log(`You: ${me.firstName}${me.username ? ` (@${me.username})` : ""} (id ${me.id})`);
  await client.disconnect();
}

void main().catch((err: unknown) => {
  console.error("Unexpected error:", err);
  process.exit(1);
});