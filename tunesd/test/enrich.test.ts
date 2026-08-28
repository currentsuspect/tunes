import { describe, expect, it } from "vitest";
import { parseArtistTitle } from "../src/enrich.js";

describe("parseArtistTitle", () => {
  it("parses 'Artist - Title.ext'", () => {
    expect(parseArtistTitle("Travis Scott - ESCAPE PLAN.flac")).toEqual({
      artist: "Travis Scott",
      title: "ESCAPE PLAN",
    });
  });

  it("parses 'Artist - Title (feat. X) (Remix)' cleaning extra spaces", () => {
    expect(parseArtistTitle("Vax   -   AWOL  (feat. no one).flac")).toEqual({
      artist: "Vax",
      title: "AWOL (feat. no one)",
    });
  });

  it("returns null for filenames without the dash convention", () => {
    expect(parseArtistTitle("just a track name.mp3")).toBeNull();
    expect(parseArtistTitle("untitled")).toBeNull();
    expect(parseArtistTitle("")).toBeNull();
    expect(parseArtistTitle("-")).toBeNull();
    expect(parseArtistTitle("OnlyArtist -")).toBeNull();
  });
});