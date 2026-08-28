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