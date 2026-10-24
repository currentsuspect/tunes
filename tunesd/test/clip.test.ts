import { execFileSync } from "node:child_process";
import { mkdtemp, readFile, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { ClipMaker, clipArgs, kMaxClipMs, parseSpan } from "../src/clip.js";

describe("the span of a clip", () => {
  it("takes milliseconds, start before end", () => {
    expect(parseSpan("1500", "16500")).toEqual({ fromMs: 1500, toMs: 16500 });
    expect(typeof parseSpan("16500", "1500")).toBe("string");
    expect(typeof parseSpan(null, "1500")).toBe("string");
    expect(typeof parseSpan("-1", "1500")).toBe("string");
  });

  it("is a verse at most, and not a blip", () => {
    expect(typeof parseSpan("0", String(kMaxClipMs + 1))).toBe("string");
    expect(typeof parseSpan("0", "200")).toBe("string");
  });

  it("is cut to the millisecond, with a video only when there is a card", () => {
    const audio = clipArgs("in.flac", { fromMs: 21360, toMs: 25400 }, null, "out.mp4");
    expect(audio).toEqual(expect.arrayContaining(["-ss", "21.360", "-t", "4.040", "-vn"]));
    const video = clipArgs("in.flac", { fromMs: 21360, toMs: 25400 }, "card.png", "out.mp4");
    expect(video).toEqual(expect.arrayContaining(["libx264", "card.png"]));
  });
});

const hasFfmpeg = (() => {
  try {
    execFileSync("ffmpeg", ["-version"], { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
})();

describe.skipIf(!hasFfmpeg)("cutting a clip", () => {
  let dir: string;
  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "clip-"));
  });
  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it("cuts exactly the span asked for, and tidies up after", async () => {
    const song = join(dir, "song.flac");
    execFileSync("ffmpeg", ["-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=10", song]);
    const clips = new ClipMaker(join(dir, "tmp"));
    const made = await clips.make(song, { fromMs: 2000, toMs: 5500 }, null);
    expect(made.mime).toBe("audio/mp4");
    const secs = Number(
      execFileSync("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", made.path]).toString(),
    );
    expect(secs).toBeGreaterThan(3.4);
    expect(secs).toBeLessThan(3.6);
    expect((await stat(made.path)).size).toBeGreaterThan(1000);
    await clips.discard(made.path);
    await expect(readFile(made.path)).rejects.toThrow();
  });
});
