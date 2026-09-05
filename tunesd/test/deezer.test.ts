import { describe, expect, it } from "vitest";
import { DeezerClient, DeezerUnavailable, isGenericPicture, pickPicture } from "../src/deezer.js";

function client(reply: unknown, status = 200): DeezerClient {
  const fetcher = (async () =>
    new Response(JSON.stringify(reply), {
      status,
      headers: { "content-type": "application/json" },
    })) as unknown as typeof fetch;
  return new DeezerClient("tunes/test", fetcher);
}

const row = (over: Record<string, unknown> = {}) => ({
  id: 1,
  name: "Yeat",
  picture_xl: "https://cdn.deezer.com/images/artist/abc/1000x1000.jpg",
  nb_fan: 226597,
  ...over,
});

describe("isGenericPicture", () => {
  it("treats Deezer's empty-slug silhouette as no image", () => {
    expect(isGenericPicture("https://cdn.deezer.com/images/artist//1000x1000.jpg")).toBe(true);
    expect(isGenericPicture("")).toBe(true);
    expect(isGenericPicture(null)).toBe(true);
  });

  it("accepts a real picture", () => {
    expect(isGenericPicture("https://cdn.deezer.com/images/artist/abc/1000x1000.jpg")).toBe(false);
  });
});

describe("pickPicture", () => {
  it("prefers the largest available size", () => {
    const url = pickPicture({
      picture_medium: "https://cdn.deezer.com/images/artist/m/250x250.jpg",
      picture_xl: "https://cdn.deezer.com/images/artist/x/1000x1000.jpg",
    });
    expect(url).toContain("/x/");
  });

  it("falls past a generic silhouette to a real one", () => {
    const url = pickPicture({
      picture_xl: "https://cdn.deezer.com/images/artist//1000x1000.jpg",
      picture_big: "https://cdn.deezer.com/images/artist/b/500x500.jpg",
    });
    expect(url).toContain("/b/");
  });

  it("reports null when nothing usable is present", () => {
    expect(pickPicture({})).toBeNull();
  });
});

describe("DeezerClient failure taxonomy", () => {
  it("throws on an HTTP error rather than reporting no match", async () => {
    await expect(client({}, 503).searchArtist("Yeat")).rejects.toBeInstanceOf(DeezerUnavailable);
  });

  it("throws on a quota error, which Deezer reports with HTTP 200", async () => {
    await expect(
      client({ error: { code: 4, message: "Quota limit exceeded" } }).searchArtist("Yeat")
    ).rejects.toThrow(/error 4/);
  });

  it("returns null only when the search genuinely had no results", async () => {
    await expect(client({ data: [] }).searchArtist("Nobody At All")).resolves.toBeNull();
  });
});

describe("DeezerClient.searchArtist", () => {
  it("maps a hit", async () => {
    const a = await client({ data: [row()] }).searchArtist("Yeat");
    expect(a).toMatchObject({ id: 1, name: "Yeat", fans: 226597 });
    expect(a?.pictureUrl).toContain("/abc/");
  });

  it("skips malformed rows", async () => {
    const a = await client({ data: [{ id: 2 }, row({ id: 3, name: "Yeat" })] }).searchArtist("Yeat");
    expect(a?.id).toBe(3);
  });

  it("returns every candidate so the caller can name-check them", async () => {
    const c = client({
      data: [row({ id: 1, name: "Le N'" }), row({ id: 2, name: "Len" })],
    });
    const all = await c.searchArtistCandidates("Len");
    expect(all.map((a) => a.name)).toEqual(["Le N'", "Len"]);
  });
});
