import { describe, expect, it } from "vitest";
import { buildManifest, releaseArtKey } from "../src/manifest.js";
import type { TrackEnrichment } from "../src/manifest.js";
import type { ProbeResult } from "../src/probe.js";

function probe(over: Partial<ProbeResult> = {}): ProbeResult {
  return {
    sha: "a".repeat(64),
    size: 1000,
    codec: "flac",
    sampleRate: 44100,
    channels: 2,
    bitrate: 950000,
    durationMs: 125000,
    tags: {},
    hasEmbeddedArt: false,
    audioSha: null,
    probedAt: "2026-08-27T00:00:00Z",
    ...over,
  };
}

function enrichment(over: Partial<TrackEnrichment> = {}): TrackEnrichment {
  return {
    artist: null,
    album: null,
    year: null,
    artSha: null,
    releaseId: null,
    releaseType: null,
    trackNumber: null,
    discNumber: null,
    totalTracks: null,
    membership: [],
    ...over,
  };
}

describe("buildManifest", () => {
  it("prefers embedded tags, then caption, then filename", () => {
    const tagged = buildManifest([probe({ tags: { title: "Tagged Title", artist: "Tag Artist" } })]);
    expect(tagged.tracks[0]?.title).toBe("Tagged Title");
    expect(tagged.tracks[0]?.artist).toBe("Tag Artist");

    const captioned = buildManifest(
      [probe()],
      new Map([["a".repeat(64), { caption: "Caption Title", fileName: "whatever.flac" }]])
    );
    expect(captioned.tracks[0]?.title).toBe("Caption Title");

    const filenamed = buildManifest(
      [probe()],
      new Map([["a".repeat(64), { caption: "", fileName: "Travis Scott - ESCAPE PLAN.flac" }]])
    );
    // Filenames with the "Artist - Title" shape contribute title + artist
    // separately; the joined "Travis Scott - ESCAPE PLAN" is no longer
    // the title itself, just the original filename string we parsed.
    expect(filenamed.tracks[0]?.title).toBe("ESCAPE PLAN");
    expect(filenamed.tracks[0]?.artist).toBe("Travis Scott");
  });

  it("falls back to filename-parsed artist when no tags and no enrichment", () => {
    const m = buildManifest(
      [probe()],
      new Map([["a".repeat(64), { caption: null, fileName: "Some Artist - Track.flac" }]])
    );
    expect(m.tracks[0]?.artist).toBe("Some Artist");
    expect(m.tracks[0]?.title).toBe("Track");
    expect(m.tracks[0]?.album).toBe("unknown album");
    expect(m.tracks[0]?.artSha).toBeNull();
  });

  it("enrichment fills artist/album/art only when tags are absent", () => {
    const enrich = new Map([
      [
        "a".repeat(64),
        { artist: "Travis Scott", album: "ESCAPE PLAN", year: "2021", artSha: "c".repeat(64), releaseId: "mb:x", releaseType: "Single", trackNumber: 1, discNumber: null, totalTracks: null, membership: [] },
      ],
    ]);
    const untagged = buildManifest([probe()], new Map(), enrich);
    expect(untagged.tracks[0]?.artist).toBe("Travis Scott");
    expect(untagged.tracks[0]?.album).toBe("ESCAPE PLAN");
    expect(untagged.tracks[0]?.year).toBe("2021");
    expect(untagged.tracks[0]?.artSha).toBe("c".repeat(64));

    const tagged = buildManifest(
      [probe({ tags: { title: "T", artist: "Real Tag Artist", album: "Real Album" } })],
      new Map(),
      enrich
    );
    expect(tagged.tracks[0]?.artist).toBe("Real Tag Artist");
    expect(tagged.tracks[0]?.album).toBe("Real Album");
  });

  it("is deterministic: same input, same integrity", () => {
    const meta = new Map([["a".repeat(64), { caption: "x", fileName: "y.flac" }]]);
    const m1 = buildManifest([probe(), probe({ sha: "b".repeat(64), tags: { title: "T" } })], meta);
    const m2 = buildManifest([probe(), probe({ sha: "b".repeat(64), tags: { title: "T" } })], meta);
    expect(m1.integrity).toBe(m2.integrity);
    expect(m1.tracks.map((t) => t.sha)).toEqual(m2.tracks.map((t) => t.sha));
  });

  it("groups tracks of one release into a single release entity", () => {
    const enrich = new Map([
      [
        "a".repeat(64),
        {
          artist: "Travis Scott",
          album: "ESCAPE PLAN / MAFIA",
          year: "2021",
          artSha: "c".repeat(64),
          releaseId: "sp:album1",
          releaseType: "single",
          trackNumber: 1,
          discNumber: null,
          totalTracks: null,
                membership: [],
                },
      ],
      [
        "b".repeat(64),
        {
          artist: "Travis Scott",
          album: "ESCAPE PLAN / MAFIA",
          year: "2021",
          artSha: null,
          releaseId: "sp:album1",
          releaseType: "single",
          trackNumber: 1,
          discNumber: null,
          totalTracks: null,
                membership: [],
                },
      ],
    ]);
    const m = buildManifest([probe(), probe({ sha: "b".repeat(64) })], new Map(), enrich);
    expect(m.schema).toBe(4);
    expect(m.releases.length).toBe(1);
    const r = m.releases[0]!;
    expect(r.id).toBe("sp:album1");
    expect(r.trackShas).toEqual(["a".repeat(64), "b".repeat(64)]);
    expect(r.artSha).toBe("c".repeat(64));
    expect(m.tracks[0]?.releaseId).toBe("sp:album1");
  });

  it("merges same-artist single/combo releases across sources when years align", () => {
    const enrich = new Map([
      [
        "a".repeat(64),
        {
          artist: "Ken Carson",
          album: "cartunez",
          year: "2026",
          artSha: null,
          releaseId: "mb:one",
          releaseType: null,
          trackNumber: 1,
          discNumber: null,
          totalTracks: null,
                membership: [],
                },
      ],
      [
        "b".repeat(64),
        {
          artist: "Ken Carson",
          album: "xperiment - cartunez",
          year: "2026",
          artSha: null,
          releaseId: "sp:two",
          releaseType: null,
          trackNumber: 2,
          discNumber: null,
          totalTracks: null,
                membership: [],
                },
      ],
    ]);
    const m = buildManifest([probe(), probe({ sha: "b".repeat(64) })], new Map(), enrich);
    expect(m.releases.length).toBe(1);
    expect(m.releases[0]?.title).toBe("xperiment - cartunez");
    expect(m.releases[0]?.trackShas).toHaveLength(2);
  });

  it("consolidates multi-piece drops into the full album card", () => {
    const mk = (
      i: number,
      sha: string,
      album: string,
      releaseId: string,
      artSha: string | null = null
    ) => ({
      sha,
      artist: "Ken Carson",
      album,
      year: "2026",
      artSha,
      releaseId,
      releaseType: null,
      trackNumber: i,
      discNumber: null,
          totalTracks: null,
        membership: [],
        });
    const enrich = new Map<string, TrackEnrichment>();
    for (let i = 0; i < 3; i++) {
      enrich.set(`a${i}`.repeat(32), mk(i, `a${i}`.repeat(32), "cartunez", "mb:c", "c".repeat(64)));
    }
    for (let i = 0; i < 6; i++) enrich.set(`b${i}`.repeat(32), mk(i, `b${i}`.repeat(32), "xperiment", "mb:x"));
    for (let i = 0; i < 20; i++) enrich.set(`c${i}`.repeat(32), mk(i, `c${i}`.repeat(32), "xperiment - cartunez", "mb:f"));
    const m = buildManifest(
      [],
      new Map(),
      enrich,
      [...enrich.keys()].map((sha) => ({ sha, size: 100 }))
    );
    expect(m.releases.length).toBe(1);
    expect(m.releases[0]?.title).toBe("xperiment - cartunez");
    expect(m.releases[0]?.trackShas).toHaveLength(29);
    expect(m.releases[0]?.artSha).toBe("c".repeat(64)); // art inherited from member tracks
  });

  it("folds absorbed unknown-album strays into one card", () => {
    const mk = (i: number, sha: string) => ({
      sha,
      artist: null as string | null,
      album: null as string | null,
      year: null as string | null,
      artSha: null,
      releaseId: null,
      releaseType: null,
      trackNumber: null,
      discNumber: null,
          totalTracks: null,
        membership: [],
        });
    const enrich = new Map<string, TrackEnrichment>();
    for (let i = 0; i < 2; i++) enrich.set(`a${i}`.repeat(32), mk(i, `a${i}`.repeat(32)));
    for (let i = 0; i < 5; i++) enrich.set(`b${i}`.repeat(32), mk(i, `b${i}`.repeat(32)));
    const m = buildManifest(
      [],
      new Map(),
      enrich,
      [...enrich.keys()].map((sha) => ({ sha, size: 100 }))
    );
    expect(m.releases.length).toBe(1);
    expect(m.releases[0]?.trackShas).toHaveLength(7);
  });

  it("folds three anonymous stray cards into one", () => {
    const mk = (i: number, sha: string) => ({
      sha,
      artist: null as string | null,
      album: null as string | null,
      year: null as string | null,
      artSha: null,
      releaseId: null,
      releaseType: null,
      trackNumber: null,
      discNumber: null,
          totalTracks: null,
        membership: [],
        });
    const enrich = new Map<string, TrackEnrichment>();
    for (let i = 0; i < 6; i++) enrich.set(`x${i}`.repeat(32), mk(i, `x${i}`.repeat(32)));
    const m = buildManifest(
      [],
      new Map(),
      enrich,
      [...enrich.keys()].map((sha) => ({ sha, size: 100 }))
    );
    expect(m.releases.length).toBe(1);
    expect(m.releases[0]?.trackShas).toHaveLength(6);
  });

  it("keeps same-token releases apart when years differ", () => {
    const enrich = new Map([
      [
        "a".repeat(64),
        {
          artist: "Artist",
          album: "Cartunez",
          year: "2020",
          artSha: null,
          releaseId: "mb:one",
          releaseType: null,
          trackNumber: 1,
          discNumber: null,
          totalTracks: null,
                membership: [],
                },
      ],
      [
        "b".repeat(64),
        {
          artist: "Artist",
          album: "Cartunez (Deluxe)",
          year: "2024",
          artSha: null,
          releaseId: "mb:two",
          releaseType: null,
          trackNumber: 1,
          discNumber: null,
          totalTracks: null,
                membership: [],
                },
      ],
    ]);
    const m = buildManifest([probe(), probe({ sha: "b".repeat(64) })], new Map(), enrich);
    expect(m.releases.length).toBe(2);
  });

  it("never merges releases that differ in year even with token-subsets", () => {
    const enrich = new Map([
      [
        "a".repeat(64),
        {
          artist: "Travis Scott",
          album: "ESCAPE PLAN",
          year: "2021",
          artSha: null,
          releaseId: "mb:one",
          releaseType: "Single",
          trackNumber: 1,
          discNumber: null,
          totalTracks: null,
                membership: [],
                },
      ],
      [
        "b".repeat(64),
        {
          artist: "Travis Scott",
          album: "ESCAPE PLAN / MAFIA",
          year: "2023",
          artSha: null,
          releaseId: "sp:two",
          releaseType: "single",
          trackNumber: 1,
          discNumber: null,
          totalTracks: null,
                membership: [],
                },
      ],
    ]);
    const m = buildManifest([probe(), probe({ sha: "b".repeat(64) })], new Map(), enrich);
    expect(m.releases.length).toBe(2);
  });

  it("keeps a single in both the single card and its album (membership)", () => {
    const enrich = new Map<string, TrackEnrichment>([
      [
        "a".repeat(64),
        {
          artist: "Don Toliver",
          album: "BROTHER STONE (FEAT. KODAK BLACK)",
          year: "2024",
          artSha: null,
          releaseId: "mb:single",
          releaseType: "Single",
          trackNumber: 1,
          discNumber: null,
          totalTracks: 1,
          membership: [{ id: "mb:album-x", position: 12, disc: 1 }],
        },
      ],
    ]);
    const m = buildManifest(
      [probe()],
      new Map(),
      enrich,
      [],
      [],
      new Map([
        ["mb:album-x", { title: "HARDSTONE PSYCHO", type: "Album", totalTracks: 15 }],
      ])
    );
    const single = m.releases.find((r) => r.id === "mb:single");
    const album = m.releases.find((r) => r.id === "mb:album-x");
    expect(single?.trackShas).toEqual(["a".repeat(64)]);
    expect(album?.trackShas).toEqual(["a".repeat(64)]);
    expect(album?.tracks[0]?.trackNumber).toBe(12);
    expect(album?.tracks[0]?.discNumber).toBe(1);
    expect(m.tracks[0]?.releaseIds).toEqual(["mb:single", "mb:album-x"]);
  });

  it("materializes an album card from linkmeta even with no primary tracks", () => {
    const enrich = new Map<string, TrackEnrichment>([
      [
        "a".repeat(64),
        {
          artist: "Don Toliver",
          album: "BROTHER STONE (FEAT. KODAK BLACK)",
          year: null,
          artSha: null,
          releaseId: "mb:single",
          releaseType: "Single",
          trackNumber: 1,
          discNumber: null,
          totalTracks: 1,
          membership: [{ id: "mb:album-y", position: 4, disc: null }],
        },
      ],
    ]);
    const m = buildManifest(
      [probe()],
      new Map(),
      enrich,
      [],
      [],
      new Map([
        ["mb:album-y", { title: "HARDSTONE PSYCHO", type: "Album", totalTracks: 15 }],
      ])
    );
    const album = m.releases.find((r) => r.id === "mb:album-y");
    expect(album?.title).toBe("HARDSTONE PSYCHO");
    expect(album?.type).toBe("Album");
    expect(album?.totalTracks).toBe(15);
    expect(album?.artist).toBe("Don Toliver");
    expect(album?.tracks[0]?.trackNumber).toBe(4);
  });

  it("surfaces the release-group id from linkmeta on the release", () => {
    const enrich = new Map<string, TrackEnrichment>([
      [
        "a".repeat(64),
        {
          artist: "Don Toliver",
          album: "HARDSTONE PSYCHO",
          year: "2024",
          artSha: null,
          releaseId: "mb:rel",
          releaseType: "Album",
          trackNumber: 1,
          discNumber: null,
          totalTracks: 23,
          membership: [],
        },
      ],
    ]);
    const m = buildManifest(
      [probe()],
      new Map(),
      enrich,
      [],
      [],
      new Map([
        ["mb:rel", { title: "HARDSTONE PSYCHO", type: "Album", totalTracks: 23, groupId: "g1", date: "2024-08-09" }],
      ])
    );
    expect(m.releases[0]?.groupId).toBe("g1");
  });

  it("suppresses category/genre releases as entities", () => {
    const enrich = new Map([
      [
        "a".repeat(64),
        {
          artist: "Don Toliver",
          album: "Alt Rap",
          year: "2026",
          artSha: null,
          releaseId: "mb:venue",
          releaseType: null,
          trackNumber: null,
          discNumber: null,
          totalTracks: null,
                membership: [],
                },
      ],
    ]);
    const m = buildManifest([probe()], new Map(), enrich);
    expect(m.releases.length).toBe(1);
    expect(m.releases[0]?.title).toBe("unknown album");
    expect(m.releases[0]?.artist).toBe("Don Toliver");
    expect(m.tracks[0]?.album).toBe("unknown album");
    // The genre-compilation id is dropped, but the track is still grouped into
    // a release, so it must name the release that holds it. Reporting null here
    // left a track sitting inside a release it claimed not to belong to.
    expect(m.tracks[0]?.releaseId).toBe(m.releases[0]?.id);
    expect(m.tracks[0]?.releaseIds).not.toContain("mb:x");
    expect(m.tracks[0]?.artSha).toBeNull();
  });

  it("merges single/combo releases whose titles are token-subsets", () => {
    const enrich = new Map([
      [
        "a".repeat(64),
        {
          artist: "Travis Scott",
          album: "ESCAPE PLAN",
          year: "2021",
          artSha: "c".repeat(64),
          releaseId: "mb:one",
          releaseType: null,
          trackNumber: 1,
          discNumber: null,
          totalTracks: null,
                membership: [],
                },
      ],
      [
        "b".repeat(64),
        {
          artist: "Travis Scott",
          album: "ESCAPE PLAN / MAFIA",
          year: "2021",
          artSha: null,
          releaseId: "mb:two",
          releaseType: null,
          trackNumber: 2,
          discNumber: null,
          totalTracks: null,
                membership: [],
                },
      ],
    ]);
    const m = buildManifest([probe(), probe({ sha: "b".repeat(64) })], new Map(), enrich);
    expect(m.releases.length).toBe(1);
    expect(m.releases[0]?.title).toBe("ESCAPE PLAN / MAFIA");
    expect(m.releases[0]?.trackShas).toEqual(["a".repeat(64), "b".repeat(64)]);
  });

  it("strips the 'Artist - ' prefix from filename titles when enriched", () => {
    const m = buildManifest(
      [probe()],
      new Map([
        ["a".repeat(64), { caption: null, fileName: "Don Toliver - Smoke (feat. HVN).flac" }],
      ]),
      new Map([
        [
          "a".repeat(64),
          {
            artist: "Don Toliver",
            album: "Life of a DON",
            year: "2021",
            artSha: null,
            releaseId: "mb:rel",
            releaseType: null,
            trackNumber: null,
            discNumber: null,
          totalTracks: null,
                    membership: [],
                    },
        ],
      ])
    );
    expect(m.tracks[0]?.title).toBe("Smoke (feat. HVN)");
  });

  it("falls back to a normalized name key without an external id", () => {
    const m = buildManifest([probe(), probe({ sha: "b".repeat(64) })], new Map());
    expect(m.releases.length).toBe(1); // anonymous strays fold into one card
    const named = buildManifest(
      [probe(), probe({ sha: "b".repeat(64) })],
      new Map(),
      new Map([
        [
          "a".repeat(64),
          {
            artist: "Travis Scott",
            album: "MAFIA",
            year: "2021",
            artSha: null,
            releaseId: null,
            releaseType: null,
            trackNumber: null,
            discNumber: null,
          totalTracks: null,
                    membership: [],
                    },
        ],
        [
          "b".repeat(64),
          {
            artist: "Travis Scott",
            album: "ESCAPE PLAN",
            year: "2021",
            artSha: null,
            releaseId: null,
            releaseType: null,
            trackNumber: 1,
            discNumber: null,
          totalTracks: null,
                    membership: [],
                    },
        ],
      ])
    );
    expect(named.releases.length).toBe(2); // different albums, same artist
  });
});
  it("merges same-title split cards regardless of size and lifts the total", () => {
    const mk = (i: number, sha: string, releaseId: string, total: number | null = null) => ({
      sha,
      artist: "Don Toliver",
      album: "HARDSTONE PSYCHO",
      year: "2024",
      artSha: null,
      releaseId,
      releaseType: "Album",
      trackNumber: i,
      discNumber: null,
      totalTracks: total,
      membership: [],
    });
    const enrich = new Map<string, TrackEnrichment>();
    for (let i = 0; i < 14; i++) enrich.set(`a${i}`.repeat(32), mk(i, `a${i}`.repeat(32), "sp:album", null));
    for (let i = 0; i < 16; i++) enrich.set(`b${i}`.repeat(32), mk(i, `b${i}`.repeat(32), "mb:album", 23));
    const m = buildManifest([], new Map(), enrich, [...enrich.keys()].map((sha) => ({ sha, size: 1 })));
    expect(m.releases).toHaveLength(1);
    expect(m.releases[0]?.trackShas.length).toBe(30);
    expect(m.releases[0]?.totalTracks).toBe(30);
  });

  it("carries addedAt per track from the lookup map", () => {
    const sha = "a".repeat(64);
    const other = "b".repeat(64);
    const added = new Map<string, string>([
      [sha, "2026-08-30T10:00:00.000Z"],
    ]);
    const m = buildManifest(
      [probe({ sha }), probe({ sha: other })],
      new Map(),
      new Map(),
      [],
      [],
      new Map(),
      added,
    );
    expect(m.tracks[0]?.addedAt).toBe("2026-08-30T10:00:00.000Z");
    expect(m.tracks[1]?.addedAt).toBeNull();
  });

  it("addedAt defaults to null when the lookup map is empty", () => {
    const m = buildManifest([probe()]);
    expect(m.tracks[0]?.addedAt).toBeNull();
  });

  it("exposes embedded tag values on every track", () => {
    const m = buildManifest([
      probe({ tags: { title: "T", artist: "A", album: "B", year: "2024" } }),
    ]);
    const t = m.tracks[0]!;
    expect(t.embeddedTitle).toBe("T");
    expect(t.embeddedArtist).toBe("A");
    expect(t.embeddedAlbum).toBe("B");
    expect(t.embeddedYear).toBe("2024");
  });

  it("embedded fields are null when no tags are present", () => {
    const m = buildManifest([probe()]);
    const t = m.tracks[0]!;
    expect(t.embeddedTitle).toBeNull();
    expect(t.embeddedArtist).toBeNull();
    expect(t.embeddedAlbum).toBeNull();
    expect(t.embeddedYear).toBeNull();
  });

  it("uses cover art lifted out of the file when no provider supplied one", () => {
    const sha = "a".repeat(64);
    const art = new Map([[sha, "c".repeat(64)]]);
    const m = buildManifest([probe()], new Map(), new Map(), [], [], new Map(), new Map(), art);
    expect(m.tracks[0]?.artSha).toBe("c".repeat(64));
  });

  it("prefers the provider cover over the embedded one when both exist", () => {
    const sha = "a".repeat(64);
    const enrich = new Map<string, TrackEnrichment>([
      [sha, enrichment({ artist: "A", album: "B", artSha: "d".repeat(64), releaseId: "mb:x" })],
    ]);
    const art = new Map([[sha, "c".repeat(64)]]);
    const m = buildManifest([probe()], new Map(), enrich, [], [], new Map(), new Map(), art);
    expect(m.tracks[0]?.artSha).toBe("d".repeat(64));
  });

  it("keeps the embedded cover even when a genre-compilation match is dropped", () => {
    const sha = "a".repeat(64);
    const enrich = new Map<string, TrackEnrichment>([
      [sha, enrichment({ artist: "A", album: "Trap", releaseId: "mb:x" })],
    ]);
    const art = new Map([[sha, "c".repeat(64)]]);
    const m = buildManifest([probe()], new Map(), enrich, [], [], new Map(), new Map(), art);
    expect(m.tracks[0]?.artSha).toBe("c".repeat(64));
  });

  it("keeps the file's own album when a genre compilation would have blanked it", () => {
    // The regression: a MusicBrainz match onto a "Trap" compilation forced the
    // album to "unknown album" even when the file said LYFESTYLE.
    const sha = "a".repeat(64);
    const enrich = new Map<string, TrackEnrichment>([
      [sha, enrichment({ artist: "A", album: "Trap", releaseId: "mb:x" })],
    ]);
    const m = buildManifest([probe({ tags: { album: "LYFESTYLE" } })], new Map(), enrich);
    expect(m.tracks[0]?.album).toBe("LYFESTYLE");
  });

  it("still drops a genre compilation when the file has no album of its own", () => {
    const sha = "a".repeat(64);
    const enrich = new Map<string, TrackEnrichment>([
      [sha, enrichment({ artist: "A", album: "Trap", releaseId: "mb:x" })],
    ]);
    const m = buildManifest([probe()], new Map(), enrich);
    expect(m.tracks[0]?.album).toBe("unknown album");
  });

  it("uses the tagger's own track and disc numbers over inferred positions", () => {
    const sha = "a".repeat(64);
    const enrich = new Map<string, TrackEnrichment>([
      [sha, enrichment({ artist: "A", album: "B", releaseId: "mb:x", trackNumber: 3, discNumber: 2, totalTracks: 9 })],
    ]);
    const m = buildManifest(
      [probe({ tags: { trackNumber: 7, discNumber: 1, totalTracks: 18 } })],
      new Map(),
      enrich
    );
    expect(m.tracks[0]?.trackNumber).toBe(7);
    expect(m.tracks[0]?.discNumber).toBe(1);
    expect(m.tracks[0]?.totalTracks).toBe(18);
  });

  it("falls back to inferred positions when the file is not numbered", () => {
    const sha = "a".repeat(64);
    const enrich = new Map<string, TrackEnrichment>([
      [sha, enrichment({ artist: "A", album: "B", releaseId: "mb:x", trackNumber: 3 })],
    ]);
    const m = buildManifest([probe()], new Map(), enrich);
    expect(m.tracks[0]?.trackNumber).toBe(3);
  });

