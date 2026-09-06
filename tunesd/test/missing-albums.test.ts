import { describe, expect, it } from "vitest";
import type { ArtistDiscography, DiscographyGroup } from "../src/discography.js";
import { missingFromCollection } from "../src/discography.js";

const group = (
  id: string,
  title: string,
  type = "Album",
  date: string | null = null
): DiscographyGroup => ({ id, title, type, year: date?.slice(0, 4) ?? null, date });

const disco = (name: string, groups: DiscographyGroup[]): ArtistDiscography => ({
  name,
  mbid: `mbid-${name}`,
  fetchedAt: 0,
  groups,
});

const discographies = (
  ...entries: Array<[string, ArtistDiscography]>
): Map<string, ArtistDiscography> => new Map(entries);

describe("missingFromCollection", () => {
  it("suggests the rest of an act's catalogue", () => {
    const out = missingFromCollection(
      [{ name: "Travis Scott", tracks: 17 }],
      discographies([
        "travis scott",
        disco("Travis Scott", [
          group("g1", "ASTROWORLD", "Album", "2018-08-03"),
          group("g2", "Rodeo", "Album", "2015-09-04"),
          group("g3", "UTOPIA", "Album", "2023-07-28"),
        ]),
      ]),
      [{ title: "ASTROWORLD", groupId: null }]
    );
    expect(out.map((g) => g.title)).toEqual(["UTOPIA", "Rodeo"]);
    expect(out[0]?.forArtist).toBe("Travis Scott");
  });

  it("skips an artist whose discography matches nothing owned", () => {
    // MusicBrainz answers a common name with whichever artist it likes.
    // Asking for "Lunchbox" returns an indie act sharing none of the
    // rapper's records; every one of its albums would read as "missing".
    const out = missingFromCollection(
      [{ name: "Lunchbox", tracks: 23 }],
      discographies([
        "lunchbox",
        disco("Lunchbox", [
          group("w1", "The Magic of Sound"),
          group("w2", "Summer's Over"),
        ]),
      ]),
      [
        { title: "Lunchtime.", groupId: null },
        { title: "New Jazz", groupId: null },
      ]
    );
    expect(out).toEqual([]);
  });

  it("matches an owned release by group id even when the titles differ", () => {
    const out = missingFromCollection(
      [{ name: "Yeat", tracks: 48 }],
      discographies([
        "yeat",
        disco("Yeat", [
          group("g-owned", "2093"),
          group("g-missing", "Lyfë"),
        ]),
      ]),
      [{ title: "2093 (P2)", groupId: "g-owned" }]
    );
    expect(out.map((g) => g.title)).toEqual(["Lyfë"]);
  });

  it("does not treat a curly apostrophe as a different album", () => {
    // normName only lowercases and collapses spaces, so "Don't" and "Don’t"
    // would otherwise look like two records and the owned one would be
    // recommended back to its owner.
    const out = missingFromCollection(
      [{ name: "A$AP Rocky", tracks: 17 }],
      discographies([
        "a$ap rocky",
        disco("A$AP Rocky", [
          group("g1", "Don’t Be Dumb"),
          group("g2", "LONG.LIVE.A$AP"),
        ]),
      ]),
      [{ title: "Don't Be Dumb", groupId: null }]
    );
    expect(out.map((g) => g.title)).toEqual(["LONG.LIVE.A$AP"]);
  });

  it("leaves out singles and compilations", () => {
    const out = missingFromCollection(
      [{ name: "Don Toliver", tracks: 32 }],
      discographies([
        "don toliver",
        disco("Don Toliver", [
          group("g0", "Life of a DON"),
          group("g1", "Heaven or Hell", "Album"),
          group("g2", "No Idea", "Single"),
          group("g3", "Greatest Hits", "Compilation"),
          group("g4", "Donny Womack", "EP"),
        ]),
      ]),
      [{ title: "Life of a DON", groupId: null }]
    );
    expect(out.map((g) => g.title).sort()).toEqual([
      "Donny Womack",
      "Heaven or Hell",
    ]);
  });

  it("ranks the acts with the most tracks first", () => {
    const out = missingFromCollection(
      [
        { name: "Small", tracks: 2 },
        { name: "Big", tracks: 50 },
      ],
      discographies(
        [
          "small",
          disco("Small", [group("s0", "Owned Small"), group("s1", "Small Album")]),
        ],
        ["big", disco("Big", [group("b0", "Owned Big"), group("b1", "Big Album")])]
      ),
      [
        { title: "Owned Small", groupId: null },
        { title: "Owned Big", groupId: null },
      ]
    );
    expect(out.map((g) => g.title)).toEqual(["Big Album", "Small Album"]);
  });

  it("credits a shared album once, to the act with more tracks held", () => {
    const shared = group("shared", "Joint Record");
    const out = missingFromCollection(
      [
        { name: "Guest", tracks: 3 },
        { name: "Lead", tracks: 40 },
      ],
      discographies(
        ["guest", disco("Guest", [group("x", "Owned Guest"), shared])],
        ["lead", disco("Lead", [group("y", "Owned Lead"), shared])]
      ),
      [
        { title: "Owned Guest", groupId: null },
        { title: "Owned Lead", groupId: null },
      ]
    );
    expect(out).toHaveLength(1);
    expect(out[0]?.forArtist).toBe("Lead");
  });

  it("orders one act's albums newest first", () => {
    const out = missingFromCollection(
      [{ name: "Act", tracks: 10 }],
      discographies([
        "act",
        disco("Act", [
          group("g0", "Owned"),
          group("g1", "Older", "Album", "2011-01-01"),
          group("g2", "Newer", "Album", "2019-01-01"),
        ]),
      ]),
      [{ title: "Owned", groupId: null }]
    );
    expect(out.map((g) => g.title)).toEqual(["Newer", "Older"]);
  });

  it("honours the limit", () => {
    const out = missingFromCollection(
      [{ name: "Act", tracks: 10 }],
      discographies([
        "act",
        disco("Act", [
          group("g0", "Owned"),
          group("g1", "One"),
          group("g2", "Two"),
          group("g3", "Three"),
        ]),
      ]),
      [{ title: "Owned", groupId: null }],
      { limit: 2 }
    );
    expect(out).toHaveLength(2);
  });

  it("returns nothing for an act with no stored discography", () => {
    const out = missingFromCollection(
      [{ name: "Unknown Act", tracks: 5 }],
      discographies(),
      [{ title: "Something", groupId: null }]
    );
    expect(out).toEqual([]);
  });
});

