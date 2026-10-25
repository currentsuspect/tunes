import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index.js";
import { signAccessToken, verifyAccessToken } from "../src/crypto.js";

// BYOB (docs/BYOB.md) through the whole Worker: the token learns the account's box, a library request goes to that
// box's tunnel, and a box's own hostname cannot be reached from outside.

const ACCESS_SECRET = "test-access-secret";
const NOW = Math.floor(Date.now() / 1000);
const REFRESH = "r".repeat(64);

/** A D1 stand-in that answers the few queries these paths make, by the SQL they send. */
function fakeDb(box: { id: string } | null) {
  return {
    prepare: (sql: string) => ({
      bind: (..._args: unknown[]) => ({
        first: async () => {
          if (sql.includes("FROM device WHERE refresh_hash")) {
            return { id: "dev-1", account_id: "acct-cedric", status: "active" };
          }
          if (sql.includes("FROM account WHERE id")) return { id: "acct-cedric", label: "Cedric", status: "active" };
          if (sql.includes("FROM box WHERE account_id")) return box ? { ...box, status: "active" } : null;
          return null;
        },
        run: async () => ({}),
      }),
    }),
  };
}

function env(box: { id: string } | null) {
  return {
    DB: fakeDb(box),
    ACCESS_SECRET,
    MEDIA_SECRET: "test-media-secret",
    INTERNAL_PUBLISH_KEY: "k".repeat(64),
  } as any;
}

afterEach(() => vi.unstubAllGlobals());

describe("bring your own box", () => {
  it("puts the account's box in its access token", async () => {
    const res = await worker.fetch(
      new Request("https://tunes.aestra.studio/auth/token", {
        method: "POST",
        body: JSON.stringify({ refresh_token: REFRESH }),
      }),
      env({ id: "cedric-box" }),
    );
    const { access_token } = (await res.json()) as { access_token: string };
    expect((await verifyAccessToken(access_token, ACCESS_SECRET, NOW))?.box).toBe("cedric-box");

    const none = await worker.fetch(
      new Request("https://tunes.aestra.studio/auth/token", {
        method: "POST",
        body: JSON.stringify({ refresh_token: REFRESH }),
      }),
      env(null),
    );
    const plain = (await none.json()) as { access_token: string };
    expect((await verifyAccessToken(plain.access_token, ACCESS_SECRET, NOW))?.box).toBeUndefined();
  });

  it("sends a box account's library request to its box, and everyone else's to the owner's", async () => {
    const seen: string[] = [];
    vi.stubGlobal("fetch", async (req: Request) => {
      seen.push(new URL(req.url).host);
      return new Response("{}");
    });
    const ask = async (box?: string) => {
      const token = await signAccessToken(
        { sub: "acct-cedric", did: "dev-1", iat: NOW, exp: NOW + 600, ...(box ? { box } : {}) },
        ACCESS_SECRET,
      );
      await worker.fetch(
        new Request("https://tunes.aestra.studio/soulseek/search?q=x", {
          headers: { authorization: `Bearer ${token}` },
        }),
        env(null),
      );
    };
    await ask("cedric-box");
    await ask();
    expect(seen).toEqual(["cedric-box.aestra.studio", "tunes.aestra.studio"]);
  });

  it("refuses a box's hostname from outside, before any tunnel", async () => {
    const tunnel = vi.fn(async () => new Response("library"));
    vi.stubGlobal("fetch", tunnel);
    const res = await worker.fetch(new Request("https://cedric-box.aestra.studio/manifest"), env(null));
    expect(res.status).toBe(404);
    // Anything beneath a box's name is refused the same way.
    const deeper = await worker.fetch(new Request("https://x.cedric-box.aestra.studio/manifest"), env(null));
    expect(deeper.status).toBe(404);
    expect(tunnel).not.toHaveBeenCalled();
  });

  it("never turns a malformed box claim into a hostname", async () => {
    const seen: string[] = [];
    vi.stubGlobal("fetch", async (req: Request) => {
      seen.push(new URL(req.url).host);
      return new Response("{}");
    });
    const token = await signAccessToken(
      { sub: "acct-x", did: "dev-1", iat: NOW, exp: NOW + 600, box: "evil.example.com/x" },
      ACCESS_SECRET,
    );
    await worker.fetch(
      new Request("https://tunes.aestra.studio/search?q=x", { headers: { authorization: `Bearer ${token}` } }),
      env(null),
    );
    expect(seen).toEqual(["tunes.aestra.studio"]);
  });

  it("lets the owner check a box end to end, and nobody else", async () => {
    const seen: string[] = [];
    vi.stubGlobal("fetch", async (url: string) => {
      seen.push(String(url));
      return new Response(JSON.stringify({ ok: true, box: "cedric-box" }));
    });
    const ask = (key: string, id = "cedric-box") =>
      worker.fetch(
        new Request(`https://tunes.aestra.studio/internal/boxes/${id}/health`, {
          headers: { authorization: `Bearer ${key}` },
        }),
        env(null),
      );
    const ok = await ask("k".repeat(64));
    expect(ok.status).toBe(200);
    expect(seen).toEqual(["https://cedric-box.aestra.studio/health"]);
    expect((await ask("x".repeat(64))).status).toBe(401);
    expect((await ask("k".repeat(64), "Evil.Host")).status).toBe(400);
    expect(seen).toHaveLength(1);
  });
});
