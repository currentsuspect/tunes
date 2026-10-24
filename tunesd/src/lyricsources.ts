/**
 * Lyrics beyond LRCLIB, and the order they are asked in.
 *
 * LRCLIB had 1,905 of 2,509 songs on 24 Oct. A sample of the 556 it lacked
 * found NetEase holding synced lyrics for a third of them and Genius plain
 * lyrics for two thirds. NetEase also carries "YRC" for well-known songs:
 * every word's start and length in milliseconds, which is the exact data a
 * word-timing model learns from. So the order is by timing, not by source:
 *
 *   1. word-timed   (NetEase YRC)
 *   2. line-timed   (LRCLIB, then NetEase LRC)
 *   3. plain words  (LRCLIB plain, then Genius)
 *
 * Each source answers on its own; one being down never marks a song as having
 * no lyrics (see [LyricChain.find]). Lyrics here are for the listener's own
 * library, never redistributed.
 */
import { LyricsUnavailable, kDurationToleranceSec, type LrclibClient, type LyricsCandidate } from "./lyrics.js";

export type LyricTiming = "word" | "line" | "plain";
export type FetchedSource = "lrclib" | "netease" | "genius";

export interface FoundLyrics {
  text: string;
  source: FetchedSource;
  timing: LyricTiming;
  /** The source's own id for the song, for re-picking a bad match. */
  id: string | null;
  /** What the source sent, untouched: kept for training, never shown. */
  raw: unknown;
}

export interface Ours {
  title: string;
  artist: string;
  album: string;
  durationMs: number | null;
}

/** A chain's answer: what it found, and whether every source answered. A
 * miss while a source was down is not "no lyrics exist". */
export interface ChainAnswer {
  found: FoundLyrics | null;
  complete: boolean;
}

// ---------------------------------------------------------------- matching

export function normTitle(s: string): string {
  return s
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/\(.*?\)|\[.*?\]/g, " ")
    .replace(/\s(feat|ft)\.?\s.*$/, " ")
    .replace(/[^a-z0-9]+/g, "");
}

/** The first name on a credit line: "Beyoncé, JAY-Z" -> "beyonce". */
export function leadArtist(s: string): string {
  const first = s.split(/,|;|\/|&|\sx\s|\sfeat\.?\s|\sft\.?\s|\swith\s/i)[0] ?? s;
  return normTitle(first);
}

export function sameSong(
  theirs: { title: string; artists: string[]; durationMs: number | null },
  ours: Ours,
): boolean {
  if (normTitle(theirs.title) !== normTitle(ours.title)) return false;
  const lead = leadArtist(ours.artist);
  if (!theirs.artists.some((a) => leadArtist(a) === lead)) return false;
  if (ours.durationMs == null || theirs.durationMs == null) return true;
  return Math.abs(theirs.durationMs - ours.durationMs) <= kDurationToleranceSec * 1000;
}

// ---------------------------------------------------------------- formats

/** `[mm:ss.xxx]`, minutes unbounded, milliseconds kept: a model learns from
 * the timing, and centiseconds throw a tenth of it away. */
export function stamp(ms: number): string {
  const t = Math.max(0, Math.round(ms));
  const m = Math.floor(t / 60_000);
  const s = Math.floor((t % 60_000) / 1000);
  const f = t % 1000;
  return `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}.${String(f).padStart(3, "0")}`;
}

/** Credit lines NetEase puts above the words: "作词 : …", "Producer : …". */
const CREDIT =
  /^\s*(作词|作曲|编曲|制作人|制作|混音|母带|和声|吉他|贝斯|鼓|录音|监制|出品|发行|词|曲|lyrics?( by)?|written by|composed by|produced by|producer|composer|arranger|mix(ed|ing)?( by)?|master(ed|ing)?( by)?)\s*[:：]/i;

