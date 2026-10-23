/**
 * Getting songs that are not in the library yet, on request (owner, 23 Oct:
 * "somebody can search for a song and get something").
 *
 * Search turns Soulseek's file lists into songs: each file's path is read for
 * an artist, a title and an album, files that are the same song are grouped,
 * and each song carries its best copy (lossless first, then a free slot and a
 * short queue). A get downloads that copy, falls back to the usual ranked
 * search when the peer fails, checks the file is audio of the right length,
 * and commits it to the store; the daemon then enriches and publishes, and
 * the song is in everyone's library.
 *
 * One get at a time: the box's line is about 1 MB/s and one peer rarely gives
 * more than 200 KB/s (measured 16 Oct), so two at once only halves both.
 * Jobs live in memory. A restart forgets the queue; the app shows a get as
 * failed and it can be asked for again.
 */
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { mkdir, rename, rm, rmdir, stat, writeFile } from "node:fs/promises";
import { dirname } from "node:path";

import type { DeezerAlbum, DeezerTrack } from "./deezer.js";
import type { Log } from "./logger.js";
import type { ProbeResult } from "./probe.js";
import { acquire, findDownloaded, type AcquireOptions } from "./resource.js";
import { matchAlbum, norm } from "./complete.js";
import { sleep } from "./telegram/ports.js";
import { words, type SlskdApi, type SlskFile, type SlskResponse, type Wanted } from "./soulseek.js";

const AUDIO = /\.(flac|mp3|m4a|ogg|opus|wav|aiff?)$/i;
const LOSSLESS = /\.(flac|wav|aiff?)$/i;

/** One song found out there, with the copy a get would take. */
export interface FoundSong {
  key: string;
  title: string;
  artist: string;
  album: string | null;
  format: string;
  lossless: boolean;
  bitrate: number | null;
  durationMs: number | null;
  sizeBytes: number;
  /** How many people share it: a rough "is this the real thing". */
  peers: number;
  /** The copy a get starts with. */
  username: string;
  filename: string;
  /** Already in the library: the listed song's sha. */
  inLibrary: string | null;
}

/** "Artist/Album (2018)/03 - Title.flac" read as artist, album and title.
 * Paths are whatever people named their folders; this reads the usual
 * shapes and leaves the rest to grouping. */
export function readPath(path: string): { artist: string | null; album: string | null; title: string } {
  const parts = path.split(/[\\/]/).filter((p) => p.length > 0);
  const file = (parts.pop() ?? "").replace(/\.[a-z0-9]{2,4}$/i, "");
  const parent = parts.pop() ?? null;
  const grand = parts.pop() ?? null;
  const tidy = (s: string) =>
    s
      .replace(/[_]+/g, " ")
      .replace(/\s*[[(](19|20)\d\d([-.]\d\d){0,2}[\])]\s*/g, " ")
      .replace(/\s*[[(](flac|mp3|320|v0|web|cd|lossless|24bit|16bit|explicit|clean|dirty|e)[^\])]*[\])]\s*/gi, " ")
      .replace(/\s*\[\d{5,}\]\s*/g, " ")
      .replace(/\s+/g, " ")
      .trim();
  // "03", "[03]", "03.", and disc-track "1-03".
  const trackNo = /^\[?(\d{1,2}[-.])?\d{1,3}\]?\.?$/;
  const year = /^(19|20)\d\d([-.]\d\d){0,2}$/;
  // Folder names that say nothing about who made it.
  const vague = /^(music|musik|downloads?|mp3s?|flac|songs?|audio|various( artists)?|va|unknown( artist)?|new folder|complete|soulseek|share[sd]?)$/i;
  const plausible = (a: string | null | undefined): string | null => {
    const t = (a ?? "").trim();
    if (!t || trackNo.test(t) || year.test(t) || vague.test(t)) return null;
    return t;
  };
  const dropNo = (t: string) => t.replace(/^\[?(\d{1,2}[-.])?\d{1,3}\]?(\s*[-.)_]\s*|\s+)/, "").trim();

  const pieces = tidy(file)
    .split(/\s+-\s+/)
    .map((p) => p.trim())
    .filter((p) => p.length > 0 && !trackNo.test(p) && !year.test(p));
  let title = dropNo(pieces[pieces.length - 1] ?? "");
  let artist: string | null = null;
  let album: string | null = null;
  if (pieces.length >= 2) artist = plausible(dropNo(pieces[0]!));
  if (pieces.length >= 3) album = pieces.slice(1, -1).join(" - ");

  let pArtist: string | null = null;
  let pAlbum: string | null = null;
  if (parent) {
    const pd = tidy(parent).split(/\s+-\s+/);
    if (pd.length >= 2) {
      // "Artist - Album", or "2022 - Album" inside the artist's folder.
      pArtist = plausible(pd[0]) ?? plausible(grand ? tidy(grand) : null);
      pAlbum = pd.slice(1).join(" - ").trim() || null;
    } else {
      pAlbum = plausible(pd[0]) ?? null;
      pArtist = plausible(grand ? tidy(grand) : null);
    }
  }
  album ??= pAlbum;
  // "07 - Last Last - Burna Boy" in Burna Boy's folder: title first.
  if (pArtist && artist && title.toLowerCase() === pArtist.toLowerCase() && artist.toLowerCase() !== title.toLowerCase()) {
    [artist, title] = [title, artist];
  }
  // "ASTROWORLD - SICKO MODE" in a folder named ASTROWORLD: the album, not
  // the artist.
  if (artist && pAlbum && artist.toLowerCase() === pAlbum.toLowerCase()) artist = null;
  artist ??= pArtist;
  if (!title) title = dropNo(tidy(file));
  return { artist, album, title };
}

