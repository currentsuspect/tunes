import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { randomUUID } from "node:crypto";

import { sleep } from "./telegram/ports.js";

/** Where slskd listens and the key tunesd uses. From the environment, else
 * ~/.config/tunes/slskd.env (written when slskd was installed; never in the
 * repo). Null when neither exists: the provider is simply off. */
export function slskdConfig(
  env: NodeJS.ProcessEnv = process.env,
  file: string = join(homedir(), ".config", "tunes", "slskd.env")
): { url: string; apiKey: string } | null {
  let url = env.SLSKD_URL;
  let apiKey = env.SLSKD_API_KEY;
  if (!url || !apiKey) {
    try {
      for (const line of readFileSync(file, "utf8").split("\n")) {
        const i = line.indexOf("=");
        if (i < 0) continue;
        const k = line.slice(0, i).trim();
        const v = line.slice(i + 1).trim();
        if (k === "SLSKD_URL") url ??= v;
        if (k === "SLSKD_API_KEY") apiKey ??= v;
      }
    } catch {
      return null;
    }
  }
  return url && apiKey ? { url: url.replace(/\/$/, ""), apiKey } : null;
}

export interface SlskFile {
  filename: string;
  size: number;
  bitRate?: number;
  length?: number;
}

export interface SlskResponse {
  username: string;
  hasFreeUploadSlot: boolean;
  uploadSpeed: number;
  queueLength: number;
  files: SlskFile[];
}

export interface SlskTransfer {
  state: string;
  percentComplete: number;
  bytesTransferred: number;
}

/** The slice of slskd's REST API the provider uses. */
export class SlskdApi {
  constructor(
    private readonly base: string,
    private readonly apiKey: string,
    private readonly fetchImpl: typeof fetch = fetch
  ) {}

  private async call<T>(method: string, path: string, body?: unknown): Promise<T> {
    const res = await this.fetchImpl(`${this.base}/api/v0${path}`, {
      method,
      headers: { "X-API-Key": this.apiKey, "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(30_000),
    });
    if (!res.ok) throw new Error(`slskd ${method} ${path}: ${res.status}`);
    const text = await res.text();
    return (text ? JSON.parse(text) : null) as T;
  }

  async loggedIn(): Promise<boolean> {
    try {
      const s = await this.call<{ isLoggedIn?: boolean }>("GET", "/server");
      return s?.isLoggedIn === true;
    } catch {
      return false;
    }
  }

  /** One search, waited out. slskd gathers answers for [timeoutMs]. */
  async search(text: string, timeoutMs = 12_000): Promise<SlskResponse[]> {
    const id = randomUUID();
    await this.call("POST", "/searches", { id, searchText: text, searchTimeout: timeoutMs, responseLimit: 300 });
    const deadline = Date.now() + timeoutMs + 20_000;
    while (Date.now() < deadline) {
      const s = await this.call<{ isComplete?: boolean }>("GET", `/searches/${id}`);
      if (s?.isComplete) break;
      await sleep(1000);
    }
    const out = await this.call<SlskResponse[]>("GET", `/searches/${id}/responses`);
    await this.call("DELETE", `/searches/${id}`).catch(() => undefined);
    return out ?? [];
  }

  async download(username: string, file: SlskFile): Promise<void> {
    await this.call("POST", `/transfers/downloads/${encodeURIComponent(username)}`, [
      { filename: file.filename, size: file.size },
    ]);
  }

  async transfer(username: string, filename: string): Promise<SlskTransfer | null> {
    const d = await this.call<{ directories?: Array<{ files: Array<SlskTransfer & { filename: string; id: string }> }> }>(
      "GET",
      `/transfers/downloads/${encodeURIComponent(username)}`
    );
    for (const dir of d?.directories ?? []) {
      for (const f of dir.files) if (f.filename === filename) return f;
    }
    return null;
  }

  /** Forgets finished, failed and cancelled transfers. */
  async clearFinished(): Promise<void> {
    await this.call("DELETE", "/transfers/downloads/all/completed");
  }

  /** Cancels and forgets a transfer, so slow peers do not linger. */
  async cancel(username: string, filename: string): Promise<void> {
    const d = await this.call<{ directories?: Array<{ files: Array<{ filename: string; id: string }> }> }>(
      "GET",
      `/transfers/downloads/${encodeURIComponent(username)}`
    ).catch(() => null);
    for (const dir of d?.directories ?? []) {
      for (const f of dir.files) {
        if (f.filename !== filename) continue;
        await this.call("DELETE", `/transfers/downloads/${encodeURIComponent(username)}/${f.id}?remove=true`).catch(
          () => undefined
        );
      }
    }
  }
}

// ---------------------------------------------------------------- matching

/** Lowercased words, accents folded, punctuation dropped. */
export function words(s: string): string[] {
  return s
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/&/g, " and ")
    .split(/[^a-z0-9]+/)
    .filter((w) => w.length > 0);
}

