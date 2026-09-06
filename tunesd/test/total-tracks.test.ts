import { describe, expect, it } from "vitest";
import { resolveTotalTracks } from "../src/manifest.js";

/**
 * Cases taken from the live library, where "Missing from your collection"
 * was listing albums the owner already has in full.
 */
describe("resolveTotalTracks", () => {
  it("believes the files over a provider that describes another edition", () => {
    // HARDSTONE PSYCHO: 16 files on disk, every one tagged TOTALTRACKS=16,
    // provider said 23. The home screen reported "7 missing" for a complete
    // album.
    const files = Array.from({ length: 16 }, () => 16);
    expect(resolveTotalTracks(16, files, 23)).toBe(16);
  });

  it("takes the majority when the tags disagree", () => {
    // Life of a DON: mostly 16, with one stray single-tagged file and one
    // deluxe number.
    const files = [...Array.from({ length: 14 }, () => 16), 1, 19];
    expect(resolveTotalTracks(16, files, 19)).toBe(16);
  });

  it("breaks a tie toward the larger total, not toward probe order", () => {
    expect(resolveTotalTracks(2, [12, 14], null)).toBe(14);
    expect(resolveTotalTracks(2, [14, 12], null)).toBe(14);
  });

  it("still reports a genuine shortfall", () => {
    // The feature has to keep working: ten of sixteen really is six missing.
    expect(resolveTotalTracks(10, Array.from({ length: 10 }, () => 16), null)).toBe(16);
  });

  it("discards a per-disc count that is smaller than what we hold", () => {
    // A multi-disc tagger writes the tracks-on-this-disc number. Believing it
    // would say a 16-track album holds 4.
    expect(resolveTotalTracks(16, Array.from({ length: 16 }, () => 4), null)).toBeNull();
  });

  it("reports nothing rather than a total below what is on disk", () => {
    // xperiment - cartunez: 35 files, provider total 22. "35/22 complete" is
    // not a claim we can support.
    expect(resolveTotalTracks(35, [], 22)).toBeNull();
  });

  it("falls back to the provider when the files say nothing", () => {
    expect(resolveTotalTracks(10, [], 16)).toBe(16);
  });

  it("accepts a provider total that exactly matches what we hold", () => {
    expect(resolveTotalTracks(16, [], 16)).toBe(16);
  });

  it("returns null when neither source has anything usable", () => {
    expect(resolveTotalTracks(5, [], null)).toBeNull();
  });

  it("ignores junk tag values instead of counting them as votes", () => {
    expect(resolveTotalTracks(3, [0, -4, 3.5, 12], null)).toBe(12);
  });

  it("does not let a single provider answer outvote the files", () => {
    // The regression this guards: one provider number beating sixteen files.
    expect(resolveTotalTracks(16, Array.from({ length: 16 }, () => 16), 23)).not.toBe(23);
  });
});
