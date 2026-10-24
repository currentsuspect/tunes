import { describe, expect, it } from "vitest";
import {
  ENRICH_RETRY_BASE_MS,
  ENRICH_RETRY_MAX_MS,
  enrichBackoffMs,
  enrichRetryDue,
  flattenReleaseTracks,
  MusicBrainzClient,
  parseArtistTitle,
  splitArtistNames,
} from "../src/enrich.js";
import { pickFirstAlbum } from "../src/enrich.js";

describe("enrichBackoffMs", () => {
  it("does not delay a track nobody has tried yet", () => {
    expect(enrichBackoffMs(0)).toBe(0);
  });

  it("doubles per failed attempt", () => {
    expect(enrichBackoffMs(1)).toBe(ENRICH_RETRY_BASE_MS);
    expect(enrichBackoffMs(2)).toBe(ENRICH_RETRY_BASE_MS * 2);
    expect(enrichBackoffMs(3)).toBe(ENRICH_RETRY_BASE_MS * 4);
  });

  it("caps at a week no matter how many attempts pile up", () => {
    expect(enrichBackoffMs(50)).toBe(ENRICH_RETRY_MAX_MS);
    expect(enrichBackoffMs(5000)).toBe(ENRICH_RETRY_MAX_MS);
  });
});

describe("enrichRetryDue", () => {
  const now = Date.parse("2026-09-05T20:00:00.000Z");

  it("lets an untried track through immediately", () => {
    expect(enrichRetryDue(undefined, now)).toBe(true);
  });

  it("suppresses a track that just failed", () => {
    // The regression: a permanent miss used to re-run the whole provider
    // cascade on every 90s pass because the failure was never recorded.
    const justFailed = { attempts: 1, lastAttemptAt: new Date(now - 90_000).toISOString() };
    expect(enrichRetryDue(justFailed, now)).toBe(false);
  });

  it("releases the track once its backoff has elapsed", () => {
    const attempt = {
      attempts: 1,
      lastAttemptAt: new Date(now - ENRICH_RETRY_BASE_MS).toISOString(),
    };
    expect(enrichRetryDue(attempt, now)).toBe(true);
  });

  it("keeps suppressing while a longer backoff is still running", () => {
    const attempt = {
      attempts: 3,
      lastAttemptAt: new Date(now - ENRICH_RETRY_BASE_MS * 2).toISOString(),
    };
    expect(enrichRetryDue(attempt, now)).toBe(false);
  });

  it("fails open on an unparseable timestamp rather than stranding the track", () => {
    expect(enrichRetryDue({ attempts: 4, lastAttemptAt: "not a date" }, now)).toBe(true);
  });
});

describe("splitArtistNames", () => {
  it("splits the Vorbis multi-artist separators", () => {
    expect(splitArtistNames("Yeat;Don Toliver")).toEqual(["Yeat", "Don Toliver"]);
    expect(splitArtistNames("Don Toliver/ HVN/")).toEqual(["Don Toliver", "HVN"]);
  });

  it("leaves commas alone — they occur inside real names", () => {
    expect(splitArtistNames("Tyler, The Creator")).toEqual(["Tyler, The Creator"]);
  });

  it("returns a single name unchanged", () => {
    expect(splitArtistNames("Yeat")).toEqual(["Yeat"]);
  });

  it("drops empties and duplicates", () => {
    expect(splitArtistNames("Yeat;;Yeat")).toEqual(["Yeat"]);
    expect(splitArtistNames("   ")).toEqual([]);
    expect(splitArtistNames(null)).toEqual([]);
    expect(splitArtistNames(undefined)).toEqual([]);
  });
});

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

