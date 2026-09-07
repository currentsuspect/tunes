import { describe, expect, it } from "vitest";
import { buildNumberFromTag, newestRelease } from "../src/updates.js";

/**
 * Choosing which release to offer.
 *
 * Everything a phone is told about updates comes from this, and the phone acts
 * on it by downloading 100 MB and asking the user to install. Offering the
 * wrong release, or one whose asset does not exist, costs a real download and
 * a failed install on someone else's data plan.
 */
describe("buildNumberFromTag", () => {
  it("reads the CI run number", () => {
    expect(buildNumberFromTag("build-42")).toBe(42);
  });

  it("ignores tags that are not builds", () => {
    // Hand-made tags live in the same list. Treating "v1.0" as a build would
    // put a garbage number into the comparison.
    for (const tag of ["v1.0", "release", "build-", "build-x", ""]) {
      expect(buildNumberFromTag(tag)).toBeNull();
    }
  });

  it("rejects zero and negatives rather than accepting them", () => {
    expect(buildNumberFromTag("build-0")).toBeNull();
    expect(buildNumberFromTag("build--3")).toBeNull();
  });

  it("tolerates surrounding whitespace", () => {
    expect(buildNumberFromTag("  build-7 ")).toBe(7);
  });
});

const apk = (size = 1000) => ({
  name: "app-release.apk",
  url: "https://api.github.com/asset/1",
  size,
});

describe("newestRelease", () => {
  it("picks the highest build, not the first or the newest by date", () => {
    // A re-run of an older commit publishes later but is not a newer app, so
    // ordering by published_at would offer a downgrade.
    const chosen = newestRelease([
      {
        tag_name: "build-9",
        assets: [apk()],
        published_at: "2026-09-08T00:00:00Z",
      },
      {
        tag_name: "build-12",
        assets: [apk()],
        published_at: "2026-09-01T00:00:00Z",
      },
    ]);
    expect(chosen?.info.build).toBe(12);
  });

  it("skips a release with no APK attached", () => {
    // The build failed after tagging, or someone tagged by hand. Offering it
    // sends the phone to a 404 after it has already told the user there is an
    // update.
    const chosen = newestRelease([
      { tag_name: "build-20", assets: [{ name: "notes.txt", url: "u", size: 1 }] },
      { tag_name: "build-5", assets: [apk()] },
    ]);
    expect(chosen?.info.build).toBe(5);
  });

  it("skips drafts", () => {
    const chosen = newestRelease([
      { tag_name: "build-30", draft: true, assets: [apk()] },
      { tag_name: "build-4", assets: [apk()] },
    ]);
    expect(chosen?.info.build).toBe(4);
  });

  it("skips tags that are not builds", () => {
    const chosen = newestRelease([
      { tag_name: "v2.0", assets: [apk()] },
      { tag_name: "build-3", assets: [apk()] },
    ]);
    expect(chosen?.info.build).toBe(3);
  });

  it("carries the size, so a phone can be told what it is agreeing to", () => {
    const chosen = newestRelease([
      { tag_name: "build-3", assets: [apk(104_000_000)] },
    ]);
    expect(chosen?.info.size).toBe(104_000_000);
  });

  it("uses the first line of the notes only", () => {
    const chosen = newestRelease([
      {
        tag_name: "build-3",
        body: "fix(player): keep the queue\n\nCommit: abc123",
        assets: [apk()],
      },
    ]);
    expect(chosen?.info.notes).toBe("fix(player): keep the queue");
  });

  it("falls back to the tag when a release has no title", () => {
    const chosen = newestRelease([{ tag_name: "build-3", assets: [apk()] }]);
    expect(chosen?.info.name).toBe("build-3");
  });

  it("returns null when there is nothing usable", () => {
    expect(newestRelease([])).toBeNull();
    expect(newestRelease([{ tag_name: "v1", assets: [apk()] }])).toBeNull();
    // A malformed payload must not throw: a GitHub hiccup cannot be allowed
    // to take the music server down with it.
    expect(newestRelease(null)).toBeNull();
    expect(newestRelease({ nope: true })).toBeNull();
  });
});
