import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { AboutService, type AboutTrack } from "../src/about.js";
import {
  AboutStore,
  GeniusAboutClient,
  peopleAround,
  sameCredit,
  songAboutFrom,
  workOf,
  type SongAbout,
} from "../src/genius.js";

// Yeat's "Griddlë" as Genius's song API answered on 24 Oct, cut down.
const griddle = {
  id: 13303522,
  url: "https://genius.com/Yeat-griddle-lyrics",
  description: { plain: "“Griddlë” serves as the 4th track on Yeat’s sixth studio album, ADL." },
  release_date: "2026-03-27",
  producer_artists: [{ id: 1, name: "BNYX®" }, { id: 2, name: "Bangs (Producer)" }],
  writer_artists: [{ id: 3, name: "Yeat" }, { id: 4, name: "Don Toliver" }],
  featured_artists: [],
  custom_performances: [
    { label: "Mixing Engineer", artists: [{ id: 3, name: "Yeat" }] },
    { label: "Label", artists: [{ id: 9, name: "Field Trip Recordings" }] },
  ],
  song_relationships: [
    { relationship_type: "samples", songs: [{ title: "Old One", primary_artist: { name: "Someone" } }] },
    { relationship_type: "translations", songs: [{ title: "Griddlë (Русский перевод)", primary_artist: { name: "Genius Russian" } }] },
    { relationship_type: "sampled_in", songs: [] },
  ],
  album: { id: 1168170, name: "ADL" },
  primary_artist: { id: 1476681, name: "Yeat" },
};

const yeat: AboutTrack = {
  sha: "a".repeat(64),
  title: "Griddlë",
  artist: "Yeat (feat. Don Toliver)",
  primaryArtist: "Yeat",
  album: "ADL (Deluxe)",
  releaseId: "name:yeat|adl (deluxe)",
  durationMs: 157000,
};

describe("a song, as Genius tells it", () => {
  it("keeps its story, makers, credits and connections", () => {
    const s = songAboutFrom(griddle);
    expect(s.description).toContain("4th track");
    expect(s.producers).toEqual(["BNYX®", "Bangs (Producer)"]);
    expect(s.writers).toEqual(["Yeat", "Don Toliver"]);
    expect(s.credits).toContainEqual({ role: "Label", names: ["Field Trip Recordings"] });
    expect(s.album).toEqual({ id: 1168170, name: "ADL" });
    expect(s.artist).toEqual({ id: 1476681, name: "Yeat" });
  });

  it("leaves translations and empty connections out", () => {
    expect(songAboutFrom(griddle).connections).toEqual([
      { type: "samples", songs: [{ title: "Old One", artist: "Someone" }] },
    ]);
  });

  it("treats Genius's “?” and missing write-ups as none", () => {
    expect(songAboutFrom({ ...griddle, description: { plain: "?" } }).description).toBeNull();
    expect(songAboutFrom({ ...griddle, description: undefined }).description).toBeNull();
  });
});

describe("people and their work", () => {
  const s = songAboutFrom(griddle);

  it("knows a producer by their name, whatever Genius adds to it", () => {
    expect(sameCredit("Bangs (Producer)", "Bangs")).toBe(true);
    expect(sameCredit("BNYX®", "BNYX")).toBe(true);
    expect(sameCredit("Yeat", "Yeats")).toBe(false);
  });

  it("finds what a person made, and how", () => {
    expect(workOf("BNYX", [["a", s]])).toEqual([{ sha: "a", roles: ["produced"] }]);
    expect(workOf("Don Toliver", [["a", s]])).toEqual([{ sha: "a", roles: ["written"] }]);
    expect(workOf("Drake", [["a", s]])).toEqual([]);
  });

  it("lists the people around an artist by songs, the artist left out", () => {
    const other: SongAbout = { ...s, geniusId: 2, producers: ["BNYX®"], featured: ["Don Toliver"] };
    const people = peopleAround("Yeat", [s, other]);
    expect(people[0]).toEqual({ name: "BNYX®", songs: 2, roles: ["produced"] });
    expect(people.map((p) => p.name)).toContain("Bangs");
    expect(people.map((p) => p.name)).not.toContain("Yeat");
  });
});

/** A Genius that answers from fixtures and counts what it was asked. */
function fakeGenius(): { fetcher: typeof fetch; asked: string[] } {
  const asked: string[] = [];
  const fetcher = (async (input: string | URL | Request) => {
    const url = String(input);
    asked.push(url.replace("https://genius.com/api", ""));
    const ok = (response: unknown) => new Response(JSON.stringify({ response }), { status: 200 });
    if (url.includes("/search/song")) {
      return ok({ sections: [{ hits: [{ result: { id: 13303522, title: "Griddlë", primary_artist: { name: "Yeat" } } }] }] });
    }
    if (url.includes("/songs/13303522")) return ok({ song: griddle });
    if (url.includes("/albums/1168170")) {
      return ok({ album: { name: "ADL", url: "u", description_preview: "ADL is the sixth studio album.", release_date: "2026-03-27", song_performances: [] } });
    }
    if (url.includes("/artists/1476681")) {
      return ok({ artist: { name: "Yeat", url: "u", description: { plain: "Noah Olivier Smith, better known as Yeat." }, alternate_names: ["Kranky Kranky"], image_url: "img" } });
    }
    return new Response("{}", { status: 404 });
  }) as typeof fetch;
  return { fetcher, asked };
}

describe("the about pages", () => {
  it("answer from Genius the first time, and from disk after", async () => {
    const dir = await mkdtemp(join(tmpdir(), "about-"));
    try {
      const g = fakeGenius();
      const store = await new AboutStore(join(dir, "about.json")).load();
      const service = new AboutService(store, new GeniusAboutClient(g.fetcher), () => [yeat], { warn: () => {}, info: () => {} } as never);
      const first = await service.song(yeat.sha);
      expect(first?.song?.producers).toContain("BNYX®");
      expect(first?.album?.description).toBe("ADL is the sixth studio album.");
      const askedOnce = g.asked.length;
      await service.song(yeat.sha);
      expect(g.asked.length).toBe(askedOnce);

      const again = new AboutService(await new AboutStore(join(dir, "about.json")).load(), new GeniusAboutClient(g.fetcher), () => [yeat], { warn: () => {}, info: () => {} } as never);
      const artist = await again.artist("Yeat");
      expect(artist.artist?.alternateNames).toContain("Kranky Kranky");
      expect(artist.people.map((p) => p.name)).toContain("BNYX®");
      expect(again.person("BNYX").work).toEqual([{ sha: yeat.sha, roles: ["produced"] }]);
      expect((await again.album(yeat.releaseId!)).album?.name).toBe("ADL");
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });

  it("the pass asks about each song once, and remembers Genius not knowing one", async () => {
    const dir = await mkdtemp(join(tmpdir(), "about-"));
    try {
      const g = fakeGenius();
      const unknown: AboutTrack = { ...yeat, sha: "b".repeat(64), title: "Nothing Like It", primaryArtist: "Nobody" };
      const service = new AboutService(await new AboutStore(join(dir, "about.json")).load(), new GeniusAboutClient(g.fetcher), () => [yeat, unknown], { warn: () => {}, info: () => {} } as never);
      expect(await service.pass(10, 0)).toEqual({ asked: 2, found: 1 });
      expect(await service.pass(10, 0)).toEqual({ asked: 0, found: 0 });
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});