/** What makes two copies the same song: the lead artist, and the title
 * without its featuring credit or clean/explicit label. Remixes, live takes
 * and the like stay their own songs. */
export function songKey(artist: string, title: string): string {
  const lead = artist.split(/,|\s+(?:feat\.?|ft\.?|featuring|&|x|and)\s+/i)[0] ?? artist;
  const t = title
    .replace(/[([]\s*(?:feat\.?|ft\.?|featuring|with)\s[^)\]]*[)\]]/gi, " ")
    .replace(/\s(?:feat\.?|ft\.?|featuring)\s.*$/i, " ")
    .replace(/[([]\s*(?:explicit|clean|dirty|album version)\s*[)\]]/gi, " ");
  return `${keyOf(lead)}|${keyOf(t)}`;
}

const keyOf = (s: string) => s.toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "");

const VERSION = /\b(live|remix|instrumental|acapella|karaoke|sped|slowed|reverb|cover)\b/i;

/** Soulseek's answers as songs, most-shared first. Only files whose path holds
 * every word asked for; MP3s under 192 kb/s are left out. */
export function groupSongs(
  responses: SlskResponse[],
  query: string,
  inLibrary: (w: Wanted) => string | null,
  limit = 15,
  /** What was typed, when [query] is a shorter retry of it: songs are ranked
   * by how much of this they match before how widely they are shared. */
  asked: string = query,
): FoundSong[] {
  const want = words(query);
  const askedWords = words(asked);
  const has = (ws: Set<string>, w: string) => ws.has(w) || [...ws].some((x) => x.startsWith(w));
  const groups = new Map<
    string,
    { song: Omit<FoundSong, "peers" | "inLibrary">; score: number; peers: Set<string> }
  >();
  for (const r of responses) {
    for (const f of r.files ?? []) {
      if (!AUDIO.test(f.filename)) continue;
      const path = new Set(words(f.filename));
      if (!want.every((w) => path.has(w) || [...path].some((p) => p.startsWith(w)))) continue;
      const lossless = LOSSLESS.test(f.filename);
      if (!lossless && f.bitRate != null && f.bitRate > 0 && f.bitRate < 192) continue;
      const read = readPath(f.filename);
      if (!read.artist || read.title.length === 0) continue;
      // "SICKO MODE - Travis Scott": the asked-for words are all in the
      // "artist" and none in the "title", so the two were the other way round.
      {
        const a = new Set(words(read.artist));
        const t = new Set(words(read.title));
        if (want.length > 0 && want.every((w) => has(a, w)) && !want.some((w) => has(t, w))) {
          [read.artist, read.title] = [read.title, read.artist];
        }
      }
      // Versions the query did not ask for are their own songs, kept apart
      // by title anyway; a "live" folder name does not make a studio take
      // live, so only the title decides.
      // Brackets kept: "SICKO MODE (Skrillex Remix)" is its own song; the
      // featuring credit and a clean/explicit label are not.
      const key = songKey(read.artist, read.title);
      if (key.startsWith("|") || key.endsWith("|")) continue;
      const score =
        (lossless ? 1000 : Math.min(f.bitRate ?? 0, 320)) +
        (r.hasFreeUploadSlot ? 200 : 0) -
        Math.min(r.queueLength, 50) +
        Math.min(r.uploadSpeed / 1e6, 20);
      const g = groups.get(key);
      const song = {
        key,
        title: read.title,
        artist: read.artist,
        album: read.album,
        format: (f.filename.match(AUDIO)?.[1] ?? "").toUpperCase(),
        lossless,
        bitrate: lossless ? null : (f.bitRate ?? null),
        durationMs: f.length ? f.length * 1000 : null,
        sizeBytes: f.size,
        username: r.username,
        filename: f.filename,
      };
      if (!g) {
        groups.set(key, { song, score, peers: new Set([r.username]) });
      } else {
        g.peers.add(r.username);
        if (score > g.score) {
          g.song = song;
          g.score = score;
        }
      }
    }
  }
  // "Rush - Ayra Starr" beside "Ayra Starr - Rush": one song, the right
  // way round being the one more people's files say.
  for (const [key, g] of [...groups.entries()]) {
    const [a, t] = key.split("|");
    const flipped = groups.get(`${t}|${a}`);
    if (!flipped || flipped === g || !groups.has(key)) continue;
    const [keep, drop, dropKey] = flipped.peers.size >= g.peers.size ? [flipped, g, key] : [g, flipped, `${t}|${a}`];
    for (const p of drop.peers) keep.peers.add(p);
    groups.delete(dropKey);
  }
  const askedForVersion = VERSION.test(asked);
  const relevance = (s: { artist: string; title: string }) => {
    const ws = new Set(words(`${s.artist} ${s.title}`));
    return askedWords.filter((w) => has(ws, w)).length;
  };
  return [...groups.values()]
    .map((g) => ({
      ...g.song,
      peers: g.peers.size,
      inLibrary: inLibrary({ artist: g.song.artist, title: g.song.title, durationMs: g.song.durationMs }),
    }))
    .sort(
      (a, b) =>
        // Most of what was typed first: a shorter retry finds other songs too.
        relevance(b) - relevance(a) ||
        // The plain song before its remixes, unless a remix was asked for.
        Number(!askedForVersion && VERSION.test(a.title)) - Number(!askedForVersion && VERSION.test(b.title)) ||
        b.peers - a.peers ||
        Number(b.lossless) - Number(a.lossless),
    )
    .slice(0, limit);
}