function isCredit(text: string, ours: Ours, atMs: number): boolean {
  if (CREDIT.test(text)) return true;
  // "Beyonce - Irreplaceable" sung at 0:00: the title card, not a lyric.
  if (atMs < 5000 && /\s[-–]\s/.test(text)) {
    const t = normTitle(text);
    if (t.includes(normTitle(ours.title)) && t.includes(leadArtist(ours.artist))) return true;
  }
  return false;
}

interface YrcWord {
  start: number;
  dur: number;
  text: string;
}

/**
 * NetEase YRC to Enhanced LRC with word ends.
 *
 * YRC: `[lineStart,lineDur](wordStart,wordDur,0)word(…)…`, all milliseconds.
 * Out: `[mm:ss.xxx]<start>word<end> <start>word<end>`. A tag straight after a
 * word, before the space, is that word's end. Readers that know only starts
 * skip a tag with no word after it, so nothing older breaks.
 */
export function yrcToLrc(yrc: string, ours: Ours): string | null {
  const out: string[] = [];
  for (const raw of yrc.split("\n")) {
    const line = raw.trim();
    const head = /^\[(\d+),(\d+)\]/.exec(line);
    if (!head) continue; // JSON credit rows start with "{"
    const words: YrcWord[] = [];
    const re = /\((\d+),(\d+),\d+\)([^(]*)/g;
    let m: RegExpExecArray | null;
    while ((m = re.exec(line.slice(head[0].length))) !== null) {
      words.push({ start: Number(m[1]), dur: Number(m[2]), text: m[3] ?? "" });
    }
    const text = words.map((w) => w.text).join("").replace(/\s+/g, " ").trim();
    if (text === "" || isCredit(text, ours, Number(head[1]))) continue;
    // A YRC token carries its own trailing space; tokens without one are
    // syllables of one word ("Irre" "place" "able"), merged into a single
    // timed word here (the syllables stay in the raw archive).
    const parts: string[] = [];
    let cur: { start: number; end: number; text: string } | null = null;
    const flush = () => {
      if (cur && cur.text !== "") parts.push(`<${stamp(cur.start)}>${cur.text}<${stamp(cur.end)}>`);
      cur = null;
    };
    for (const w of words) {
      const t = w.text.trim();
      if (t !== "") {
        if (cur === null) cur = { start: w.start, end: w.start + w.dur, text: t };
        else {
          cur.text += t;
          cur.end = w.start + w.dur;
        }
      }
      if (/\s$/.test(w.text)) flush();
    }
    flush();
    if (parts.length === 0) continue;
    out.push(`[${stamp(Number(head[1]))}]${parts.join(" ")}`);
  }
  return out.length > 0 ? out.join("\n") : null;
}

/** NetEase's line LRC without its credit rows. */
export function cleanNeteaseLrc(lrc: string, ours: Ours): string | null {
  const out: string[] = [];
  for (const raw of lrc.split("\n")) {
    const line = raw.trim();
    if (line === "" || line.startsWith("{")) continue;
    const m = /^((?:\[\d+:\d{1,2}(?:[.:]\d{1,3})?\])+)(.*)$/.exec(line);
    if (!m) continue;
    const text = (m[2] ?? "").trim();
    const first = /\[(\d+):(\d{1,2})/.exec(m[1]!);
    const at = first ? Number(first[1]) * 60_000 + Number(first[2]) * 1000 : 0;
    if (text === "" || isCredit(text, ours, at)) continue;
    out.push(`${m[1]}${text}`);
  }
  // A handful of lines is a credits block or a "no lyrics yet" stub.
  return out.length >= 4 ? out.join("\n") : null;
}

/** The words in a Genius page: every lyrics container, its credits header cut. */
export function geniusLyricsFromHtml(html: string): string | null {
  const parts: string[] = [];
  let from = 0;
  for (;;) {
    const at = html.indexOf('data-lyrics-container="true"', from);
    if (at < 0) break;
    const open = html.lastIndexOf("<div", at);
    const close = matchingDivEnd(html, open);
    if (open < 0 || close < 0) break;
    parts.push(html.slice(html.indexOf(">", at) + 1, close));
    from = close;
  }
  if (parts.length === 0) return null;
  let body = parts.join("<br/>");
  // The header (contributors, "… Lyrics") sits inside the first container.
  for (;;) {
    const at = body.indexOf('data-exclude-from-selection="true"');
    if (at < 0) break;
    const open = body.lastIndexOf("<div", at);
    const close = matchingDivEnd(body, open);
    if (open < 0 || close < 0) break;
    body = body.slice(0, open) + body.slice(close + "</div>".length);
  }
  const text = decodeEntities(
    body
      .replace(/<br\s*\/?>/gi, "\n")
      .replace(/<[^>]+>/g, ""),
  )
    .split("\n")
    .map((l) => l.trim())
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
  return text.length >= 20 ? text : null;
}

/** Index of the `</div>` closing the `<div` at [open], or -1. */
function matchingDivEnd(html: string, open: number): number {
  if (open < 0) return -1;
  let depth = 0;
  const re = /<div\b|<\/div>/g;
  re.lastIndex = open;
  let m: RegExpExecArray | null;
  while ((m = re.exec(html)) !== null) {
    if (m[0] === "</div>") {
      depth -= 1;
      if (depth === 0) return m.index;
    } else {
      depth += 1;
    }
  }
  return -1;
}

function decodeEntities(s: string): string {
  return s
    .replace(/&#x([0-9a-f]+);/gi, (_, h: string) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d: string) => String.fromCodePoint(Number(d)))
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&");
}

// ---------------------------------------------------------------- clients

const BROWSER_UA =
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36";

async function getJson(fetcher: typeof fetch, url: string, headers: Record<string, string>): Promise<unknown> {
  let res: Response;
  try {
    res = await fetcher(url, { headers, signal: AbortSignal.timeout(20_000) });
  } catch (e) {
    throw new LyricsUnavailable(String(e));
  }
  if (res.status === 404) return null;
  if (!res.ok) throw new LyricsUnavailable(`${new URL(url).host} ${res.status}`);
  try {
    return await res.json();
  } catch (e) {
    throw new LyricsUnavailable(`${new URL(url).host} sent no JSON: ${String(e)}`);
  }
}

interface NeteaseSong {
  id: number;
  name: string;
  duration: number;
  artists: Array<{ name: string }>;
}

/** NetEase Cloud Music: word-timed YRC when it has it, line LRC otherwise. */
export class NeteaseClient {
  constructor(private readonly fetcher: typeof fetch = fetch) {}

  async find(ours: Ours): Promise<FoundLyrics | null> {
    const q = `${ours.artist.split(/,|;|\//)[0]?.trim() ?? ours.artist} ${ours.title.replace(/\(.*?\)|\[.*?\]/g, " ")}`;
    const search = (await getJson(
      this.fetcher,
      `https://music.163.com/api/search/get?type=1&limit=10&s=${encodeURIComponent(q.trim())}`,
      { "User-Agent": BROWSER_UA, Referer: "https://music.163.com/" },
    )) as { result?: { songs?: NeteaseSong[] } } | null;
    const songs = search?.result?.songs ?? [];
    const song = songs.find((s) =>
      sameSong({ title: s.name, artists: s.artists.map((a) => a.name), durationMs: s.duration }, ours),
    );
    if (!song) return null;
    const lyric = (await getJson(
      this.fetcher,
      `https://music.163.com/api/song/lyric/v1?id=${song.id}&lv=1&yv=1&tv=-1&rv=-1&kv=-1`,
      { "User-Agent": BROWSER_UA, Referer: "https://music.163.com/" },
    )) as { yrc?: { lyric?: string }; lrc?: { lyric?: string }; pureMusic?: boolean } | null;
    if (!lyric || lyric.pureMusic) return null;
    const raw = { song, lyric };
    const yrc = lyric.yrc?.lyric ? yrcToLrc(lyric.yrc.lyric, ours) : null;
    if (yrc) return { text: yrc, source: "netease", timing: "word", id: String(song.id), raw };
    const lrc = lyric.lrc?.lyric ? cleanNeteaseLrc(lyric.lrc.lyric, ours) : null;
    if (lrc) return { text: lrc, source: "netease", timing: "line", id: String(song.id), raw };
    return null;
  }
}

/** Genius: plain words, read off the song's page. */
export class GeniusClient {
  constructor(private readonly fetcher: typeof fetch = fetch) {}

  async find(ours: Ours): Promise<FoundLyrics | null> {
    const q = `${ours.artist.split(/,|;|\//)[0]?.trim() ?? ours.artist} ${ours.title.replace(/\(.*?\)|\[.*?\]/g, " ")}`;
    const search = (await getJson(
      this.fetcher,
      `https://genius.com/api/search/song?per_page=5&q=${encodeURIComponent(q.trim())}`,
      { "User-Agent": BROWSER_UA, Accept: "application/json" },
    )) as {
      response?: {
        sections?: Array<{
          hits?: Array<{
            result: { id: number; title: string; url: string; instrumental?: boolean; lyrics_state?: string; primary_artist: { name: string } };
          }>;
        }>;
      };
    } | null;
    const hits = (search?.response?.sections ?? []).flatMap((s) => s.hits ?? []).map((h) => h.result);
    const hit = hits.find(
      (r) =>
        !r.instrumental &&
        r.lyrics_state === "complete" &&
        sameSong({ title: r.title, artists: [r.primary_artist.name], durationMs: null }, ours),
    );
    if (!hit) return null;
    let res: Response;
    try {
      res = await this.fetcher(hit.url, { headers: { "User-Agent": BROWSER_UA }, signal: AbortSignal.timeout(20_000) });
    } catch (e) {
      throw new LyricsUnavailable(String(e));
    }
    if (!res.ok) throw new LyricsUnavailable(`genius page ${res.status}`);
    const text = geniusLyricsFromHtml(await res.text());
    if (!text) return null;
    return { text, source: "genius", timing: "plain", id: String(hit.id), raw: { hit, text } };
  }
}

// ---------------------------------------------------------------- chain

function fromLrclib(c: LyricsCandidate | null, wantSynced: boolean): FoundLyrics | null {
  if (!c) return null;
  const synced = c.syncedLyrics?.trim();
  const plain = c.plainLyrics?.trim();
  if (wantSynced) {
    return synced ? { text: synced, source: "lrclib", timing: "line", id: String(c.id), raw: c } : null;
  }
  return plain ? { text: plain, source: "lrclib", timing: "plain", id: String(c.id), raw: c } : null;
}

type Finder = { find(ours: Ours): Promise<FoundLyrics | null> };

/** Asks every source, best timing first. */
export class LyricChain {
  constructor(
    private readonly lrclib: Pick<LrclibClient, "candidate">,
    private readonly netease: Finder,
    private readonly genius: Finder,
  ) {}

  async find(ours: Ours): Promise<ChainAnswer> {
    let complete = true;
    const ask = async <T>(f: () => Promise<T>): Promise<T | null> => {
      try {
        return await f();
      } catch (e) {
        if (!(e instanceof LyricsUnavailable)) throw e;
        complete = false;
        return null;
      }
    };
    const ne = await ask(() => this.netease.find(ours));
    if (ne?.timing === "word") return { found: ne, complete: true };
    const lr = await ask(() => this.lrclib.candidate(ours));
    const lrSynced = fromLrclib(lr, true);
    if (lrSynced) return { found: lrSynced, complete: true };
    if (ne?.timing === "line") return { found: ne, complete: true };
    const lrPlain = fromLrclib(lr, false);
    if (lrPlain) return { found: lrPlain, complete: true };
    const ge = await ask(() => this.genius.find(ours));
    if (ge) return { found: ge, complete: true };
    return { found: null, complete };
  }
}
