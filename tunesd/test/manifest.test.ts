import { describe, expect, it } from "vitest";
import { buildManifest } from "../src/manifest.js";
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
    probedAt: "2026-08-27T00:00:00Z",
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
    expect(filenamed.tracks[0]?.title).toBe("Travis Scott - ESCAPE PLAN");
  });

  it("never invents artist/album from filenames", () => {
    const m = buildManifest(
      [probe()],
      new Map([["a".repeat(64), { caption: null, fileName: "Some Artist - Track.flac" }]])
    );
    expect(m.tracks[0]?.artist).toBe("unknown artist");
    expect(m.tracks[0]?.album).toBe("unknown album");
    expect(m.tracks[0]?.artSha).toBeNull();
  });

  it("enrichment fills artist/album/art only when tags are absent", () => {
    const enrich = new Map([
      [
        "a".repeat(64),
        { artist: "Travis Scott", album: "ESCAPE PLAN", year: "2021", artSha: "c".repeat(64), releaseId: "mb:x", releaseType: "Single", trackNumber: 1, discNumber: null },
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
        },
      ],
    ]);
    const m = buildManifest([probe(), probe({ sha: "b".repeat(64) })], new Map(), enrich);
    expect(m.schema).toBe(2);
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
        },
      ],
    ]);
    const m = buildManifest([probe(), probe({ sha: "b".repeat(64) })], new Map(), enrich);
    expect(m.releases.length).toBe(2);
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
        },
      ],
    ]);
    const m = buildManifest([probe()], new Map(), enrich);
    expect(m.releases.length).toBe(1);
    expect(m.releases[0]?.title).toBe("unknown album");
    expect(m.releases[0]?.artist).toBe("Don Toliver");
    expect(m.tracks[0]?.album).toBe("unknown album");
    expect(m.tracks[0]?.releaseId).toBeNull();
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
          },
        ],
      ])
    );
    expect(named.releases.length).toBe(2); // different albums, same artist
  });
});