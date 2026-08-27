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
  });

  it("is deterministic: same input, same integrity", () => {
    const meta = new Map([["a".repeat(64), { caption: "x", fileName: "y.flac" }]]);
    const m1 = buildManifest([probe(), probe({ sha: "b".repeat(64), tags: { title: "T" } })], meta);
    const m2 = buildManifest([probe(), probe({ sha: "b".repeat(64), tags: { title: "T" } })], meta);
    expect(m1.integrity).toBe(m2.integrity);
    expect(m1.tracks.map((t) => t.sha)).toEqual(m2.tracks.map((t) => t.sha));
  });
});