/** Whether a found song holds every word of [query] (a prefix will do) in
 * its artist, title or album. */
export function holdsAll(query: string, s: { artist: string; title: string; album: string | null }): boolean {
  const ws = new Set(words(`${s.artist} ${s.title} ${s.album ?? ""}`));
  return words(query).every((w) => ws.has(w) || [...ws].some((x) => x.startsWith(w)));
}

/** The query as typed, then shorter forms of it for when Soulseek answers
 * nothing: without its first word, then its last two. */
export function queryVariants(q: string): string[] {
  const w = q.split(/\s+/).filter(Boolean);
  const out = [w.join(" ")];
  // Without the first word (often the artist, which the server may refuse
  // to search for at all), then the last two, then without the last word.
  if (w.length >= 2) out.push(w.slice(1).join(" "));
  if (w.length >= 4) out.push(w.slice(-2).join(" "));
  if (w.length >= 2) out.push(w.slice(0, -1).join(" "));
  return [...new Set(out)].filter((v) => v.length >= 4).slice(0, 4);
}

export type JobState = "queued" | "searching" | "downloading" | "checking" | "done" | "failed" | "notFound";

export interface GetJob {
  id: string;
  title: string;
  artist: string;
  album: string | null;
  /** Release this get fills in, when it came from "Finish the record". */
  release: string | null;
  state: JobState;
  /** 0..1 while downloading. */
  progress: number | null;
  sha: string | null;
  at: string;
  /** Who asked, by account name ("Dennis"); null when not known. */
  by?: string | null;
  /** Place in the line while queued: 1 is next. */
  position?: number | null;
}