describe("release grouping", () => {
  const sha = (n: number) => String(n).repeat(64).slice(0, 64);

  it("keeps one album together when each track credits different guests", () => {
    // The live regression: LYFESTYLE had 48 tracks across 9 credit strings and
    // shattered into 6 releases.
    const probes = [
      probe({ sha: sha(1), tags: { album: "LYFESTYLE", artist: "Yeat" } }),
      probe({ sha: sha(2), tags: { album: "LYFESTYLE", artist: "Yeat, Don Toliver" } }),
      probe({ sha: sha(3), tags: { album: "LYFESTYLE", artist: "Yeat;Summrs" } }),
      probe({ sha: sha(4), tags: { album: "LYFESTYLE", artist: "Yeat;Kodak Black" } }),
    ];
    const m = buildManifest(probes);
    expect(m.releases).toHaveLength(1);
    expect(m.releases[0]?.title).toBe("LYFESTYLE");
    expect(m.releases[0]?.artist).toBe("Yeat");
    expect(m.releases[0]?.trackShas).toHaveLength(4);
  });

  it("uses the album-artist tag when the tagger supplied one", () => {
    const probes = [
      probe({ sha: sha(1), tags: { album: "X", artist: "A, B", albumArtist: "A" } }),
      probe({ sha: sha(2), tags: { album: "X", artist: "C", albumArtist: "A" } }),
    ];
    const m = buildManifest(probes);
    expect(m.releases).toHaveLength(1);
    expect(m.releases[0]?.artist).toBe("A");
  });

  it("does not let a stale provider id split an album the file named", () => {
    const enrich = new Map<string, TrackEnrichment>([
      [sha(1), enrichment({ artist: "Yeat", album: "Trap Hits", releaseId: "mb:bogus" })],
    ]);
    const probes = [
      probe({ sha: sha(1), tags: { album: "LYFESTYLE", artist: "Yeat" } }),
      probe({ sha: sha(2), tags: { album: "LYFESTYLE", artist: "Yeat" } }),
    ];
    const m = buildManifest(probes, new Map(), enrich);
    expect(m.releases).toHaveLength(1);
    expect(m.releases[0]?.trackShas).toHaveLength(2);
  });

  it("still uses the provider id when the file named no album", () => {
    const enrich = new Map<string, TrackEnrichment>([
      [sha(1), enrichment({ artist: "A", album: "Real Album", releaseId: "mb:real" })],
      [sha(2), enrichment({ artist: "A", album: "Real Album", releaseId: "mb:real" })],
    ]);
    const m = buildManifest([probe({ sha: sha(1) }), probe({ sha: sha(2) })], new Map(), enrich);
    expect(m.releases).toHaveLength(1);
    expect(m.releases[0]?.id).toBe("mb:real");
  });

  it("keeps genuinely different albums apart", () => {
    const m = buildManifest([
      probe({ sha: sha(1), tags: { album: "LYFESTYLE", artist: "Yeat" } }),
      probe({ sha: sha(2), tags: { album: "2093", artist: "Yeat" } }),
    ]);
    expect(m.releases.map((r) => r.title).sort()).toEqual(["2093", "LYFESTYLE"]);
  });

  it("keeps same-titled albums by different acts apart", () => {
    const m = buildManifest([
      probe({ sha: sha(1), tags: { album: "Untitled", artist: "A" } }),
      probe({ sha: sha(2), tags: { album: "Untitled", artist: "B" } }),
    ]);
    expect(m.releases).toHaveLength(2);
  });

  it("exposes the guests it separated out", () => {
    const m = buildManifest([
      probe({ sha: sha(1), tags: { album: "X", artist: "Yeat;Don Toliver", title: "T (feat. Summrs)" } }),
    ]);
    expect(m.tracks[0]?.primaryArtist).toBe("Yeat");
    expect(m.tracks[0]?.featured).toEqual(["Don Toliver", "Summrs"]);
    // display artist is untouched
    expect(m.tracks[0]?.artist).toBe("Yeat;Don Toliver");
  });
});

