/**
 * Where a song hits: the 808 landing after the beat drops out, and the
 * stretches where the music goes quiet. The phone uses them to clear the
 * lyrics for a moment (an ad-lib alone in the middle on the hit, the whole
 * sheet dissolving and coming back line by line, the words fading out when
 * the song does).
 *
 * An 808 is nearly all energy under 100 Hz, so the song's sub-bass level,
 * read every 10 ms, says where it hits. Trap 808s hit all the time, so a hit
 * alone means nothing: a drop is a hit after an unusually long gap in the
 * bass (twice the song's usual gap, and at least 0.9 s), or after the whole
 * mix fell quiet. On Yeat's "Griddlë" that is five moments in 2.5 minutes
 * out of a bass line that gaps every bar (24 Oct).
 *
 * The result travels inside the lyric, as one metadata line other players
 * skip: [tunesbeat:drop=1360,67500;break=64000-67500;quiet=154230-157330]
 * (milliseconds).
 *
 * A break is the other kind of moment: the 808 gone for two seconds or more
 * while the rest keeps playing, until it slams back in. "Griddlë" has one at
 * each "don't get hit with the b- (ah)": the bass leaves, the ad-lib and a
 * train sound carry it, and the 808 returns on the next line. Its return is
 * a drop too.
 */
import { spawn } from "node:child_process";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname } from "node:path";

/** Bump when detection changes, so older results are worked out again. */
export const kBeatVersion = 1;

/** Samples per second read from ffmpeg: plenty for a 10 ms envelope. */
const kRate = 4000;
const kHop = 40;
const kFrameMs = 1000 / (kRate / kHop);

export interface BeatMoments {
  /** When a drop hits, ms. */
  drops: number[];
  /** Spans where the 808 is gone but the music is not, ms; each ends on
   * the hit that brings it back. */
  breaks: Array<[number, number]>;
  /** The 808's hits for a few seconds after each drop, ms: the pulse a
   * word on the drop shrinks back in time with. */
  pulse: number[];
  /** Spans where the music goes quiet, ms. */
  quiet: Array<[number, number]>;
}

/** Level in dB every 10 ms, smoothed over 30 ms. */
export function envelope(samples: Float32Array): Float64Array {
  const n = Math.floor(samples.length / kHop);
  const raw = new Float64Array(n);
  for (let i = 0; i < n; i++) {
    let sum = 0;
    for (let k = i * kHop; k < (i + 1) * kHop; k++) sum += samples[k]! * samples[k]!;
    raw[i] = 10 * Math.log10(sum / kHop + 1e-10);
  }
  const out = new Float64Array(n);
  for (let i = 0; i < n; i++) {
    const a = raw[Math.max(0, i - 1)]!;
    const b = raw[i]!;
    const c = raw[Math.min(n - 1, i + 1)]!;
    out[i] = (a + b + c) / 3;
  }
  return out;
}

function percentile(xs: Float64Array, p: number): number {
  const s = Array.from(xs).sort((a, b) => a - b);
  if (s.length === 0) return 0;
  return s[Math.min(s.length - 1, Math.floor((p / 100) * s.length))]!;
}

function mean(xs: Float64Array, from: number, to: number): number {
  let sum = 0;
  for (let i = from; i < to; i++) sum += xs[i]!;
  return to > from ? sum / (to - from) : 0;
}

/**
 * The drops and quiet stretches in a song, from its sub-bass ([sub], under
 * 100 Hz) and full-mix ([full]) envelopes. Nothing for a song with so many
 * "drops" that none would stand out.
 */
