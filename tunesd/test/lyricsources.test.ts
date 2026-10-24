import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { LyricsUnavailable, type LyricsCandidate } from "../src/lyrics.js";
import {
  cleanNeteaseLrc,
  geniusLyricsFromHtml,
  LyricChain,
  sameSong,
  stamp,
  yrcToLrc,
  type FoundLyrics,
} from "../src/lyricsources.js";

const ours = { title: "Irreplaceable", artist: "Beyoncé", album: "B'Day", durationMs: 227_853 };

describe("NetEase word timing", () => {
  const yrc = [
    '{"t":0,"c":[{"tx":"作词: "},{"tx":"Shaffer Smith"}]}',
    "[90,1050](90,350,0)Beyonce (440,350,0)- (790,350,0)Irreplaceable",
    "[1170,1620](1170,270,0)to (1440,90,0)the (1530,390,0)left (1920,210,0)to (2130,120,0)the (2250,540,0)left",
    "[6600,900](6600,200,0)Irre(6800,150,0)place(6950,300,0)able (7300,200,0)me",
  ].join("\n");

  it("keeps every word's start and end, to the millisecond", () => {
    const out = yrcToLrc(yrc, ours)!.split("\n");
    expect(out[0]).toBe(
      "[00:01.170]<00:01.170>to<00:01.440> <00:01.440>the<00:01.530> <00:01.530>left<00:01.920> " +
        "<00:01.920>to<00:02.130> <00:02.130>the<00:02.250> <00:02.250>left<00:02.790>",
    );
  });

  it("drops the credits and the title card", () => {
    const out = yrcToLrc(yrc, ours)!;
    expect(out).not.toContain("作词");
    expect(out).not.toContain("Beyonce");
  });

  it("joins a word sung in syllables back into one word", () => {
    const last = yrcToLrc(yrc, ours)!.split("\n").at(-1);
    expect(last).toBe("[00:06.600]<00:06.600>Irreplaceable<00:07.250> <00:07.300>me<00:07.500>");
  });

  it("writes minutes past an hour as minutes", () => {
    expect(stamp(3_905_123)).toBe("65:05.123");
  });
});

describe("NetEase line timing", () => {
  it("keeps the lines and drops the credit block", () => {
    const lrc = [
      '{"t":0,"c":[{"tx":"作词: "},{"tx":"Cameron"}]}',
      "[00:00.227][Verse]",
      "[00:01.006]Goddamn",
      "[00:02.184]You actin' way different",
      "[00:04.000]作曲 : Someone",
      "[00:05.100]Line four",
      "[00:07.300]Line five",
    ].join("\n");
    const out = cleanNeteaseLrc(lrc, ours)!;
    expect(out.split("\n")).toEqual([
      "[00:00.227][Verse]",
      "[00:01.006]Goddamn",
      "[00:02.184]You actin' way different",
      "[00:05.100]Line four",
      "[00:07.300]Line five",
    ]);
  });

  it("treats a stub of a line or two as no lyrics", () => {
    expect(cleanNeteaseLrc("[00:00.00]纯音乐，请欣赏", ours)).toBeNull();
  });
});

describe("Genius", () => {
  it("reads the words off a song page, without the contributors header", async () => {
    const html = await readFile(join(import.meta.dirname, "fixtures", "genius-page.html"), "utf8");
    const text = geniusLyricsFromHtml(html)!;
    expect(text.startsWith("[Intro]")).toBe(true);
    expect(text).toContain("So many thoughts in my head, I can't go to bed (Yeah)");
    expect(text).not.toMatch(/Contributors|Advert|<|&#/);
  });
});

describe("matching", () => {
  it("wants the same title, lead artist and length", () => {
    expect(sameSong({ title: "Irreplaceable", artists: ["Beyonce"], durationMs: 228_000 }, ours)).toBe(true);
    expect(sameSong({ title: "Irreplaceable (Live)", artists: ["Beyonce"], durationMs: 300_000 }, ours)).toBe(false);
    expect(sameSong({ title: "Irreplaceable", artists: ["Ne-Yo"], durationMs: 228_000 }, ours)).toBe(false);
  });
});

describe("the chain", () => {
  const found = (timing: FoundLyrics["timing"], source: FoundLyrics["source"]): FoundLyrics => ({
    text: `${source}-${timing}`,
    source,
    timing,
    id: "1",
    raw: null,
  });
  const lrclib = (c: Partial<LyricsCandidate> | null) => ({
    candidate: async () =>
      c && ({ id: 1, trackName: "", artistName: "", albumName: "", duration: 0, instrumental: false, plainLyrics: null, syncedLyrics: null, ...c } as LyricsCandidate),
  });
  const of = (f: FoundLyrics | null) => ({ find: async () => f });
  const failing = { find: async (): Promise<FoundLyrics | null> => { throw new LyricsUnavailable("down"); } };

  it("takes word timing over anything else", async () => {
    const c = new LyricChain(lrclib({ syncedLyrics: "[00:01.00]x" }), of(found("word", "netease")), of(null));
    expect((await c.find(ours)).found?.timing).toBe("word");
  });

  it("then LRCLIB's lines, then NetEase's, then plain words", async () => {
    expect((await new LyricChain(lrclib({ syncedLyrics: "[00:01.00]x" }), of(found("line", "netease")), of(null)).find(ours)).found?.source).toBe("lrclib");
    expect((await new LyricChain(lrclib({ plainLyrics: "x" }), of(found("line", "netease")), of(null)).find(ours)).found?.source).toBe("netease");
    expect((await new LyricChain(lrclib({ plainLyrics: "x" }), of(null), of(found("plain", "genius"))).find(ours)).found?.source).toBe("lrclib");
    expect((await new LyricChain(lrclib(null), of(null), of(found("plain", "genius"))).find(ours)).found?.source).toBe("genius");
  });

  it("does not call it 'no lyrics' while a source is down", async () => {
    const a = await new LyricChain(lrclib(null), failing, of(null)).find(ours);
    expect(a).toEqual({ found: null, complete: false });
    const b = await new LyricChain(lrclib(null), of(null), of(null)).find(ours);
    expect(b).toEqual({ found: null, complete: true });
  });
});