describe("track/release linkage", () => {
  const sha = (n: number) => String(n).repeat(64).slice(0, 64);

  it("every track names a release that actually contains it", () => {
    const enrich = new Map<string, TrackEnrichment>([
      [sha(1), enrichment({ artist: "Yeat", album: "Trap Hits", releaseId: "mb:stale" })],
    ]);
    const m = buildManifest(
      [
        probe({ sha: sha(1), tags: { album: "LYFESTYLE", artist: "Yeat" } }),
        probe({ sha: sha(2), tags: { album: "LYFESTYLE", artist: "Yeat;Summrs" } }),
      ],
      new Map(),
      enrich
    );
    const byId = new Map(m.releases.map((r) => [r.id, r]));
    for (const t of m.tracks) {
      expect(t.releaseId).not.toBeNull();
      const rel = byId.get(t.releaseId!);
      expect(rel, `release ${t.releaseId} missing`).toBeDefined();
      expect(rel!.trackShas).toContain(t.sha);
    }
  });

  it("keeps the provider id as a cross-reference", () => {
    const enrich = new Map<string, TrackEnrichment>([
      [sha(1), enrichment({ artist: "Yeat", album: "Something", releaseId: "mb:stale" })],
    ]);
    const m = buildManifest(
      [probe({ sha: sha(1), tags: { album: "LYFESTYLE", artist: "Yeat" } })],
      new Map(),
      enrich
    );
    expect(m.tracks[0]?.releaseId).toBe("name:yeat|lyfestyle");
    expect(m.tracks[0]?.releaseIds).toContain("mb:stale");
  });

  it("does not mint a phantom extra release from provider membership when the file named the album", () => {
    const enrich = new Map<string, TrackEnrichment>([
      [
        sha(1),
        enrichment({
          artist: "Yeat",
          album: "Whatever",
          releaseId: "mb:a",
          membership: [{ id: "mb:b", position: 3, disc: 1 }],
        }),
      ],
    ]);
    const m = buildManifest(
      [probe({ sha: sha(1), tags: { album: "LYFESTYLE", artist: "Yeat" } })],
      new Map(),
      enrich
    );
    expect(m.releases).toHaveLength(1);
    expect(m.releases[0]?.id).toBe("name:yeat|lyfestyle");
  });
});