describe("MusicBrainzClient.artistDiscography", () => {
  it("searches the artist and maps release groups", async () => {
    const calls: string[] = [];
    const replies: unknown[] = [
      { artists: [{ id: "mbid-1", name: "Don Toliver" }] },
      {
        "release-groups": [
          {
            id: "g1",
            title: "HARDSTONE PSYCHO",
            "primary-type": "Album",
            "first-release-date": "2024-08-09",
          },
          {
            id: "g2",
            title: "BROTHER STONE (FEAT. KODAK BLACK)",
            "primary-type": "Single",
            "first-release-date": "2024-05-17",
          },
        ],
      },
    ];
    const fetcher = async (url: string) => {
      calls.push(url);
      const body = replies.shift() ?? { artists: [] };
      return { ok: true, json: async () => body } as Response;
    };
    const mb = new MusicBrainzClient(
      "tunes/test",
      "",
      fetcher as unknown as typeof fetch
    );
    const d = await mb.artistDiscography("Don Toliver");
    expect(d?.mbid).toBe("mbid-1");
    expect(d?.groups).toHaveLength(2);
    expect(d?.groups[0]).toMatchObject({
      id: "g1",
      title: "HARDSTONE PSYCHO",
      type: "Album",
      year: "2024",
      date: "2024-08-09",
    });
    expect(calls.some((u) => u.includes("/ws/2/artist?query="))).toBe(true);
    expect(
      calls.some((u) => u.includes("/ws/2/artist/mbid-1?inc=release-groups"))
    ).toBe(true);
  });

});

describe("MusicBrainzClient.searchArtists", () => {
  it("queries the artist index and maps hits", async () => {
    const fetcher = async (url: string) => {
      expect(url).toContain("/ws/2/artist?query=");
      expect(url).toContain(encodeURIComponent('artist:"OCTANE"'));
      return {
        ok: true,
        json: async () => ({
          artists: [
            { id: "m1", name: "OCTANE", type: "Group", disambiguation: "US rap duo", score: 100 },
            { id: "m2", name: "Octane", type: "Person", disambiguation: null, score: 42 },
          ],
        }),
      } as Response;
    };
    const mb = new MusicBrainzClient("tunes/test", "", fetcher as unknown as typeof fetch);
    const hits = await mb.searchArtists("OCTANE");
    expect(hits).toHaveLength(2);
    expect(hits[0]).toMatchObject({
      name: "OCTANE",
      mbid: "m1",
      type: "Group",
      disambiguation: "US rap duo",
      score: 100,
    });
  });

  it("returns nothing on a missing index", async () => {
    const fetcher = async () => ({ ok: true, json: async () => ({ artists: [] }) }) as Response;
    const mb = new MusicBrainzClient("tunes/test", "", fetcher as unknown as typeof fetch);
    expect(await mb.searchArtists("zzz")).toEqual([]);
  });
});

describe("the record a song first came out on", () => {
  const rec = (title: string, releases: unknown[], disambiguation = "") =>
    ({ id: title, title, disambiguation, "artist-credit": [{ name: "Michael Jackson" }], releases }) as never;
  const rel = (id: string, date: string, type: string, secondary: string[] = [], title = id) => ({
    id,
    title,
    status: "Official",
    date,
    "release-group": { id: `g-${id}`, title, "primary-type": type, "secondary-types": secondary },
  });
  it("earliest album, not a compilation, a live record or a remaster's later date", () => {
    const got = pickFirstAlbum(
      [
        rec("Smooth Criminal", [rel("number-ones", "2003", "Album", ["Compilation"]), rel("bad-2012", "2012", "Album", [], "Bad")]),
        rec("Smooth Criminal", [rel("bad", "1987-08-31", "Album", [], "Bad")]),
        rec("Smooth Criminal", [rel("brunei", "1996", "Album", ["Live"])], "live"),
        rec("Smooth Criminal", [rel("single", "1988", "Single", [], "Smooth Criminal")]),
      ],
      "Smooth Criminal (2012 Remaster)"
    );
    expect(got?.title).toBe("Bad");
    expect(got?.year).toBe("1987");
    expect(got?.groupId).toBe("g-bad");
  });
  it("nothing when only other songs come back", () => {
    expect(pickFirstAlbum([rec("Billie Jean", [rel("thriller", "1982", "Album")])], "Smooth Criminal")).toBeNull();
  });
});
