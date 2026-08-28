import { describe, expect, it } from "vitest";
import { buildManifest } from "../src/manifest.js";
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
        { artist: "Travis Scott", album: "ESCAPE PLAN", year: "2021", artSha: "c".repeat(64), releaseId: "mb:x", releaseType: "Single", trackNumber: 1 },
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

  it("never merges releases with different external ids", () => {
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
        },
      ],
      [
        "b".repeat(64),
        {
          artist: "Travis Scott",
          album: "ESCAPE PLAN / MAFIA",
          year: "2021",
          artSha: null,
          releaseId: "sp:two",
          releaseType: "single",
          trackNumber: 1,
        },
      ],
    ]);
    const m = buildManifest([probe(), probe({ sha: "b".repeat(64) })], new Map(), enrich);
    expect(m.releases.length).toBe(2);
  });

  it("falls back to a normalized name key without an external id", () => {
    const m = buildManifest([probe(), probe({ sha: "b".repeat(64) })], new Map());
    expect(m.releases.length).toBe(2); // per-sha until named
    const named = buildManifest(
      [probe(), probe({ sha: "b".repeat(64) })],
      new Map([
        [
          "a".repeat(64),
          { caption: null, fileName: "Travis Scott - MAFIA.flac" },
        ],
        [
          "b".repeat(64),
          { caption: null, fileName: "Travis Scott - ESCAPE PLAN.flac" },
        ],
      ]),
      new Map()
    );
    expect(named.releases.length).toBe(2); // different albums, same artist
  });
});