export function findMoments(sub: Float64Array, full: Float64Array): BeatMoments {
  const n = Math.min(sub.length, full.length);
  if (n < 100) return { drops: [], breaks: [], pulse: [], quiet: [] };
  const top = percentile(sub, 95);
  const fullTop = percentile(full, 95);

  // Gaps in the bass, and the hit (back to full level) that ends each.
  const gaps: Array<{ from: number; to: number; hit: number | null }> = [];
  for (let i = 0; i < n; ) {
    if (sub[i]! >= top - 24) {
      i++;
      continue;
    }
    let j = i;
    while (j < n && sub[j]! < top - 24) j++;
    let hit: number | null = null;
    for (let k = j; k < Math.min(n, j + 15); k++) {
      if (sub[k]! > top - 3) {
        hit = k;
        break;
      }
    }
    if (j - i >= 6) gaps.push({ from: i, to: j, hit });
    i = j;
  }
  const hitGaps = gaps.filter((g) => g.hit !== null).map((g) => g.to - g.from).sort((a, b) => a - b);
  const usual = hitGaps[Math.floor(hitGaps.length / 2)] ?? 0;
  const longGap = Math.max(2 * usual, 900 / kFrameMs);

  const hits: number[] = [];
  for (const g of gaps) {
    if (g.hit === null) continue;
    const len = g.to - g.from;
    const mixFell = len >= 200 / kFrameMs && mean(full, g.from, g.to) <= fullTop - 18;
    if (len < longGap && !mixFell) continue;
    hits.push(g.hit);
  }

  // Breaks: no 808 hit (nothing within 7 dB of its usual peak) for 2 s,
  // the mix still going, and a hit within a second after.
  const breaks: Array<[number, number]> = [];
  for (let i = 0; i < n; ) {
    if (sub[i]! > top - 7) {
      i++;
      continue;
    }
    let j = i;
    while (j < n && sub[j]! <= top - 7) j++;
    if ((j - i) * kFrameMs >= 2000 && mean(full, i, j) >= fullTop - 16) {
      let hit: number | null = null;
      for (let k = j; k < Math.min(n, j + 100); k++) {
        if (sub[k]! > top - 3) {
          hit = k;
          break;
        }
      }
      if (hit !== null) {
        breaks.push([Math.round(i * kFrameMs), Math.round(hit * kFrameMs)]);
        hits.push(hit);
      }
    }
    i = j;
  }

  const drops: number[] = [];
  for (const h of hits.sort((a, b) => a - b)) {
    const at = Math.round(h * kFrameMs);
    const last = drops[drops.length - 1];
    if (last !== undefined && at - last < 3000) continue;
    drops.push(at);
  }
  // One every 12 s on average is the most that still reads as a moment.
  const durationMs = n * kFrameMs;
  if (drops.length > durationMs / 12_000) {
    drops.length = 0;
    breaks.length = 0;
  }

  // Every 808 onset (up within 6 dB of its peak after 50 ms well under it),
  // kept only for the 4 s after a drop.
  const pulse: number[] = [];
  let low = 0;
  for (let i = 0; i < n; i++) {
    if (sub[i]! < top - 12) low++;
    else if (sub[i]! > top - 6) {
      if (low >= 5) {
        const at = Math.round(i * kFrameMs);
        if (drops.some((d) => at >= d - 60 && at <= d + 4000)) pulse.push(at);
      }
      low = 0;
    }
  }

  // Quiet: the mix, averaged over 300 ms, 20 dB under its usual level for
  // a second and a half or more.
  const quiet: Array<[number, number]> = [];
  const w = 15;
  const soft = (i: number) => mean(full, Math.max(0, i - w), Math.min(n, i + w)) < fullTop - 20;
  for (let i = 0; i < n; ) {
    if (!soft(i)) {
      i++;
      continue;
    }
    let j = i;
    while (j < n && soft(j)) j++;
    if ((j - i) * kFrameMs >= 1500) quiet.push([Math.round(i * kFrameMs), Math.round(j * kFrameMs)]);
    i = j;
  }
  return { drops, breaks, pulse, quiet };
}

/** The metadata line, or null when there is nothing to say. */
export function beatLine(m: BeatMoments): string | null {
  if (m.drops.length === 0 && m.breaks.length === 0 && m.quiet.length === 0) return null;
  const span = (xs: Array<[number, number]>) => xs.map(([a, b]) => `${a}-${b}`).join(",");
  const parts: string[] = [];
  if (m.drops.length) parts.push(`drop=${m.drops.join(",")}`);
  if (m.breaks.length) parts.push(`break=${span(m.breaks)}`);
  if (m.pulse.length) parts.push(`pulse=${m.pulse.join(",")}`);
  if (m.quiet.length) parts.push(`quiet=${span(m.quiet)}`);
  return `[tunesbeat:${parts.join(";")}]`;
}

