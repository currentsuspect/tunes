import { describe, expect, it } from "vitest";
import { foldTags, hasAttachedPicture, parseIndex, tagsFromFfprobe } from "../src/probe.js";

/**
 * Shape taken verbatim from a real library file: FLAC Vorbis comments come
 * back UPPERCASE, while `track`/`disc` arrive lower case in the same file.
 * The old reader tried `tags[k] ?? tags[k.toLowerCase()]`, so it never found
 * ALBUM and every one of these files showed up as "unknown album".
 */
const realFlac = {
  format: {
    tags: {
      TITLE: "NEW HIGH",
      ARTISTS: "Yeat;Don Toliver",
      ALBUM: "LYFESTYLE",
      track: "7",
      TRACKTOTAL: "18",
      disc: "1",
      GENRE: "Hip-Hop",
      DATE: "2026",
    },
  },
  streams: [
    { codec_name: "flac", codec_type: "audio", sample_rate: "44100", channels: 2, tags: {} },
    { codec_name: "mjpeg", codec_type: "video", disposition: { attached_pic: 1 } },
  ],
};

describe("foldTags", () => {
  it("finds a tag whatever case the container used", () => {
    const folded = foldTags({ ALBUM: "LYFESTYLE", track: "7" });
    expect(folded.get("album")).toBe("LYFESTYLE");
    expect(folded.get("track")).toBe("7");
  });

  it("ignores empty and whitespace-only values", () => {
    const folded = foldTags({ ALBUM: "   ", ARTIST: "" });
    expect(folded.has("album")).toBe(false);
    expect(folded.has("artist")).toBe(false);
  });

  it("lets the first source win so format tags outrank stream tags", () => {
    const folded = foldTags({ TITLE: "From Format" }, { title: "From Stream" });
    expect(folded.get("title")).toBe("From Format");
  });
});

describe("parseIndex", () => {
  it("reads a plain number", () => {
    expect(parseIndex("7")).toEqual({ index: 7, total: null });
  });

  it("reads the n/total form", () => {
    expect(parseIndex("7/18")).toEqual({ index: 7, total: 18 });
  });

  it("rejects junk and zero rather than inventing a position", () => {
    expect(parseIndex("A side")).toEqual({ index: null, total: null });
    expect(parseIndex("0")).toEqual({ index: null, total: null });
    expect(parseIndex(undefined)).toEqual({ index: null, total: null });
  });
});

describe("tagsFromFfprobe", () => {
  it("reads UPPERCASE Vorbis comments — the regression", () => {
    const tags = tagsFromFfprobe(realFlac);
    expect(tags.album).toBe("LYFESTYLE");
    expect(tags.title).toBe("NEW HIGH");
    expect(tags.year).toBe("2026");
    expect(tags.genre).toBe("Hip-Hop");
  });

  it("accepts ARTISTS as an alias for ARTIST", () => {
    expect(tagsFromFfprobe(realFlac).artist).toBe("Yeat;Don Toliver");
  });

  it("falls back to main_artist when neither ARTIST nor ARTISTS is present", () => {
    const tags = tagsFromFfprobe({ format: { tags: { main_artist: "Yeat" } } });
    expect(tags.artist).toBe("Yeat");
  });

  it("reads mixed-case numbering in a single file", () => {
    const tags = tagsFromFfprobe(realFlac);
    expect(tags.trackNumber).toBe(7);
    expect(tags.discNumber).toBe(1);
    expect(tags.totalTracks).toBe(18);
  });

  it("derives the total from a 7/18 track tag when TRACKTOTAL is absent", () => {
    const tags = tagsFromFfprobe({ format: { tags: { TRACK: "7/18" } } });
    expect(tags.trackNumber).toBe(7);
    expect(tags.totalTracks).toBe(18);
  });

  it("takes tags off the audio stream, not the cover-art stream", () => {
    const tags = tagsFromFfprobe({
      streams: [
        { codec_name: "mjpeg", codec_type: "video", tags: { TITLE: "cover.jpg" } },
        { codec_name: "flac", codec_type: "audio", tags: { TITLE: "Real Title" } },
      ],
    });
    expect(tags.title).toBe("Real Title");
  });

  it("reports nothing rather than guessing when the file has no tags", () => {
    expect(tagsFromFfprobe({ format: {}, streams: [] })).toEqual({});
  });
});

describe("hasAttachedPicture", () => {
  it("sees the cover art stream", () => {
    expect(hasAttachedPicture(realFlac)).toBe(true);
  });

  it("is false for an audio-only file", () => {
    expect(
      hasAttachedPicture({ streams: [{ codec_name: "flac", codec_type: "audio" }] })
    ).toBe(false);
  });
});
