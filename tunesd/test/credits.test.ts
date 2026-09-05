import { describe, expect, it } from "vitest";
import { parseCredits, releaseArtistOf, sameArtistName, stripFeatured } from "../src/credits.js";

describe("parseCredits", () => {
  it("recovers the primary artist from the real library's credit strings", () => {
    // These nine strings all belong to one album (LYFESTYLE) and used to
    // produce nine different release keys.
    for (const raw of [
      "Yeat",
      "Yeat, Don Toliver",
      "Yeat;Don Toliver",
      "Yeat, Kodak Black",
      "Yeat;Kodak Black",
      "Yeat, Lil Durk",
      "Yeat;Lil Durk",
      "Yeat, Summrs",
      "Yeat;Summrs",
    ]) {
      expect(parseCredits(raw).primary).toBe("Yeat");
    }
  });

  it("keeps the guests it stripped", () => {
    expect(parseCredits("Yeat;Don Toliver").featured).toEqual(["Don Toliver"]);
    expect(parseCredits("PARTYOF2, Jadagrac").featured).toEqual(["Jadagrac"]);
  });

  it("handles trailing separators from sloppy taggers", () => {
    expect(parseCredits("Don Toliver/ HVN/")).toEqual({
      primary: "Don Toliver",
      featured: ["HVN"],
    });
  });

  it("does not split a comma that is part of the name", () => {
    expect(parseCredits("Tyler, The Creator").primary).toBe("Tyler, The Creator");
    expect(parseCredits("Tyler, The Creator").featured).toEqual([]);
  });

  it("reads an explicit feature marker", () => {
    expect(parseCredits("Yeat feat. Don Toliver")).toEqual({
      primary: "Yeat",
      featured: ["Don Toliver"],
    });
    expect(parseCredits("Yeat ft. Summrs & NGeeYL")).toEqual({
      primary: "Yeat",
      featured: ["Summrs", "NGeeYL"],
    });
  });

  it("splits ampersand and x collaborations", () => {
    expect(parseCredits("Yeat & Lil Durk").primary).toBe("Yeat");
    expect(parseCredits("Yeat x Summrs").featured).toEqual(["Summrs"]);
  });

  it("never lists the primary as its own guest", () => {
    expect(parseCredits("Yeat, Yeat").featured).toEqual([]);
  });

  it("returns empty credits for empty input", () => {
    expect(parseCredits("")).toEqual({ primary: "", featured: [] });
    expect(parseCredits(null)).toEqual({ primary: "", featured: [] });
    expect(parseCredits(undefined)).toEqual({ primary: "", featured: [] });
  });
});

describe("stripFeatured", () => {
  it("pulls a bracketed credit out of the title", () => {
    expect(stripFeatured("AWOL (feat. no one)")).toEqual({
      title: "AWOL",
      featured: ["no one"],
    });
    expect(stripFeatured("Track [ft. X & Y]")).toEqual({
      title: "Track",
      featured: ["X", "Y"],
    });
  });

  it("leaves a non-credit parenthetical alone", () => {
    // Real title from the library — "(SUGAR)" is part of the song name.
    expect(stripFeatured("WAIT FOR THE SUN (SUGAR)")).toEqual({
      title: "WAIT FOR THE SUN (SUGAR)",
      featured: [],
    });
    expect(stripFeatured("Out My Face (My Baby)").featured).toEqual([]);
  });

  it("does not treat a bare 'with' in a title as a credit", () => {
    expect(stripFeatured("Dancing with Myself")).toEqual({
      title: "Dancing with Myself",
      featured: [],
    });
  });

  it("handles more than one credit block", () => {
    const out = stripFeatured("Song (feat. A) [ft. B]");
    expect(out.title).toBe("Song");
    expect(out.featured).toEqual(["A", "B"]);
  });

  it("never returns an empty title", () => {
    expect(stripFeatured("(feat. A)").title).toBe("(feat. A)");
  });
});

describe("releaseArtistOf", () => {
  it("trusts the album-artist tag over the track credit", () => {
    expect(releaseArtistOf("Yeat", "Yeat, Don Toliver")).toBe("Yeat");
  });

  it("falls back to the primary of the track credit", () => {
    expect(releaseArtistOf(null, "Yeat;Kodak Black")).toBe("Yeat");
    expect(releaseArtistOf("", "Yeat, Summrs")).toBe("Yeat");
  });

  it("collapses every LYFESTYLE credit string to one release artist", () => {
    const seen = new Set(
      [
        ["Yeat", "Yeat"],
        [null, "Yeat, Don Toliver"],
        [null, "Yeat;Kodak Black"],
        ["Yeat", "Yeat, Lil Durk"],
        [null, "Yeat;Summrs"],
      ].map(([aa, ta]) => releaseArtistOf(aa, ta as string))
    );
    expect([...seen]).toEqual(["Yeat"]);
  });

  it("keeps a comma-containing album artist intact", () => {
    expect(releaseArtistOf("Tyler, The Creator", "Tyler, The Creator")).toBe(
      "Tyler, The Creator"
    );
  });
});

describe("sameArtistName", () => {
  it("accepts the same name written differently", () => {
    expect(sameArtistName("A$AP Rocky", "A$AP Rocky")).toBe(true);
    expect(sameArtistName("Tyler, The Creator", "Tyler The Creator")).toBe(true);
    expect(sameArtistName("Beyoncé", "Beyonce")).toBe(true);
    expect(sameArtistName("yeat", "Yeat")).toBe(true);
  });

  it("rejects the near-misses providers actually returned", () => {
    // Deezer answered these for the real queries; accepting them would put the
    // wrong picture and genres on the artist.
    expect(sameArtistName("Len", "Le N'")).toBe(false);
    expect(sameArtistName("HVN", "HVN & ERTH")).toBe(false);
  });

  it("rejects empty or missing names rather than matching them together", () => {
    expect(sameArtistName("", "")).toBe(false);
    expect(sameArtistName(null, null)).toBe(false);
    expect(sameArtistName("Yeat", null)).toBe(false);
  });
});
