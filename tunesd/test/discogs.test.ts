import { describe, expect, it } from "vitest";
import { DiscogsClient } from "../src/enrich.js";

function fakeFetch(results: unknown[]): typeof fetch {
  return (async () => {
    return new Response(JSON.stringify({ results }), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  }) as unknown as typeof fetch;
}

describe("DiscogsClient", () => {
  it("accepts exact artist+title, stripping format suffixes", async () => {
    const client = new DiscogsClient("tok", "tunes/0.1", fakeFetch([
      { title: "Vax - AWOL (Vinyl, US, 2026)", year: 2026, cover_image: "https://img/awol.jpg", thumb: "https://img/thumb.jpg" },
      { title: "Other - Track", year: 2000 },
    ]));
    const hit = await client.search({ artist: "Vax", title: "AWOL" });
    expect(hit?.artist).toBe("Vax");
    expect(hit?.album).toBe("AWOL");
    expect(hit?.year).toBe("2026");
    expect(hit?.artUrl).toBe("https://img/awol.jpg");
  });

  it("rejects wrong-artist near misses", async () => {
    const client = new DiscogsClient("tok", "tunes/0.1", fakeFetch([
      { title: "Someone Else - AWOL", year: 2020 },
    ]));
    expect(await client.search({ artist: "Vax", title: "AWOL" })).toBeNull();
  });

  it("skips placeholder cover images", async () => {
    const client = new DiscogsClient("tok", "tunes/0.1", fakeFetch([
      { title: "Vax - AWOL", year: 2026, cover_image: "https://img/spacer.gif" },
    ]));
    const hit = await client.search({ artist: "Vax", title: "AWOL" });
    expect(hit?.artUrl).toBeNull();
  });
});