describe("joint albums", () => {
  const sha = (n: number) => String(n).repeat(64).slice(0, 64);

  it("treats a rotating-credit joint album as one release", () => {
    // CONGLOMERATE from the real library: no album-artist tag and the running
    // order of the three names changes track by track.
    const m = buildManifest([
      probe({ sha: sha(1), tags: { album: "CONGLOMERATE", artist: "Fimiguerrero, Len" } }),
      probe({ sha: sha(2), tags: { album: "CONGLOMERATE", artist: "Len, Fimiguerrero" } }),
      probe({ sha: sha(3), tags: { album: "CONGLOMERATE", artist: "Lancey Foux, Fimiguerrero, Len" } }),
      probe({ sha: sha(4), tags: { album: "CONGLOMERATE", artist: "Lancey Foux, Len" } }),
    ]);
    expect(m.releases).toHaveLength(1);
    expect(m.releases[0]?.trackShas).toHaveLength(4);
    expect(m.releases[0]?.artist).toBe("Fimiguerrero, Lancey Foux, Len");
  });

  it("still keeps same-titled albums by unrelated acts apart", () => {
    const m = buildManifest([
      probe({ sha: sha(1), tags: { album: "Untitled", artist: "Alpha" } }),
      probe({ sha: sha(2), tags: { album: "Untitled", artist: "Beta" } }),
    ]);
    expect(m.releases).toHaveLength(2);
  });

  it("does not merge different albums that share one cast member", () => {
    const m = buildManifest([
      probe({ sha: sha(1), tags: { album: "One", artist: "A, B" } }),
      probe({ sha: sha(2), tags: { album: "Two", artist: "A, C" } }),
    ]);
    expect(m.releases).toHaveLength(2);
  });
});

