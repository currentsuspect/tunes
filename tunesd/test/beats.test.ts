import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { BeatStore, beatLine, findMoments, withBeats } from "../src/beats.js";

/** A minute of trap: an 808 every 500 ms, each decaying 30 dB before the
 * next, the rest of the mix steady. Frames are 10 ms, levels in dB. */
function trap(seconds = 60): { sub: Float64Array; full: Float64Array } {
  const n = seconds * 100;
  const sub = new Float64Array(n);
  const full = new Float64Array(n).fill(-2);
  for (let i = 0; i < n; i++) {
    const since = i % 50;
    sub[i] = since < 8 ? 0 : -30;
  }
  return { sub, full };
}

describe("where a song hits", () => {
  it("ignores an 808 that only breathes between bars", () => {
    const { sub, full } = trap();
    expect(findMoments(sub, full)).toEqual({ drops: [], breaks: [], pulse: [], quiet: [] });
  });

  it("finds a break: the 808 gone for seconds, the mix still going, then back", () => {
    const { sub, full } = trap();
    // 20.08 s to 23 s: no hit at all; the 808 lands again at 23 s.
    for (let i = 2008; i < 2300; i++) sub[i] = -30;
    const m = findMoments(sub, full);
    expect(m.breaks).toEqual([[20080, 23000]]);
    expect(m.drops).toEqual([23000]);
    // The 808 after it, every 500 ms for 4 s, to pulse with.
    expect(m.pulse).toEqual([23000, 23500, 24000, 24500, 25000, 25500, 26000, 26500, 27000]);
  });

  it("finds a drop after the whole beat falls quiet", () => {
    const { sub, full } = trap();
    for (let i = 4008; i < 4050; i++) {
      sub[i] = -40;
      full[i] = -30;
    }
    expect(findMoments(sub, full).drops).toEqual([40500]);
  });

  it("says nothing when every bar is a 'drop'", () => {
    const { sub, full } = trap();
    for (let s = 2; s < 58; s += 3) {
      for (let i = s * 100 + 8; i < s * 100 + 50; i++) {
        sub[i] = -40;
        full[i] = -30;
      }
    }
    expect(findMoments(sub, full).drops).toEqual([]);
  });

  it("finds the music going quiet", () => {
    const { sub, full } = trap();
    for (let i = 5000; i < 5300; i++) {
      sub[i] = -60;
      full[i] = -50;
    }
    const [q] = findMoments(sub, full).quiet;
    expect(q).toBeDefined();
    expect(q![0]).toBeGreaterThanOrEqual(5000 * 10 - 200);
    expect(q![1]).toBeLessThanOrEqual(5300 * 10 + 200);
  });
});

describe("the beat line in a lyric", () => {
  const m = { drops: [1360, 67660], breaks: [[63080, 67660]] as Array<[number, number]>, pulse: [], quiet: [] };

  it("is one metadata line other players skip", () => {
    expect(beatLine(m)).toBe("[tunesbeat:drop=1360,67660;break=63080-67660]");
    expect(beatLine({ drops: [], breaks: [], pulse: [], quiet: [] })).toBeNull();
  });

  it("goes on timed lyrics, replacing one a phone handed back", () => {
    const lyric = "[tunesbeat:drop=1]\n[00:01.46] (I-I-I)\n[00:01.73] Uh, uh";
    expect(withBeats(lyric, m)).toBe(
      "[tunesbeat:drop=1360,67660;break=63080-67660]\n[00:01.46] (I-I-I)\n[00:01.73] Uh, uh"
    );
  });

  it("leaves plain lyrics, and lyrics it has nothing for, alone", () => {
    expect(withBeats("just words\nmore words", m)).toBe("just words\nmore words");
    expect(withBeats("[00:01.46] hi", null)).toBe("[00:01.46] hi");
  });
});

describe("the beat store", () => {
  it("keeps what was read, and says what changed since", async () => {
    const dir = await mkdtemp(join(tmpdir(), "beats-"));
    try {
      const file = join(dir, "beats.json");
      const before = Date.now() - 1;
      const a = await new BeatStore(file).load();
      await a.set("aa", { drops: [5], breaks: [], pulse: [], quiet: [] });
      const b = await new BeatStore(file).load();
      expect(b.get("aa")?.drops).toEqual([5]);
      expect(b.changedSince(before)).toEqual(["aa"]);
      expect(b.changedSince(Date.now() + 1000)).toEqual([]);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});