export interface GetRequest {
  title: string;
  artist: string;
  album?: string | null;
  durationMs?: number | null;
  release?: string | null;
  /** Who asked, by account name. */
  by?: string | null;
  /** The copy picked in search, tried first. */
  username?: string | null;
  filename?: string | null;
  size?: number | null;
}

export interface TracklistEntry {
  title: string;
  artist: string;
  durationMs: number | null;
  trackNumber: number | null;
  discNumber: number | null;
  /** The listed song this is, when the library has it. */
  have: string | null;
}

export interface GetterDeps {
  api: SlskdApi;
  downloadsDir: string;
  probe: (path: string, size: number) => Promise<ProbeResult>;
  commit: (path: string, size: number) => Promise<string>;
  inLibrary: (w: Wanted) => string | null;
  /** Enrich and publish, so the song reaches the apps. */
  afterCommit: () => Promise<void>;
  deezer: {
    searchAlbumCandidates(artist: string, album: string): Promise<DeezerAlbum[]>;
    albumTracks(id: number): Promise<DeezerTrack[]>;
  };
  /** A release as the manifest has it, by id. */
  release: (id: string) => { id: string; title: string; artist: string; trackShas: string[]; totalTracks: number | null } | null;
  log: Log;
  /** True while a background Soulseek pass runs: it clears the downloads
   * folder when it starts, so a get waits rather than lose its file. */
  passRunning?: () => boolean;
  /** Gets per day, on top of the background passes' own cap. */
  dailyCap?: number;
  acquireOptions?: AcquireOptions;
  now?: () => Date;
  /** Where the line is kept, so a restart picks it up again instead of
   * dropping everyone's waiting songs. None: kept in memory only. */
  statePath?: string;
  /** Ten-second waits for Soulseek to log in before a get gives up. */
  loginWaits?: number;
}

interface Saved {
  jobs: GetJob[];
  requests: Array<[string, GetRequest]>;
}

const UNFINISHED: JobState[] = ["queued", "searching", "downloading", "checking"];

export class Getter {
  private readonly jobs: GetJob[] = [];
  private readonly requests = new Map<string, GetRequest>();
  private readonly searchCache = new Map<string, { at: number; songs: FoundSong[] }>();
  private readonly tracklists = new Map<string, { at: number; tracks: Array<Omit<TracklistEntry, "have">> }>();
  private running = false;
  private day = "";
  private today = 0;

  private saving: Promise<void> = Promise.resolve();

  constructor(private readonly deps: GetterDeps) {
    this.restore();
  }

  /** The line as it was when the daemon stopped. A get cut off mid-way goes
   * back in line: its file, if any, was half a file. */
  private restore(): void {
    const path = this.deps.statePath;
    if (!path) return;
    let saved: Saved;
    try {
      saved = JSON.parse(readFileSync(path, "utf8")) as Saved;
    } catch {
      return;
    }
    const requests = new Map(saved.requests ?? []);
    let resumed = 0;
    for (const j of saved.jobs ?? []) {
      if (UNFINISHED.includes(j.state)) {
        const req = requests.get(j.id);
        if (!req) continue;
        j.state = "queued";
        j.progress = null;
        this.requests.set(j.id, req);
        resumed += 1;
      }
      this.jobs.push(j);
    }
    if (resumed > 0) {
      this.deps.log.info({ event: "GETS_RESUMED", count: resumed });
      void this.drain();
    }
  }