describe("release ids survive merging", () => {
  const sha = (n: number) => String(n).repeat(64).slice(0, 64);

  it("repoints tracks at the surviving release when two releases merge", () => {
    const m = buildManifest([
      probe({ sha: sha(1), tags: { album: "CONGLOMERATE", artist: "Fimiguerrero, Len" } }),
      probe({ sha: sha(2), tags: { album: "CONGLOMERATE", artist: "Len, Fimiguerrero" } }),
      probe({ sha: sha(3), tags: { album: "CONGLOMERATE", artist: "Lancey Foux, Len" } }),
    ]);
    const ids = new Set(m.releases.map((r) => r.id));
    for (const t of m.tracks) {
      expect(ids.has(t.releaseId!), `${t.releaseId} was deleted by the merge`).toBe(true);
      for (const id of t.releaseIds) expect(ids.has(id) || id.startsWith("mb:") || id.startsWith("sp:")).toBe(true);
    }
    expect(new Set(m.tracks.map((t) => t.releaseId)).size).toBe(1);
  });
});

describe("exact-audio dedupe", () => {
  const sha = (n: string) => n.repeat(64).slice(0, 64);

  it("collapses re-tagged copies of one master into a single track", () => {
    // The live case: three copies of NEW HIGH, identical audio, different
    // object shas because their tag/artwork blocks differ.
    const m = buildManifest([
      probe({ sha: sha("c"), audioSha: "aaaa", tags: { title: "NEW HIGH", artist: "Yeat", album: "LYFESTYLE" } }),
      probe({ sha: sha("a"), audioSha: "aaaa", tags: { title: "NEW HIGH", artist: "Yeat", album: "LYFESTYLE" } }),
      probe({ sha: sha("b"), audioSha: "aaaa", tags: { title: "NEW HIGH", artist: "Yeat", album: "LYFESTYLE" } }),
    ]);
    expect(m.tracks).toHaveLength(1);
  });

  it("keeps the lowest sha256 as canonical, per SPEC §5's tiebreak", () => {
    const m = buildManifest([
      probe({ sha: sha("c"), audioSha: "aaaa", tags: { title: "T" } }),
      probe({ sha: sha("a"), audioSha: "aaaa", tags: { title: "T" } }),
    ]);
    expect(m.tracks[0]?.sha).toBe(sha("a"));
  });

  it("records the copies rather than losing them", () => {
    const m = buildManifest([
      probe({ sha: sha("a"), audioSha: "aaaa", tags: { title: "T" } }),
      probe({ sha: sha("b"), audioSha: "aaaa", tags: { title: "T" } }),
      probe({ sha: sha("c"), audioSha: "aaaa", tags: { title: "T" } }),
    ]);
    expect(m.tracks[0]?.dupeShas).toEqual([sha("b"), sha("c")]);
  });

  it("does not merge different recordings that share a title", () => {
    const m = buildManifest([
      probe({ sha: sha("a"), audioSha: "aaaa", tags: { title: "Intro", artist: "A" } }),
      probe({ sha: sha("b"), audioSha: "bbbb", tags: { title: "Intro", artist: "A" } }),
    ]);
    expect(m.tracks).toHaveLength(2);
  });

  it("leaves tracks alone when the audio hash is unavailable", () => {
    const m = buildManifest([
      probe({ sha: sha("a"), audioSha: null, tags: { title: "T" } }),
      probe({ sha: sha("b"), audioSha: null, tags: { title: "T" } }),
    ]);
    expect(m.tracks).toHaveLength(2);
  });

  it("keeps a deduped release's track count honest", () => {
    const m = buildManifest([
      probe({ sha: sha("a"), audioSha: "aaaa", tags: { title: "One", artist: "Yeat", album: "LYFESTYLE" } }),
      probe({ sha: sha("b"), audioSha: "aaaa", tags: { title: "One", artist: "Yeat", album: "LYFESTYLE" } }),
      probe({ sha: sha("d"), audioSha: "bbbb", tags: { title: "Two", artist: "Yeat", album: "LYFESTYLE" } }),
    ]);
    expect(m.tracks).toHaveLength(2);
    expect(m.releases).toHaveLength(1);
    expect(m.releases[0]?.trackShas).toHaveLength(2);
  });

  it("is deterministic regardless of input order", () => {
    const a = probe({ sha: sha("a"), audioSha: "aaaa", tags: { title: "T" } });
    const b = probe({ sha: sha("b"), audioSha: "aaaa", tags: { title: "T" } });
    expect(buildManifest([a, b]).integrity).toBe(buildManifest([b, a]).integrity);
  });
});