export interface Wanted {
  artist: string;
  title: string;
  album?: string | null;
  durationMs?: number | null;
}

/** Searches to try, best first. Soulseek drops some exact phrases outright
 * (benchmark, 7 Oct: "kendrick lamar" returned nothing, "kendrick gnx" 300),
 * so the artist is also tried in parts and the title alone. */
export function searchVariants(w: Wanted): string[] {
  const artist = words(w.artist.split(/[,;/]| feat\.? | ft\.? | x /i)[0] ?? w.artist);
  const title = words(w.title.replace(/\(.*?\)|\[.*?\]/g, " "));
  const album = w.album ? words(w.album.replace(/\(.*?\)|\[.*?\]/g, " ")) : [];
  const out = [
    [...artist, ...title],
    [artist[0] ?? "", ...title],
    [artist[artist.length - 1] ?? "", ...title],
    // The Soulseek server drops searches naming some artists outright (23
    // Oct: anything with "rihanna" got nothing, "anti" 300), so the album
    // and title, then the title alone. rankCandidates still wants an artist
    // word in the file's path, which keeps other people's songs out.
    album.length > 0 ? [...album, ...title] : [],
    title,
  ]
    .map((ws) => ws.filter(Boolean).join(" "))
    .filter((q) => q.split(" ").length >= 2 || q.length >= 5);
  return [...new Set(out)];
}

const AUDIO = /\.(flac|mp3|m4a|ogg|opus|wav|aiff?)$/i;

export interface Candidate {
  username: string;
  file: SlskFile;
  lossless: boolean;
  free: boolean;
  speed: number;
  queue: number;
  score: number;
}

/** Files that are this song, best first.
 *
 * A file matches when its path holds every title word and some artist word.
 * Ranked: lossless first, then a free slot, then length close to the song's,
 * then advertised speed. Live, remix, instrumental and similar versions are
 * dropped unless the title asks for them.
 */
/** Words in a path that mark a clean (censored) copy. */
const CLEAN = ["clean", "edited", "censored"];

/** How far down a clean copy goes: below any explicit copy, lossy ones
 * included, but still taken when nothing else is shared. Not when the ask
 * names it, or the word is the act's own ("Clean Bandit"). */
export function cleanPenalty(pathWords: Set<string>, asked: Set<string>): number {
  return CLEAN.some((w) => pathWords.has(w) && !asked.has(w)) ? 1500 : 0;
}

export function rankCandidates(responses: SlskResponse[], w: Wanted): Candidate[] {
  const titleWords = words(w.title.replace(/\(.*?\)|\[.*?\]/g, " "));
  const artistWords = words(w.artist).filter((x) => x.length > 1 && x !== "feat" && x !== "ft");
  const wantedAll = new Set(words(w.title));
  const versions = ["live", "remix", "instrumental", "acapella", "karaoke", "edit", "sped", "slowed", "reverb", "cover", "mix"];
  const out: Candidate[] = [];
  for (const r of responses) {
    for (const f of r.files ?? []) {
      if (!AUDIO.test(f.filename)) continue;
      const pathWords = new Set(words(f.filename));
      if (!titleWords.every((t) => pathWords.has(t))) continue;
      if (artistWords.length > 0 && !artistWords.some((a) => pathWords.has(a))) continue;
      if (versions.some((v) => pathWords.has(v) && !wantedAll.has(v))) continue;
      // And the other way: a title that asks for a version needs a file that
      // is one. "Spectacular (Remix)" fetched "Spectacular 2" (23 Oct) because
      // only the words outside the brackets were checked.
      if (versions.some((v) => wantedAll.has(v) && !pathWords.has(v))) continue;
      const lossless = /\.(flac|wav|aiff?)$/i.test(f.filename);
      if (!lossless && f.bitRate != null && f.bitRate > 0 && f.bitRate < 256) continue;
      let lengthPenalty = 0;
      if (w.durationMs && f.length) {
        const diff = Math.abs(f.length - w.durationMs / 1000);
        if (diff > 8) continue;
        lengthPenalty = diff;
      }
      // A clean copy is not the song: Soulseek holds both and the clean one
      // was as likely to win on speed alone.
      const score =
        (lossless ? 1000 : 0) + (r.hasFreeUploadSlot ? 200 : 0) - lengthPenalty * 5 - Math.min(r.queueLength, 50) +
        Math.min(r.uploadSpeed / 1e6, 20) -
        cleanPenalty(pathWords, new Set([...wantedAll, ...words(w.artist)]));
      out.push({
        username: r.username,
        file: f,
        lossless,
        free: r.hasFreeUploadSlot,
        speed: r.uploadSpeed,
        queue: r.queueLength,
        score,
      });
    }
  }
  out.sort((a, b) => b.score - a.score || (a.username < b.username ? -1 : 1));
  // One file per peer: a second copy from the same person fails the same way.
  const seen = new Set<string>();
  return out.filter((c) => (seen.has(c.username) ? false : (seen.add(c.username), true)));
}