  /** Writes the line down. Serialised, and atomic (temp file, rename), so a
   * crash mid-write leaves the last good copy. */
  private persist(): void {
    const path = this.deps.statePath;
    if (!path) return;
    const since = this.now().getTime() - 24 * 3600_000;
    const body: Saved = {
      jobs: this.jobs.filter((j) => Date.parse(j.at) >= since || UNFINISHED.includes(j.state)),
      requests: [...this.requests.entries()],
    };
    const text = JSON.stringify(body);
    this.saving = this.saving
      .then(async () => {
        await mkdir(dirname(path), { recursive: true });
        await writeFile(`${path}.tmp`, text);
        await rename(`${path}.tmp`, path);
      })
      .catch((e) => this.deps.log.warn({ event: "GETS_SAVE_FAILED", err: String(e) }));
  }

  /** Waits for the last save; for tests and shutdown. */
  flushed(): Promise<void> {
    return this.saving;
  }

  /** A get is under way: the background pass waits for it. */
  get busy(): boolean {
    return this.running;
  }

  /** Someone is waiting on a get: the background pass stops between songs. */
  get waiting(): boolean {
    return this.jobs.some((j) => j.state === "queued");
  }

  private now(): Date {
    return this.deps.now?.() ?? new Date();
  }

  async search(query: string): Promise<FoundSong[]> {
    const q = query.trim().toLowerCase();
    const hit = this.searchCache.get(q);
    if (hit && Date.now() - hit.at < 10 * 60_000) {
      // The library may have gained some since.
      return hit.songs.map((s) => ({
        ...s,
        inLibrary: this.deps.inLibrary({ artist: s.artist, title: s.title, durationMs: s.durationMs }),
      }));
    }
    if (!(await this.deps.api.loggedIn())) throw new Error("soulseek offline");
    // Soulseek drops some phrases outright (16 Oct: "kendrick lamar" got
    // nothing, "kendrick gnx" 300). When the whole query gets no answer,
    // ask again without the first word, then with the last two.
    let songs: FoundSong[] = [];
    for (const v of queryVariants(q)) {
      songs = groupSongs(await this.deps.api.search(v, 8_000), v, this.deps.inLibrary, 15, q);
      // A shorter ask finds other songs too. Only those that still hold
      // every word typed count: "skyte in need" asked as "in need" found
      // INXS and Stevie Wonder, which is worse than saying nothing is there.
      if (v !== q) songs = songs.filter((s) => holdsAll(q, s));
      if (songs.length > 0) break;
    }
    // Nothing found is not remembered: it is as often the network or the
    // server's refusal as the song being absent, and asking again is cheap.
    if (songs.length > 0) this.searchCache.set(q, { at: Date.now(), songs });
    if (this.searchCache.size > 50) {
      const oldest = [...this.searchCache.entries()].sort((a, b) => a[1].at - b[1].at)[0]?.[0];
      if (oldest) this.searchCache.delete(oldest);
    }
    return songs;
  }

  /** The last day's gets, newest first. */
  list(): GetJob[] {
    const since = this.now().getTime() - 24 * 3600_000;
    // The one under way counts as first, so the next waiting song is 2nd in
    // line: what the person sees is how many songs come before theirs.
    let place = this.jobs.some((j) => ["searching", "downloading", "checking"].includes(j.state)) ? 1 : 0;
    const out: GetJob[] = [];
    for (const j of this.jobs) {
      const position = j.state === "queued" ? ++place : null;
      if (Date.parse(j.at) >= since || j.state === "queued") out.push({ ...j, position });
    }
    return out.reverse();
  }

  /** Takes a waiting song out of the line. Only one that has not started:
   * a download under way finishes. */
  cancel(id: string): boolean {
    const j = this.jobs.find((x) => x.id === id);
    if (!j || j.state !== "queued") return false;
    j.state = "failed";
    this.requests.delete(id);
    this.persist();
    return true;
  }

