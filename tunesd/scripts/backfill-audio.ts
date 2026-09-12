import { mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { publishAudioFile, selectAudioToBackfill } from "../src/cloudpublish.js";
import { loadEnv } from "../src/env.js";
import { makeLogger } from "../src/logger.js";
import { State } from "../src/state.js";

const SHA_RE = /^[0-9a-f]{64}$/;
const MAX_BYTES = 64 * 1024 * 1024;

function usage(): never {
  console.error(
    "usage: npx tsx scripts/backfill-audio.ts [--extra-dir DIR]... [--priority-file PATH] [--dry-run]"
  );
  process.exit(1);
}

function indexDir(dir: string, into: Map<string, string>): void {
  let entries: string[];
  try {
    entries = readdirSync(dir);
  } catch {
    return;
  }
  for (const e of entries) {
    const p = join(dir, e);
    let st;
    try {
      st = statSync(p);
    } catch {
      continue;
    }
    if (st.isDirectory()) {
      indexDir(p, into);
    } else if (st.isFile() && SHA_RE.test(e) && !into.has(e)) {
      into.set(e, p);
    }
  }
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const extraDirs: string[] = [];
  let priorityFile: string | null = null;
  let dryRun = false;
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === "--extra-dir" && i + 1 < args.length) extraDirs.push(args[++i]!);
    else if (a === "--priority-file" && i + 1 < args.length) priorityFile = args[++i]!;
    else if (a === "--dry-run") dryRun = true;
    else usage();
  }

  const env = loadEnv();
  const log = makeLogger(env.logLevel);
  if (!env.publishUrl || !env.publishKey) {
    throw new Error("INTERNAL_PUBLISH_URL and INTERNAL_PUBLISH_KEY required");
  }
  const audioBase = env.publishUrl.replace(/\/publish\/?$/, "/audio");
  if (!/\/audio$/.test(audioBase)) throw new Error(`cannot derive audio route from ${env.publishUrl}`);

  const state = await new State(join(env.dataDir, "state.json")).load();
  const files = new Map<string, string>();
  indexDir(join(env.dataDir, "objects"), files);
  for (const d of extraDirs) indexDir(d, files);

  const seen = state.allSeenShas();
  let ordered = [...seen].sort();
  if (priorityFile) {
    const first = readFileSync(priorityFile, "utf8")
      .split("\n")
      .map((l) => l.trim().split(/\s+/)[0] ?? "")
      .filter((s) => SHA_RE.test(s));
    const rest = new Set(seen);
    for (const s of first) rest.delete(s);
    ordered = [...first, ...[...rest].sort()];
  }

  const ledgerFile = join(env.dataDir, "audio-published.json");
  const ledger: Record<string, string> = {};
  try {
    const raw = JSON.parse(readFileSync(ledgerFile, "utf8")) as { audio: Record<string, string> };
    for (const [k, v] of Object.entries(raw.audio ?? {})) ledger[k] = v;
  } catch {
    // fresh start
  }
  const saveLedger = () => {
    mkdirSync(env.dataDir, { recursive: true });
    writeFileSync(ledgerFile, JSON.stringify({ audio: ledger }, null, 1));
  };

  const due = selectAudioToBackfill(ordered, ledger, (sha) => files.has(sha));
  const missing = ordered.filter((s) => !files.has(s) && ledger[s] === undefined);
  console.log(`shas=${ordered.length} due=${due.length} no-local-copy=${missing.length} already=${ordered.length - due.length - missing.length}`);
  if (dryRun) return;

  let done = 0;
  let failed = 0;
  let bytes = 0;
  for (const sha of due) {
    const path = files.get(sha);
    if (!path) continue;
    let buf: Buffer;
    try {
      const st = statSync(path);
      if (st.size > MAX_BYTES) {
        log.warn({ event: "AUDIO_BACKFILL_OVERSIZE", bytes: st.size });
        continue;
      }
      buf = readFileSync(path);
    } catch (e) {
      log.warn({ event: "AUDIO_BACKFILL_UNREADABLE", err: String(e).slice(0, 120) });
      failed += 1;
      continue;
    }
    const ok = await publishAudioFile({
      baseUrl: audioBase,
      key: env.publishKey,
      sha,
      bytes: buf,
      log,
      timeoutMs: 300_000,
    });
    if (!ok) {
      failed += 1;
      continue;
    }
    ledger[sha] = new Date().toISOString();
    done += 1;
    bytes += buf.length;
    if (done % 10 === 0) saveLedger();
    if (done % 25 === 0) console.log(`backfilled=${done} failed=${failed} mb=${Math.round(bytes / 1048576)}`);
  }
  saveLedger();
  console.log(`done backfilled=${done} failed=${failed} mb=${Math.round(bytes / 1048576)}`);
}

void main().catch((err: unknown) => {
  console.error(String(err));
  process.exit(1);
});
