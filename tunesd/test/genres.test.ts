import { describe, expect, it } from "vitest";
import { foldTag, genresFromTags } from "../src/genres.js";

describe("genresFromTags", () => {
  it("folds spellings of one genre together", () => {
    expect(foldTag("Hip-Hop")).toBe(foldTag("hip hop"));
    const g = genresFromTags(["hip hop", "Hip-Hop", "rap"]);
    expect(g.map((x) => x.name)).toEqual(["Hip-Hop"]);
  });

  it("a specific room outranks the broad family", () => {
    const g = genresFromTags(["hip hop", "rap", "rage", "trap"]);
    expect(g[0]?.name).toBe("Rage");
    expect(g.map((x) => x.family)).toEqual(["Hip-Hop", "Hip-Hop", "Hip-Hop"]);
  });

  it("drops places, descriptors and names", () => {
    const g = genresFromTags(["female vocalists", "atlanta", "rnb", "migos", "soul"]);
    expect(g.map((x) => x.name)).toEqual(["R&B", "Soul"]);
  });

  it("a place speaks only when nothing else does", () => {
    expect(genresFromTags(["nigeria", "african"])[0]).toMatchObject({ name: "Afrobeats", family: "African" });
    expect(genresFromTags(["nigeria", "afrobeats"]).map((g) => g.name)).toEqual(["Afrobeats"]);
  });

  it("nothing recognisable is no genre, not a guess", () => {
    expect(genresFromTags(["netflix series", "building the band"])).toEqual([]);
  });

  it("is deterministic and capped", () => {
    const tags = ["trap", "rage", "plugg", "cloud rap", "underground rap"];
    expect(genresFromTags(tags)).toEqual(genresFromTags(tags));
    expect(genresFromTags(tags)).toHaveLength(3);
  });
});