  get(req: GetRequest): GetJob {
    // Asked twice (two taps, two phones): one job.
    const same = this.jobs.find(
      (j) =>
        norm(j.artist) === norm(req.artist) &&
        norm(j.title) === norm(req.title) &&
        !["failed", "notFound"].includes(j.state),
    );
    if (same) return same;
    const job: GetJob = {
      id: randomUUID(),
      title: req.title,
      artist: req.artist,
      album: req.album ?? null,
      release: req.release ?? null,
      state: "queued",
      progress: null,
      sha: null,
      at: this.now().toISOString(),
      by: req.by ?? null,
    };
    const have = this.deps.inLibrary({ artist: req.artist, title: req.title, durationMs: req.durationMs ?? null });
    if (have) {
      job.state = "done";
      job.sha = have;
    } else {
      this.requests.set(job.id, req);
    }
    this.jobs.push(job);
    if (this.jobs.length > 300) this.jobs.splice(0, this.jobs.length - 300);
    this.persist();
    void this.drain();
    return job;
  }

  /** An album's full track list (Deezer), each marked with the song the
   * library has for it. Null when Deezer does not know the album. */
  async tracklist(releaseId: string): Promise<TracklistEntry[] | null> {
    const r = this.deps.release(releaseId);
    if (!r) return null;
    let cached = this.tracklists.get(releaseId);
    if (!cached || Date.now() - cached.at > 24 * 3600_000) {
      const match = matchAlbum(
        { id: r.id, title: r.title, artist: r.artist, owned: r.trackShas.length, total: r.totalTracks ?? 0 },
        await this.deps.deezer.searchAlbumCandidates(r.artist, r.title),
      );
      if (!match) return null;
      const tracks = await this.deps.deezer.albumTracks(match.id);
      // A very different count is another edition: do not guess.
      if (r.totalTracks != null && Math.abs(tracks.length - r.totalTracks) > 3) return null;
      cached = {
        at: Date.now(),
        tracks: tracks.map((t) => ({
          title: t.title,
          artist: t.artist || r.artist,
          durationMs: t.durationMs || null,
          trackNumber: t.trackNumber,
          discNumber: t.discNumber,
        })),
      };
      this.tracklists.set(releaseId, cached);
    }
    return cached.tracks.map((t) => ({
      ...t,
      have: this.deps.inLibrary({ artist: t.artist, title: t.title, durationMs: t.durationMs }),
    }));
  }

  /** Queues every song of an album the library lacks. */
  async complete(releaseId: string, by: string | null = null): Promise<GetJob[]> {
    const list = await this.tracklist(releaseId);
    const r = this.deps.release(releaseId);
    if (!list || !r) return [];
    return list
      .filter((t) => !t.have)
      .map((t) =>
        this.get({ title: t.title, artist: t.artist, album: r.title, durationMs: t.durationMs, release: releaseId, by }),
      );
  }

  private async drain(): Promise<void> {
    if (this.running) return;
    this.running = true;
    try {
      for (;;) {
        const job = this.jobs.find((j) => j.state === "queued");
        if (!job) return;
        while (this.deps.passRunning?.()) await sleep(5000);
        this.persist();
        await this.run(job).catch((e) => {
          this.deps.log.warn({ event: "GET_FAILED", err: String(e) });
          job.state = "failed";
        });
        this.requests.delete(job.id);
        this.persist();
      }
    } finally {
      this.running = false;
    }
  }

