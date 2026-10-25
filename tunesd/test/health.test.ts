import { describe, expect, it } from "vitest";
import { health } from "../src/health.js";
import { ManifestServer } from "../src/serve.js";

// BYOB (docs/BYOB.md): a box says it is up and which box it is, and nothing about its library.
describe("GET /health", () => {
  it("names the box and the daemon's version", () => {
    const h = health({ TUNESD_BOX_ID: "cedric-box" } as NodeJS.ProcessEnv);
    expect(h.ok).toBe(true);
    expect(h.box).toBe("cedric-box");
    expect(h.version).toMatch(/^\d+\.\d+\.\d+/);
    expect(h.uptimeSec).toBeGreaterThanOrEqual(0);
    // The owner's box has no box id.
    expect(health({} as NodeJS.ProcessEnv).box).toBeNull();
  });

  it("is answered by the server without building the library", async () => {
    let builds = 0;
    const port = 43000 + Math.floor(Math.random() * 2000);
    const server = new ManifestServer(
      {} as never,
      "/nonexistent",
      async () => {
        builds += 1;
        throw new Error("health must not build the manifest");
      },
      port,
      { info() {}, warn() {}, error() {}, debug() {} } as never,
      undefined,
      null,
      null,
      null,
      undefined,
      "127.0.0.1",
    );
    await server.start();
    const res = await fetch(`http://127.0.0.1:${port}/health`);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { ok: boolean; version: string };
    expect(body.ok).toBe(true);
    expect(Object.keys(body).sort()).toEqual(["box", "ok", "uptimeSec", "version"]);
    expect(builds).toBe(0);
  });
});
