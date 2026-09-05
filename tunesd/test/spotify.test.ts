import { describe, expect, it } from "vitest";
import { SpotifyClient } from "../src/enrich.js";

function fakeFetch(handler: (url: string) => unknown): typeof fetch {
  return (async (input: string | URL | Request) => {
    const url = String(input);
    if (url.includes("api/token")) {
      return new Response(JSON.stringify({ access_token: "tok", expires_in: 3600 }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    }
    const body = handler(url);
    return new Response(JSON.stringify(body), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  }) as unknown as typeof fetch;
}

const track = (name: string, artist: string, album: string, year: string) => ({
  name,
  artists: [{ name: artist }],
  album: {
    name: album,
    release_date: year,
    images: [{ url: `https://art/${name}.jpg` }],
  },
});

describe("SpotifyClient", () => {
  it("accepts only an exact artist+title match", async () => {
    const client = new SpotifyClient("id", "secret", fakeFetch(() => ({
      tracks: {
        items: [
          track("Wrong Song", "vax", "other", "2026"),
          track("AWOL", "different artist", "x", "2020"),
          track("AWOL", "vax", "AWOL", "2026-08-25"),
        ],
      },
    })));
    const hit = await client.search({ artist: "Vax", title: "AWOL" });
    expect(hit?.artist).toBe("vax");
    expect(hit?.album).toBe("AWOL");
    expect(hit?.year).toBe("2026");
    expect(hit?.artUrl).toContain("AWOL.jpg");
  });

  it("rejects near-misses honestly", async () => {
    const client = new SpotifyClient("id", "secret", fakeFetch(() => ({
      tracks: { items: [track("AWOLNATION", "vax", "x", "2026")] },
    })));
    const hit = await client.search({ artist: "Vax", title: "AWOL" });
    expect(hit).toBeNull();
  });

  it("returns null when the token exchange fails", async () => {
    const client = new SpotifyClient(
      "id",
      "secret",
      (async () => new Response("nope", { status: 401 })) as unknown as typeof fetch
    );
    expect(await client.search({ artist: "Vax", title: "AWOL" })).toBeNull();
  });
});
describe("SpotifyClient artist lookup failure taxonomy", () => {
  const clientWith = (status: number, body: unknown = {}) => {
    const fetcher = (async (input: string | URL | Request) => {
      const url = String(input);
      if (url.includes("api/token")) {
        return new Response(JSON.stringify({ access_token: "tok", expires_in: 3600 }), {
          status: 200,
          headers: { "content-type": "application/json" },
        });
      }
      return new Response(JSON.stringify(body), {
        status,
        headers: { "content-type": "application/json" },
      });
    }) as unknown as typeof fetch;
    return new SpotifyClient("id", "secret", fetcher);
  };

  it("throws rather than reporting 'no such artist' on HTTP 403", async () => {
    // The live regression: Spotify answers 403 to every search, which used to
    // come back as null and get cached as a definitive miss for a week.
    await expect(clientWith(403).searchArtistId("Ken Carson")).rejects.toThrow(
      /HTTP 403/
    );
  });

  it("throws on 429 so a rate limit is never cached as a miss", async () => {
    await expect(clientWith(429).searchArtistId("Yeat")).rejects.toThrow(/HTTP 429/);
    await expect(clientWith(429).artistIdFromTrack("Yeat")).rejects.toThrow(/HTTP 429/);
  });

  it("returns null only when Spotify answered and had nothing", async () => {
    const empty = clientWith(200, { artists: { items: [] } });
    await expect(empty.searchArtistId("Nobody At All")).resolves.toBeNull();
  });

  it("returns null when the answer is a different artist", async () => {
    const wrong = clientWith(200, { artists: { items: [{ id: "x", name: "Someone Else" }] } });
    await expect(wrong.searchArtistId("Ken Carson")).resolves.toBeNull();
  });

  it("resolves the id on a genuine match", async () => {
    const hit = clientWith(200, { artists: { items: [{ id: "abc", name: "Ken Carson" }] } });
    await expect(hit.searchArtistId("Ken Carson")).resolves.toBe("abc");
  });
});