/**
 * [lyrics] carrying [m] as its beat line. A line already there (a phone
 * saving the lyric back hands it in) is replaced: the box's reading wins.
 * Plain lyrics get none, having no times to line a moment up with.
 */
export function withBeats(lyrics: string, m: BeatMoments | null): string {
  if (!m || !/^\s*\[\d+:\d/m.test(lyrics)) return lyrics;
  const line = beatLine(m);
  const rest = lyrics.split("\n").filter((l) => !/^\s*\[tunesbeat:/i.test(l));
  return line === null ? rest.join("\n") : [line, ...rest].join("\n");
}

/** One band of [audio] as mono samples at kRate. */
function decode(ffmpeg: string, audio: string, filter: string): Promise<Float32Array> {
  return new Promise((resolve, reject) => {
    const p = spawn(
      ffmpeg,
      ["-v", "error", "-i", audio, "-vn", "-ac", "1", "-af", filter, "-ar", String(kRate), "-f", "f32le", "-"],
      { stdio: ["ignore", "pipe", "pipe"] }
    );
    const chunks: Buffer[] = [];
    let err = "";
    p.stdout.on("data", (d: Buffer) => chunks.push(d));
    p.stderr.on("data", (d: Buffer) => (err = (err + d.toString()).slice(-1000)));
    const kill = setTimeout(() => p.kill("SIGKILL"), 120_000);
    p.on("error", (e) => {
      clearTimeout(kill);
      reject(e);
    });
    p.on("close", (code) => {
      clearTimeout(kill);
      if (code !== 0) return reject(new Error(`ffmpeg ${code}: ${err.trim().slice(-300)}`));
      const buf = Buffer.concat(chunks);
      const copy = new Uint8Array(buf.byteLength - (buf.byteLength % 4));
      copy.set(buf.subarray(0, copy.byteLength));
      resolve(new Float32Array(copy.buffer));
    });
  });
}

/** Reads [audio] and finds its moments. ~1 s for a 3-minute song. */
export async function analyzeBeats(audio: string, ffmpeg = "ffmpeg"): Promise<BeatMoments> {
  const sub = await decode(ffmpeg, audio, "lowpass=f=100,lowpass=f=100");
  const full = await decode(ffmpeg, audio, "anull");
  return findMoments(envelope(sub), envelope(full));
}

interface BeatEntry extends BeatMoments {
  at: string;
}

/** What has been worked out, kept so a song is read once. */
export class BeatStore {
  private entries = new Map<string, BeatEntry>();

  constructor(private readonly file: string) {}

  async load(): Promise<this> {
    try {
      const raw = JSON.parse(await readFile(this.file, "utf8")) as {
        version?: number;
        entries?: Record<string, BeatEntry>;
      };
      if (raw.version === kBeatVersion) {
        for (const [sha, e] of Object.entries(raw.entries ?? {})) this.entries.set(sha, e);
      }
    } catch {
      // None yet.
    }
    return this;
  }

  has(sha: string): boolean {
    return this.entries.has(sha);
  }

  get(sha: string): BeatMoments | null {
    return this.entries.get(sha) ?? null;
  }

  /** Shas worked out after [since]: their lyrics change on the phone. */
  changedSince(since: number): string[] {
    return [...this.entries].filter(([, e]) => Date.parse(e.at) > since).map(([sha]) => sha);
  }

  async set(sha: string, m: BeatMoments): Promise<void> {
    this.entries.set(sha, { ...m, at: new Date().toISOString() });
    await mkdir(dirname(this.file), { recursive: true });
    const tmp = `${this.file}.${process.pid}.tmp`;
    await writeFile(tmp, JSON.stringify({ version: kBeatVersion, entries: Object.fromEntries(this.entries) }));
    await rename(tmp, this.file);
  }
}