describe("release cover fallback", () => {
  const sha = (n: string) => n.repeat(64).slice(0, 64);
  const cover = "f".repeat(64);

  it("uses a release cover when the file carries no picture", () => {
    // CHROMAKOPIA: 13 files, one audio stream each, no attached picture.
    const art = new Map([[releaseArtKey("Tyler, The Creator", "CHROMAKOPIA"), cover]]);
    const m = buildManifest(
      [probe({ sha: sha("a"), tags: { album: "CHROMAKOPIA", artist: "Tyler, The Creator" } })],
      new Map(), new Map(), [], [], new Map(), new Map(), new Map(), art
    );
    expect(m.tracks[0]?.artSha).toBe(cover);
    expect(m.releases[0]?.artSha).toBe(cover);
  });

  it("prefers the file's own embedded art over the release cover", () => {
    const embedded = new Map([[sha("a"), "e".repeat(64)]]);
    const art = new Map([[releaseArtKey("Yeat", "LYFESTYLE"), cover]]);
    const m = buildManifest(
      [probe({ sha: sha("a"), tags: { album: "LYFESTYLE", artist: "Yeat" } })],
      new Map(), new Map(), [], [], new Map(), new Map(), embedded, art
    );
    expect(m.tracks[0]?.artSha).toBe("e".repeat(64));
  });

  it("does not apply a release cover when the file named no album", () => {
    const art = new Map([[releaseArtKey("Yeat", "LYFESTYLE"), cover]]);
    const m = buildManifest(
      [probe({ sha: sha("a"), tags: { artist: "Yeat" } })],
      new Map(), new Map(), [], [], new Map(), new Map(), new Map(), art
    );
    expect(m.tracks[0]?.artSha).toBeNull();
  });

  it("leaves art null when no cover was found for the release", () => {
    const m = buildManifest(
      [probe({ sha: sha("a"), tags: { album: "Obscure", artist: "Nobody" } })],
      new Map(), new Map(), [], [], new Map(), new Map(), new Map(), new Map()
    );
    expect(m.tracks[0]?.artSha).toBeNull();
  });
});

