import { describe, expect, it } from "vitest";
import {
  bestLyricsMatch,
  toResult,
  type LyricsCandidate,
} from "../src/lyrics.js";

/**
 * Choosing which lyrics belong to a track.
 *
 * Measured against the real thing: a search for "Big Poe" by Tyler, The
 * Creator returns twenty rows whose album names do not separate them —
 * "DON'T TAP THE GLASS", "…Instrumentals", "…[Physical version CD]",
 * "…(Test Pressing 1 CD)" — and whose first line is timed at 00:02.20,
 * 00:01.76 and 00:02.18 depending on the row.
 *
 * So picking by name lands on lyrics that run half a second out for the whole
 * song, which is worse than having none: it reads as the app being broken
 * rather than the data being wrong. Duration is what separates them.
 */
const c = (o: Partial<LyricsCandidate>): LyricsCandidate => ({
  id: 1,
  trackName: "Big Poe",
  artistName: "Tyler, The Creator",
  albumName: "DON'T TAP THE GLASS",
  duration: 182,
  instrumental: false,
  plainLyrics: "Welcome",
  syncedLyrics: "[00:02.20] Welcome",
  ...o,
});

const ours = {
  title: "Big Poe",
  artist: "Tyler, The Creator",
  durationMs: 182401,
};

describe("bestLyricsMatch", () => {
  it("prefers a candidate whose duration matches ours", () => {
    const chosen = bestLyricsMatch(
      [c({ id: 1, duration: 200 }), c({ id: 2, duration: 182.4 })],
      ours,
    );
    expect(chosen?.id).toBe(2);
  });

  it("rejects a duration outside the tolerance entirely", () => {
    // A different edit or a different recording. Better no lyrics than lyrics
    // that drift further out with every line.
    expect(bestLyricsMatch([c({ duration: 240 })], ours)).toBeNull();
  });

  it("prefers synced over plain even when plain matches more closely", () => {
    // Following along is the whole point; a perfectly matched block of text
    // still cannot be followed.
    const chosen = bestLyricsMatch(
      [
        c({ id: 1, duration: 182.4, syncedLyrics: null }),
        c({ id: 2, duration: 184, syncedLyrics: "[00:02.20] Welcome" }),
      ],
      ours,
    );
    expect(chosen?.id).toBe(2);
  });

  it("rejects instrumentals", () => {
    // An instrumental with lyrics attached is a mismatch by definition.
    expect(
      bestLyricsMatch([c({ instrumental: true })], ours),
    ).toBeNull();
  });

  it("rejects candidates with no lyrics of either kind", () => {
    expect(
      bestLyricsMatch(
        [c({ syncedLyrics: null, plainLyrics: null })],
        ours,
      ),
    ).toBeNull();
  });

  it("rejects a different song that happens to share a duration", () => {
    // LRCLIB search is fuzzy, so neighbours come back. Without a title check
    // one with a matching runtime would win the tie-break outright.
    expect(
      bestLyricsMatch([c({ trackName: "Sticky", duration: 182.4 })], ours),
    ).toBeNull();
  });

  it("accepts a title that differs only by a bracketed suffix", () => {
    const chosen = bestLyricsMatch(
      [c({ trackName: "Big Poe (Extended Mix)", duration: 182.4 })],
      ours,
    );
    expect(chosen).not.toBeNull();
  });

  it("skips the duration test when we do not know ours", () => {
    // Some tracks carry no duration. Refusing to look would deny lyrics for
    // exactly the files whose metadata is already poorest.
    const chosen = bestLyricsMatch([c({ duration: 900 })], {
      ...ours,
      durationMs: null,
    });
    expect(chosen).not.toBeNull();
  });

  it("returns null for an empty or malformed list", () => {
    expect(bestLyricsMatch([], ours)).toBeNull();
    expect(bestLyricsMatch(null as never, ours)).toBeNull();
  });
});

describe("toResult", () => {
  it("keeps the LRCLIB id, so a bad match can be re-picked", () => {
    // Without it, correcting a wrong choice means guessing again from
    // scratch rather than excluding the row that was wrong.
    expect(toResult(c({ id: 34733705 }))?.id).toBe(34733705);
  });

  it("keeps plain lyrics when there is no synced version", () => {
    const r = toResult(c({ syncedLyrics: null }));
    expect(r?.synced).toBeNull();
    expect(r?.plain).toBe("Welcome");
  });

  it("treats whitespace-only lyrics as absent", () => {
    expect(toResult(c({ syncedLyrics: "  ", plainLyrics: "\n" }))).toBeNull();
  });

  it("is null for no candidate", () => {
    expect(toResult(null)).toBeNull();
  });
});
