#!/usr/bin/env node
/**
 * Authorises a SECOND Telegram session for the same account and writes it to
 * a file. Interactive, run by a human, once.
 *
 * Named e2e-* and never run in CI (AGENTS.md §6): it needs a phone, a login
 * code, and a person to type them.
 *
 * Why a second session rather than the one tunesd already has: tunesd is
 * serving the phone from that auth key right now. Opening a concurrent MTProto
 * connection on the same key risks invalidating it, which takes the daemon
 * down for everyone using it. A separate session is the same account with an
 * independent key, so the experiment cannot damage the running service.
 *
 *   node scripts/e2e-second-session.mjs
 *
 * Reads TUNESD_API_ID / TUNESD_API_HASH from tunesd/.env. Writes the session
 * to data/session-spike, mode 600. That file is a credential for your Telegram
 * account: it is gitignored, it must not be pasted into a chat or a PR, and it
 * should be revoked from Telegram (Settings -> Devices) when the spike is done.
 */
import { readFileSync, writeFileSync, chmodSync } from "node:fs";
import { createInterface } from "node:readline/promises";
import { stdin, stdout } from "node:process";

import { TelegramClient } from "teleproto";
import { StringSession } from "teleproto/sessions/index.js";

const env = Object.fromEntries(
  readFileSync(new URL("../.env", import.meta.url), "utf8")
    .split("\n")
    .filter((l) => l.includes("=") && !l.trimStart().startsWith("#"))
    .map((l) => {
      const i = l.indexOf("=");
      return [l.slice(0, i).trim(), l.slice(i + 1).trim()];
    }),
);

const apiId = Number(env.TUNESD_API_ID);
const apiHash = env.TUNESD_API_HASH;
if (!apiId || !apiHash) {
  console.error("TUNESD_API_ID / TUNESD_API_HASH missing from tunesd/.env");
  process.exit(1);
}

const rl = createInterface({ input: stdin, output: stdout });
const ask = (q) => rl.question(q);

// Empty StringSession => a fresh authorisation, independent of data/session.
const client = new TelegramClient(new StringSession(""), apiId, apiHash, {
  connectionRetries: 3,
});

await client.start({
  phoneNumber: () => ask("phone number (with country code): "),
  phoneCode: () => ask("login code Telegram just sent: "),
  password: () => ask("2FA password (blank if none): "),
  onError: (e) => console.error("login error:", e?.message ?? e),
});

const out = new URL("../data/session-spike", import.meta.url);
writeFileSync(out, client.session.save(), { mode: 0o600 });
chmodSync(out, 0o600);

const me = await client.getMe();
console.log(`\n  authorised as: ${me?.username ?? me?.firstName ?? "unknown"}`);
console.log(`  session written to: tunesd/data/session-spike (mode 600)`);
console.log(`  this is a credential — do not paste it anywhere.`);
console.log(`  revoke it later in Telegram: Settings -> Devices.\n`);

await client.disconnect();
await rl.close();
process.exit(0);