describe("release running order", () => {
  const sha = (n: string) => n.repeat(64).slice(0, 64);

  it("orders a release by the tagger's track numbers", () => {
    // The regression: release rows took the provider's numbering, which is null
    // for a tagged file, so ordering fell through to sha order and looked random.
    const m = buildManifest([
      probe({ sha: sha("c"), tags: { album: "A", artist: "X", title: "third", trackNumber: 3 } }),
      probe({ sha: sha("a"), tags: { album: "A", artist: "X", title: "first", trackNumber: 1 } }),
      probe({ sha: sha("b"), tags: { album: "A", artist: "X", title: "second", trackNumber: 2 } }),
    ]);
    expect(m.releases[0]?.tracks.map((t) => t.trackNumber)).toEqual([1, 2, 3]);
    const order = m.releases[0]!.trackShas.map(
      (s) => m.tracks.find((t) => t.sha === s)!.title
    );
    expect(order).toEqual(["first", "second", "third"]);
  });

  it("orders across discs before track numbers", () => {
    const m = buildManifest([
      probe({ sha: sha("a"), tags: { album: "A", artist: "X", trackNumber: 1, discNumber: 2 } }),
      probe({ sha: sha("b"), tags: { album: "A", artist: "X", trackNumber: 9, discNumber: 1 } }),
    ]);
    expect(m.releases[0]?.tracks.map((t) => [t.discNumber, t.trackNumber])).toEqual([
      [1, 9],
      [2, 1],
    ]);
  });

  it("still falls back to sha order when nothing is numbered", () => {
    const m = buildManifest([
      probe({ sha: sha("b"), tags: { album: "A", artist: "X" } }),
      probe({ sha: sha("a"), tags: { album: "A", artist: "X" } }),
    ]);
    expect(m.releases[0]?.trackShas).toEqual([sha("a"), sha("b")]);
  });
});
