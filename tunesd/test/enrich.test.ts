import { describe, expect, it } from "vitest";
import { flattenReleaseTracks, parseArtistTitle } from "../src/enrich.js";

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
describe("flattenReleaseTracks", () => {
  it("keeps positions when they are globally monotonic across media", () => {
    const rows = flattenReleaseTracks([
      {
        position: 1,
        tracks: [
          { title: "A", position: 1, length: 100 },
          { title: "B", position: 2, length: 200 },
          { title: "C", position: 3, length: 300 },
        ],
      },
    ]);
    expect(rows.map((r) => r.position)).toEqual([1, 2, 3]);
    expect(rows[0]?.discNumber).toBe(1);
  });

  it("renumbers sequentially when media positions overlap or regress", () => {
    const rows = flattenReleaseTracks([
      {
        position: 1,
        tracks: [
          { title: "KRYPTONITE", position: 1 },
          { title: "TORE UP", position: 3 },
          { title: "BROTHER STONE", position: 5 },
          { title: "ATTITUDE", position: 7 },
        ],
      },
      {
        position: 2,
        tracks: [
          { title: "BANDIT", position: 5 },
          { title: "GLOCK", position: 7 },
          { title: "ICE AGE", position: 9 },
          { title: "4X4", position: 11 },
        ],
      },
    ]);
    expect(rows.map((r) => r.position)).toEqual([1, 2, 3, 4, 5, 6, 7, 8]);
    expect(rows.map((r) => r.discNumber)).toEqual([1, 1, 1, 1, 2, 2, 2, 2]);
    expect(rows[4]?.title).toBe("BANDIT");
  });

  it("renumbers when positions are missing entirely", () => {
    const rows = flattenReleaseTracks([
      { tracks: [{ title: "X" }, { title: "Y" }] },
    ]);
    expect(rows.map((r) => r.position)).toEqual([1, 2]);
  });
});