  private async run(job: GetJob): Promise<void> {
    const req = this.requests.get(job.id);
    if (!req) {
      job.state = "failed";
      return;
    }
    const day = this.now().toISOString().slice(0, 10);
    if (day !== this.day) {
      this.day = day;
      this.today = 0;
    }
    if (this.today >= (this.deps.dailyCap ?? 100)) {
      this.deps.log.info({ event: "GET_DAILY_CAP" });
      job.state = "failed";
      return;
    }
    const w: Wanted = { artist: req.artist, title: req.title, album: req.album ?? null, durationMs: req.durationMs ?? null };
    // Got by another job, or arrived from Telegram, while this one waited.
    const already = this.deps.inLibrary(w);
    if (already) {
      job.state = "done";
      job.sha = already;
      return;
    }
    // Soulseek is often still logging in just after a restart, which is
    // exactly when a resumed line starts: give it a couple of minutes.
    let online = await this.deps.api.loggedIn().catch(() => false);
    for (let i = 0; !online && i < (this.deps.loginWaits ?? 12); i++) {
      await sleep(10_000);
      online = await this.deps.api.loggedIn().catch(() => false);
    }
    if (!online) {
      job.state = "failed";
      return;
    }
    this.today += 1;
    await mkdir(this.deps.downloadsDir, { recursive: true });

    let path: string | null = null;
    if (req.username && req.filename && req.size) {
      job.state = "downloading";
      path = await this.fromPeer(job, req.username, { filename: req.filename, size: req.size });
    }
    if (!path) {
      job.state = "searching";
      job.progress = null;
      const got = await acquire(this.deps.api, w, this.deps.downloadsDir, this.deps.log, this.deps.acquireOptions);
      path = got?.path ?? null;
    }
    if (!path) {
      job.state = "notFound";
      return;
    }
    job.state = "checking";
    const size = (await stat(path)).size;
    let checked: ProbeResult | null = null;
    try {
      checked = await this.deps.probe(path, size);
    } catch {
      checked = null;
    }
    const ok =
      checked?.codec != null &&
      checked.durationMs != null &&
      (w.durationMs == null || Math.abs(checked.durationMs - w.durationMs) <= 5000);
    if (!ok) {
      this.deps.log.warn({ event: "GET_REJECTED", durationMs: checked?.durationMs ?? null });
      await rm(path, { force: true });
      await rmdir(dirname(path)).catch(() => undefined);
      job.state = "failed";
      return;
    }
    job.sha = await this.deps.commit(path, size);
    await rmdir(dirname(path)).catch(() => undefined);
    await this.deps.afterCommit().catch((e) => this.deps.log.warn({ event: "GET_PUBLISH_FAILED", err: String(e) }));
    job.state = "done";
    job.progress = 1;
    this.deps.log.info({ event: "GET_DONE", lossless: LOSSLESS.test(path) });
  }

  /** The picked copy, with progress; null when the peer refuses or crawls. */
  private async fromPeer(job: GetJob, username: string, file: SlskFile): Promise<string | null> {
    const api = this.deps.api;
    const started = Date.now();
    const judgeAfter = this.deps.acquireOptions?.judgeAfterMs ?? 25_000;
    const minRate = this.deps.acquireOptions?.minBytesPerSec ?? 40 * 1024;
    const timeout = this.deps.acquireOptions?.timeoutMs ?? 10 * 60_000;
    const poll = this.deps.acquireOptions?.pollMs ?? 2000;
    try {
      await api.download(username, file);
    } catch {
      return null;
    }
    let judged = false;
    while (Date.now() - started < timeout) {
      await sleep(poll);
      const t = await api.transfer(username, file.filename).catch(() => null);
      if (!t) continue;
      job.progress = Math.max(0, Math.min(1, (t.percentComplete ?? 0) / 100));
      if (t.state.includes("Succeeded")) {
        for (let i = 0; i < 20; i++) {
          const p = await findDownloaded(this.deps.downloadsDir, file.filename);
          if (p) return p;
          await sleep(1000);
        }
        return null;
      }
      if (/Errored|Rejected|TimedOut|Cancelled|Aborted/.test(t.state)) break;
      const elapsed = Date.now() - started;
      if (!judged && elapsed >= judgeAfter) {
        judged = true;
        if ((t.bytesTransferred ?? 0) / (elapsed / 1000) < minRate) break;
      }
    }
    await api.cancel(username, file.filename);
    return null;
  }
}