describe("edition qualifiers", () => {
  it("does not recommend an album back when a variant edition is held", () => {
    // The library holds "2093 (P2)"; MusicBrainz lists the group as "2093".
    const out = missingFromCollection(
      [{ name: "Yeat", tracks: 48 }],
      discographies([
        "yeat",
        disco("Yeat", [group("g0", "LYFESTYLE"), group("g1", "2093")]),
      ]),
      [
        { title: "LYFESTYLE", groupId: null },
        { title: "2093 (P2)", groupId: null },
      ]
    );
    expect(out).toEqual([]);
  });

  it("keeps two albums apart when one title merely contains the other", () => {
    // "Alivë" and "2 Alivë" are different Yeat records. A looser rule would
    // fold them together and stop recommending one.
    const out = missingFromCollection(
      [{ name: "Yeat", tracks: 48 }],
      discographies([
        "yeat",
        disco("Yeat", [group("g0", "2 Alivë"), group("g1", "Alivë")]),
      ]),
      [{ title: "2 Alivë", groupId: null }]
    );
    expect(out.map((g) => g.title)).toEqual(["Alivë"]);
  });

  it("still corroborates when only the variant edition is held", () => {
    // The owned title must be able to prove we resolved the right artist,
    // or the whole act gets skipped.
    const out = missingFromCollection(
      [{ name: "Yeat", tracks: 48 }],
      discographies([
        "yeat",
        disco("Yeat", [group("g0", "2093"), group("g1", "Lyfë")]),
      ]),
      [{ title: "2093 (P2)", groupId: null }]
    );
    expect(out.map((g) => g.title)).toEqual(["Lyfë"]);
  });
});
