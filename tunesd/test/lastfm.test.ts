import { describe, expect, it } from "vitest";
import {
  isPlaceholderImage,
  LASTFM_PLACEHOLDER_IMAGE,
  LastfmClient,
  LastfmUnavailable,
  pickImage,
} from "../src/lastfm.js";

function client(reply: unknown, status = 200): LastfmClient {
  const fetcher = (async () =>
    new Response(JSON.stringify(reply), {
      status,
      headers: { "content-type": "application/json" },
    })) as unknown as typeof fetch;
  return new LastfmClient("key", "tunes/test", fetcher);
}

const img = (hash: string, size: string) => ({
  "#text": `https://lastfm.freetls.fastly.net/i/u/300x300/${hash}.png`,
  size,
});

describe("pickImage", () => {
  it("prefers the largest usable size", () => {
    const url = pickImage([img("a", "small"), img("b", "extralarge"), img("c", "medium")]);
    expect(url).toContain("/b.png");
  });

  it("never returns Last.fm's grey-star placeholder", () => {
    expect(pickImage([img(LASTFM_PLACEHOLDER_IMAGE, "extralarge")])).toBeNull();
  });

  it("falls back past a placeholder to a real image", () => {
    const url = pickImage([img(LASTFM_PLACEHOLDER_IMAGE, "extralarge"), img("real", "large")]);
    expect(url).toContain("/real.png");
  });

  it("handles missing or empty image arrays", () => {
    expect(pickImage(undefined)).toBeNull();
    expect(pickImage([])).toBeNull();
  });
});

describe("isPlaceholderImage", () => {
  it("recognises the placeholder by hash", () => {
    expect(isPlaceholderImage(`https://x/${LASTFM_PLACEHOLDER_IMAGE}.png`)).toBe(true);
    expect(isPlaceholderImage("https://x/real.png")).toBe(false);
    expect(isPlaceholderImage(null)).toBe(false);
  });
});

describe("LastfmClient failure taxonomy", () => {
  it("returns null for a genuine not-found (error 6)", async () => {
    await expect(client({ error: 6, message: "Artist not found" }).artistInfo("Nobody")).resolves.toBeNull();
  });

  it("throws on an invalid API key rather than reporting 'no such artist'", async () => {
    await expect(client({ error: 10, message: "Invalid API key" }).artistInfo("Yeat")).rejects.toBeInstanceOf(
      LastfmUnavailable
    );
  });

  it("throws on rate limiting so it is never cached as a miss", async () => {
    await expect(client({ error: 29, message: "Rate limit exceeded" }).artistInfo("Yeat")).rejects.toThrow(
      /error 29/
    );
  });

  it("throws on an HTTP error", async () => {
    await expect(client({}, 503).artistInfo("Yeat")).rejects.toThrow(/HTTP 503/);
  });
});

describe("LastfmClient.artistInfo", () => {
  it("maps a full artist payload", async () => {
    const c = client({
      artist: {
        name: "Yeat",
        mbid: "abc",
        stats: { listeners: "1234567" },
        bio: { summary: "  A rapper.  " },
        tags: { tag: [{ name: "rap" }, { name: "trap" }] },
        similar: { artist: [{ name: "Summrs" }, { name: "Ken Carson" }] },
        image: [img("real", "extralarge")],
      },
    });
    const a = await c.artistInfo("yeat");
    expect(a).toMatchObject({
      name: "Yeat",
      mbid: "abc",
      tags: ["rap", "trap"],
      listeners: 1234567,
      summary: "A rapper.",
      similar: ["Summrs", "Ken Carson"],
    });
    expect(a?.imageUrl).toContain("/real.png");
  });

  it("reports no image rather than the placeholder", async () => {
    const c = client({
      artist: { name: "Yeat", image: [img(LASTFM_PLACEHOLDER_IMAGE, "extralarge")] },
    });
    expect((await c.artistInfo("Yeat"))?.imageUrl).toBeNull();
  });

  it("returns null when the payload has no artist", async () => {
    expect(await client({}).artistInfo("Yeat")).toBeNull();
  });

  it("tolerates a single tag arriving unwrapped", async () => {
    const c = client({ artist: { name: "Yeat", tags: { tag: { name: "rap" } } } });
    expect((await c.artistInfo("Yeat"))?.tags).toEqual(["rap"]);
  });
});

describe("LastfmClient.albumInfo and trackInfo", () => {
  it("maps an album", async () => {
    const c = client({
      album: {
        name: "LYFESTYLE",
        artist: "Yeat",
        mbid: "m1",
        tags: { tag: [{ name: "rap" }] },
        image: [img("cover", "extralarge")],
      },
    });
    const a = await c.albumInfo("Yeat", "lyfestyle");
    expect(a).toMatchObject({ title: "LYFESTYLE", artist: "Yeat", mbid: "m1", tags: ["rap"] });
    expect(a?.imageUrl).toContain("/cover.png");
  });

  it("maps a track and its album linkage", async () => {
    const c = client({
      track: {
        name: "NEW HIGH",
        mbid: "t1",
        listeners: "4321",
        artist: { name: "Yeat" },
        album: { title: "LYFESTYLE", artist: "Yeat", image: [img("cover", "large")] },
        toptags: { tag: [{ name: "rap" }] },
      },
    });
    const t = await c.trackInfo("Yeat", "new high");
    expect(t).toMatchObject({
      title: "NEW HIGH",
      artist: "Yeat",
      album: "LYFESTYLE",
      albumArtist: "Yeat",
      listeners: 4321,
      tags: ["rap"],
    });
  });

  it("returns a track with no album rather than inventing one", async () => {
    const c = client({ track: { name: "Loose Single", artist: { name: "Yeat" } } });
    expect((await c.trackInfo("Yeat", "Loose Single"))?.album).toBeNull();
  });
});
