import { describe, expect, it } from "vitest";
import { joinDiscography } from "../src/discography.js";
import type { DiscographyGroup } from "../src/discography.js";
import type { ManifestRelease } from "../src/manifest.js";

const groups: DiscographyGroup[] = [
  { id: "g1", title: "HARDSTONE PSYCHO", type: "Album", year: "2024", date: "2024-08-09" },
  { id: "g2", title: "BROTHER STONE (FEAT. KODAK BLACK)", type: "Single", year: "2024", date: "2024-05-17" },
  { id: "g3", title: "Life of a DON", type: "Album", year: "2021", date: "2021-10-08" },
  { id: "g4", title: "Love Sick", type: "Album", year: "2023", date: "2023-02-24" },
];

const releases: Pick<ManifestRelease, "id" | "groupId" | "title" | "trackShas" | "totalTracks">[] = [
  { id: "mb:rel1", groupId: "g1", title: "HARDSTONE PSYCHO", trackShas: ["a", "b"], totalTracks: 23 },
  { id: "mb:rel2", groupId: null, title: "BROTHER STONE (FEAT. KODAK BLACK)", trackShas: ["c"], totalTracks: 1 },
  { id: "mb:rel3", groupId: "g3", title: "Life of a DON", trackShas: ["d", "e", "f"], totalTracks: 19 },
];

describe("joinDiscography", () => {
  it("marks owned by exact release-group id and reports owned counts", () => {
    const joined = joinDiscography(groups, releases);
    const hs = joined.find((g) => g.id === "g1");
    expect(hs?.owned).toBe(true);
    expect(hs?.releaseId).toBe("mb:rel1");
    expect(hs?.ownedTracks).toBe(2);
    expect(hs?.totalTracks).toBe(23);
  });

  it("falls back to normalized title equality for releases without a group id", () => {
    const joined = joinDiscography(groups, releases);
    const bs = joined.find((g) => g.id === "g2");
    expect(bs?.owned).toBe(true);
    expect(bs?.releaseId).toBe("mb:rel2");
    expect(bs?.ownedTracks).toBe(1);
  });

  it("marks unmatched groups as not owned", () => {
    const joined = joinDiscography(groups, releases);
    const ls = joined.find((g) => g.id === "g4");
    expect(ls?.owned).toBe(false);
    expect(ls?.releaseId).toBeNull();
    expect(ls?.ownedTracks).toBe(0);
    expect(ls?.totalTracks).toBeNull();
  });

  it("carries type, year and date through", () => {
    const [first] = joinDiscography(groups, releases);
    expect(first?.type).toBe("Album");
    expect(first?.year).toBe("2024");
    expect(first?.date).toBe("2024-08-09");
  });
});