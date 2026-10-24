/**
 * A moment of a song, cut to share: the exact span of a lyric line, as a short
 * video over the lyric card the phone drew, or as audio alone.
 *
 * Word timing is what makes this worth having: the clip starts on the line's
 * first word and ends on its last, with no trimming by hand. ffmpeg does the
 * work (a still picture is cheap: ~3 s for 15 s on this box); one clip is cut
 * at a time, and nothing is kept once it is sent.
 */
import { spawn } from "node:child_process";
import { mkdir, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { randomUUID } from "node:crypto";

/** Longest clip: a verse, not a song. */
export const kMaxClipMs = 60_000;
/** Largest card accepted: a 1080x1920 PNG is ~1-2 MB. */
export const kMaxCardBytes = 6 * 1024 * 1024;

export interface ClipSpan {
  fromMs: number;
  toMs: number;
}

/** The span asked for, or why not. */
export function parseSpan(from: string | null, to: string | null): ClipSpan | string {
  if (!from || !to) return "expected from and to (ms)";
  const f = Number(from);
  const t = Number(to);
  if (!Number.isFinite(f) || !Number.isFinite(t) || f < 0 || t <= f) return "expected 0 <= from < to (ms)";
  if (t - f > kMaxClipMs) return `at most ${kMaxClipMs / 1000} s`;
  if (t - f < 500) return "at least half a second";
  return { fromMs: Math.round(f), toMs: Math.round(t) };
}

/** ffmpeg's arguments for a clip: video over [card], or audio alone. */
export function clipArgs(audio: string, span: ClipSpan, card: string | null, out: string): string[] {
  const secs = (span.toMs - span.fromMs) / 1000;
  const s = (n: number) => n.toFixed(3);
  // Short fades so the cut does not click at either end.
  const fades = `afade=t=in:d=0.08,afade=t=out:st=${s(Math.max(0, secs - 0.15))}:d=0.15`;
  const audioIn = ["-ss", s(span.fromMs / 1000), "-t", s(secs), "-i", audio];
  if (card === null) {
    return ["-v", "error", "-y", ...audioIn, "-vn", "-c:a", "aac", "-b:a", "192k", "-af", fades, "-movflags", "+faststart", "-f", "mp4", out];
  }
  return [
    "-v", "error", "-y",
    // A still picture at 2 frames a second: all a card needs, and cheap.
    "-loop", "1", "-framerate", "2", "-t", s(secs), "-i", card,
    ...audioIn,
    "-map", "0:v", "-map", "1:a",
    "-c:v", "libx264", "-preset", "veryfast", "-tune", "stillimage", "-pix_fmt", "yuv420p", "-r", "2",
    // Even dimensions, which H.264 requires.
    "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2",
    "-c:a", "aac", "-b:a", "192k", "-af", fades,
    "-t", s(secs), "-movflags", "+faststart", "-f", "mp4", out,
  ];
}

export class ClipMaker {
  private busy: Promise<unknown> = Promise.resolve();

  constructor(
    private readonly tmpDir: string,
    private readonly ffmpeg = "ffmpeg",
  ) {}

  /** Cuts [span] of [audio]; resolves to the file, which the caller sends
   * and then removes with [discard]. One at a time. */
  make(audio: string, span: ClipSpan, cardPng: Uint8Array | null): Promise<{ path: string; mime: string }> {
    const run = this.busy.then(() => this.cut(audio, span, cardPng));
    this.busy = run.catch(() => undefined);
    return run;
  }

  async discard(path: string): Promise<void> {
    await rm(path, { force: true });
    await rm(`${path}.png`, { force: true });
  }

  private async cut(audio: string, span: ClipSpan, cardPng: Uint8Array | null): Promise<{ path: string; mime: string }> {
    await mkdir(this.tmpDir, { recursive: true });
    const out = join(this.tmpDir, `${randomUUID()}.mp4`);
    let card: string | null = null;
    if (cardPng) {
      card = `${out}.png`;
      await writeFile(card, cardPng);
    }
    await new Promise<void>((resolve, reject) => {
      const p = spawn(this.ffmpeg, clipArgs(audio, span, card, out), { stdio: ["ignore", "ignore", "pipe"] });
      let err = "";
      p.stderr.on("data", (d: Buffer) => (err = (err + d.toString()).slice(-2000)));
      const kill = setTimeout(() => p.kill("SIGKILL"), 60_000);
      p.on("error", (e) => {
        clearTimeout(kill);
        reject(e);
      });
      p.on("close", (code) => {
        clearTimeout(kill);
        if (code === 0) resolve();
        else reject(new Error(`ffmpeg ${code}: ${err.trim().slice(-300)}`));
      });
    });
    if (card) await rm(card, { force: true });
    return { path: out, mime: cardPng ? "video/mp4" : "audio/mp4" };
  }
}
