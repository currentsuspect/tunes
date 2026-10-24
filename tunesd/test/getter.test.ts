import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { Getter, groupSongs, holdsAll, queryVariants, readPath, songKey, type GetJob } from "../src/getter.js";
import * as resource from "../src/resource.js";
import type { SlskResponse } from "../src/soulseek.js";

const log = { info: () => {}, warn: () => {}, error: () => {}, debug: () => {} } as never;

describe("reading a shared file's path", () => {
  it("Artist/Album (year)/NN - Title", () => {
    expect(readPath("@@x\\Music\\Travis Scott\\ASTROWORLD (2018)\\03 - SICKO MODE.flac")).toEqual({
      artist: "Travis Scott",
      album: "ASTROWORLD",
      title: "SICKO MODE",
    });
  });

  it("Artist - Album folder, NN Title file", () => {
    expect(readPath("music/Travis Scott - ASTROWORLD [FLAC]/03 SICKO MODE.flac")).toEqual({
      artist: "Travis Scott",
      album: "ASTROWORLD",
      title: "SICKO MODE",
    });
  });

  it("NN - Artist - Title in a loose folder", () => {
    const r = readPath("downloads/rap/03 - Travis Scott - SICKO MODE.mp3");
    expect(r.artist).toBe("Travis Scott");
    expect(r.title).toBe("SICKO MODE");
  });
});

const resp = (
  username: string,
  files: Array<{ filename: string; bitRate?: number; length?: number }>,
  free = true,
): SlskResponse => ({
  username,
  hasFreeUploadSlot: free,
  uploadSpeed: 1_000_000,
  queueLength: 0,
  files: files.map((f) => ({ size: 30_000_000, ...f })),
});

describe("real folder names (live search, 23 Oct)", () => {
  it("a track number or a year is not the artist or the title", () => {
    expect(readPath("Music/Travis Scott - ASTROWORLD/Travis Scott - 03 - SICKO MODE.flac")).toMatchObject({
      artist: "Travis Scott",
      title: "SICKO MODE",
    });
    expect(readPath("Travis Scott/ASTROWORLD/2018 - SICKO MODE.flac")).toMatchObject({
      artist: "Travis Scott",
      title: "SICKO MODE",
    });
  });

  it("the album's own name is not the artist", () => {
    expect(readPath("Travis Scott/ASTROWORLD/ASTROWORLD - SICKO MODE.flac")).toMatchObject({
      artist: "Travis Scott",
      album: "ASTROWORLD",
      title: "SICKO MODE",
    });
  });

  it("store labels and catalogue numbers are dropped", () => {
    expect(
      readPath("rips/Travis Scott - [E] ASTROWORLD [92967282]/03 - SICKO MODE(Explicit).flac"),
    ).toMatchObject({ artist: "Travis Scott", album: "ASTROWORLD", title: "SICKO MODE" });
  });

  it("disc-track numbers, and the title before the artist", () => {
    expect(readPath("music2\\Travis Scott\\ASTROWORLD\\1-03 SICKO MODE.flac")).toMatchObject({
      artist: "Travis Scott",
      title: "SICKO MODE",
    });
    expect(readPath("unmapped\\Various Artists\\[2022] NOW 113\\1-15 Burna Boy - Last Last.flac")).toMatchObject({
      artist: "Burna Boy",
      title: "Last Last",
    });
    expect(
      readPath("Music\\A - Z\\B\\Burna Boy\\2022 - Love, Damini\\07 - Last Last - Burna Boy.flac"),
    ).toMatchObject({ artist: "Burna Boy", title: "Last Last" });
  });

  it("a vague folder is not an artist", () => {
    expect(readPath("music/waydroid/SICKO MODE.flac").artist).toBeNull();
  });

  it("the featuring credit and clean/explicit do not split a song", () => {
    expect(songKey("Travis Scott feat. Drake", "SICKO MODE")).toBe(songKey("Travis Scott", "SICKO MODE"));
    expect(songKey("Travis Scott", "Sicko Mode (feat. Drake)")).toBe(songKey("Travis Scott", "SICKO MODE"));
    expect(songKey("Ayra Starr", "Rush (Clean)")).toBe(songKey("Ayra Starr", "Rush"));
    expect(songKey("Travis Scott", "SICKO MODE (Skrillex Remix)")).not.toBe(songKey("Travis Scott", "SICKO MODE"));
  });

  it("a shorter ask only keeps songs holding every word typed", () => {
    expect(holdsAll("burna boy last last", { artist: "Burna Boy", title: "Last Last", album: "Love, Damini" })).toBe(true);
    expect(holdsAll("burna boy last last", { artist: "Fall Out Boy", title: "The Last of the Real Ones", album: null })).toBe(false);
    expect(holdsAll("skyte in need", { artist: "INXS", title: "Need You Tonight", album: null })).toBe(false);
  });

  it("a fallback that finds only other songs says nothing is there", async () => {
    const api = {
      loggedIn: async () => true,
      search: async (text: string) =>
        text === "in need"
          ? [resp("p", [{ filename: "INXS/Kick/INXS - Need You Tonight.flac" }])]
          : [],
    };
    const g = new Getter({ api, inLibrary: () => null, log } as never);
    expect(await g.search("skyte in need")).toEqual([]);
  });

  it("shorter asks for when Soulseek drops a phrase", () => {
    expect(queryVariants("burna boy last last")).toEqual([
      "burna boy last last",
      "boy last last",
      "last last",
      "burna boy last",
    ]);
    // Two words: the artist the server will not search for is dropped.
    expect(queryVariants("rihanna desperado")).toEqual(["rihanna desperado", "desperado", "rihanna"]);
  });
});

describe("grouping answers into songs", () => {
  const answers = [
    resp("a", [{ filename: "Travis Scott/ASTROWORLD/03 - SICKO MODE.mp3", bitRate: 320, length: 312 }]),
    resp("b", [{ filename: "Travis Scott/ASTROWORLD/03 - SICKO MODE.flac", length: 312 }], false),
    resp("c", [
      { filename: "Travis Scott - ASTROWORLD/03 SICKO MODE.flac", length: 312 },
      { filename: "Travis Scott - ASTROWORLD/04 R.I.P. SCREW.flac", length: 185 },
    ]),
    resp("d", [{ filename: "remixes/Travis Scott - SICKO MODE (Skrillex Remix).mp3", bitRate: 320 }]),
    resp("e", [{ filename: "Travis Scott/ASTROWORLD/03 - SICKO MODE.mp3", bitRate: 128 }]),
  ];

  it("one song per artist and title, its best copy, most shared first", () => {
    const songs = groupSongs(answers, "sicko mode", () => null);
    expect(songs.map((s) => s.title)).toEqual(["SICKO MODE", "SICKO MODE (Skrillex Remix)"]);
    const s = songs[0]!;
    expect(s.peers).toBe(3); // a, b, c; e's 128 kb/s copy is left out
    expect(s.lossless).toBe(true);
    // Lossless and a free slot: c, not b.
    expect(s.username).toBe("c");
    expect(s.album).toBe("ASTROWORLD");
    expect(s.durationMs).toBe(312_000);
  });

  it("shows and fetches the explicit copy, not a clean one shared faster", () => {
    const songs = groupSongs(
      [
        resp("clean", [{ filename: "Don Toliver/HARDSTONE PSYCHO (Clean)/01 - KRYPTONITE.flac" }]),
        resp("dirty", [{ filename: "Don Toliver/HARDSTONE PSYCHO/01 - KRYPTONITE.mp3", bitRate: 320 }], false),
      ],
      "kryptonite",
      () => null,
    );
    expect(songs).toHaveLength(1);
    expect(songs[0]!.username).toBe("dirty");
  });

  it("a song listed artist-first and title-first is one song", () => {
    const songs = groupSongs(
      [
        resp("a", [{ filename: "x/Ayra Starr - Rush.flac" }]),
        resp("b", [{ filename: "y/Ayra Starr - Rush.flac" }]),
        resp("c", [{ filename: "z/Rush - Ayra Starr.mp3", bitRate: 320 }]),
      ],
      "rush",
      () => null,
    );
    expect(songs).toHaveLength(1);
    expect(songs[0]!.artist).toBe("Ayra Starr");
    expect(songs[0]!.peers).toBe(3);
  });

  it("only files holding every word asked for", () => {
    expect(groupSongs(answers, "sicko mode", () => null).some((s) => s.title.includes("SCREW"))).toBe(false);
  });

  it("says when the library has it already", () => {
    const songs = groupSongs(answers, "sicko mode", (w) => (w.title === "SICKO MODE" ? "sha1" : null));
    expect(songs[0]!.inLibrary).toBe("sha1");
  });
});

describe("getting a song", () => {
  let dir: string;
  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "tunes-getter-"));
  });
  afterEach(async () => {
    vi.restoreAllMocks();
    await rm(dir, { recursive: true, force: true });
  });

  const settle = async (g: Getter, id: string): Promise<GetJob> => {
    for (let i = 0; i < 200; i++) {
      const j = g.list().find((x) => x.id === id)!;
      if (["done", "failed", "notFound"].includes(j.state)) return j;
      await new Promise((r) => setTimeout(r, 5));
    }
    throw new Error("never settled");
  };

  const deps = (over: Record<string, unknown> = {}) => {
    const committed: string[] = [];
    const library = new Set<string>();
    return {
      committed,
      library,
      deps: {
        api: { loggedIn: async () => true } as never,
        downloadsDir: join(dir, "dl"),
        probe: async () => ({ codec: "flac", durationMs: 312_000 }) as never,
        commit: async (path: string) => {
          committed.push(path);
          return "newsha";
        },
        inLibrary: (w: { title: string }) => (library.has(w.title) ? "have" : null),
        afterCommit: async () => {},
        deezer: {
          searchAlbumCandidates: async () => [{ id: 9, title: "ASTROWORLD", artist: "Travis Scott", coverUrl: null }],
          albumTracks: async () => [
            { title: "STARGAZING", artist: "Travis Scott", durationMs: 270_000, trackNumber: 1, discNumber: 1 },
            { title: "CAROUSEL", artist: "Travis Scott", durationMs: 180_000, trackNumber: 2, discNumber: 1 },
            { title: "SICKO MODE", artist: "Travis Scott", durationMs: 312_000, trackNumber: 3, discNumber: 1 },
          ],
        },
        release: (id: string) =>
          id === "r1" ? { id, title: "ASTROWORLD", artist: "Travis Scott", trackShas: ["s1"], totalTracks: 3 } : null,
        log,
        ...over,
      },
    };
  };

  const fakeAcquire = () =>
    vi.spyOn(resource, "acquire").mockImplementation(async (_api, w) => {
      await mkdir(join(dir, "dl", w.title), { recursive: true });
      const path = join(dir, "dl", w.title, "f.flac");
      await writeFile(path, "x");
      return { path, candidate: {} as never };
    });

  it("fetches, checks, commits, and says done with the new song", async () => {
    fakeAcquire();
    const { deps: d, committed } = deps();
    const g = new Getter(d);
    const job = g.get({ title: "SICKO MODE", artist: "Travis Scott", durationMs: 312_000 });
    expect(job.state).toBe("queued");
    const done = await settle(g, job.id);
    expect(done.state).toBe("done");
    expect(done.sha).toBe("newsha");
    expect(committed).toHaveLength(1);
  });

  it("a file of the wrong length is not kept", async () => {
    fakeAcquire();
    const { deps: d, committed } = deps({ probe: async () => ({ codec: "flac", durationMs: 200_000 }) });
    const g = new Getter(d);
    const job = g.get({ title: "SICKO MODE", artist: "Travis Scott", durationMs: 312_000 });
    expect((await settle(g, job.id)).state).toBe("failed");
    expect(committed).toHaveLength(0);
  });

  it("asked twice, one job; already here, done at once", async () => {
    fakeAcquire();
    const { deps: d, library } = deps();
    const g = new Getter(d);
    const a = g.get({ title: "SICKO MODE", artist: "Travis Scott" });
    const b = g.get({ title: "sicko mode", artist: "travis scott" });
    expect(b.id).toBe(a.id);
    library.add("STARGAZING");
    const c = g.get({ title: "STARGAZING", artist: "Travis Scott" });
    expect(c.state).toBe("done");
    expect(c.sha).toBe("have");
  });

  it("an album's track list marks what is here, and finishing it gets the rest", async () => {
    fakeAcquire();
    const { deps: d, library } = deps();
    library.add("STARGAZING");
    const g = new Getter(d);
    const list = await g.tracklist("r1");
    expect(list?.map((t) => [t.title, t.have])).toEqual([
      ["STARGAZING", "have"],
      ["CAROUSEL", null],
      ["SICKO MODE", null],
    ]);
    const jobs = await g.complete("r1");
    expect(jobs.map((j) => j.title)).toEqual(["CAROUSEL", "SICKO MODE"]);
    expect(jobs.every((j) => j.release === "r1")).toBe(true);
  });

  it("waits while a background pass has the downloads folder", async () => {
    const acq = fakeAcquire();
    let pass = true;
    const { deps: d } = deps({ passRunning: () => pass });
    vi.useFakeTimers({ shouldAdvanceTime: true });
    try {
      const g = new Getter(d);
      g.get({ title: "SICKO MODE", artist: "Travis Scott", durationMs: 312_000 });
      await vi.advanceTimersByTimeAsync(12_000);
      expect(acq).not.toHaveBeenCalled();
      pass = false;
      await vi.advanceTimersByTimeAsync(6_000);
      // The get then makes the downloads folder on the real disk, which fake
      // time does not hurry: wait for it rather than assume one tick.
      await vi.waitFor(() => expect(acq).toHaveBeenCalled(), { timeout: 5_000, interval: 20 });
    } finally {
      vi.useRealTimers();
    }
  });
  it("keeps the line across a restart: a cut-off get goes back in line", async () => {
    const statePath = join(dir, "gets.json");
    // A pass holds the folder, so nothing starts before the "restart".
    const { deps: d } = deps({ statePath, passRunning: () => true });
    const g = new Getter(d);
    const a = g.get({ title: "SICKO MODE", artist: "Travis Scott", by: "Dennis" });
    const b = g.get({ title: "CAROUSEL", artist: "Travis Scott" });
    await g.flushed();
    // As if it died mid-download.
    const saved = JSON.parse(await readFile(statePath, "utf8"));
    saved.jobs[0].state = "downloading";
    saved.jobs[0].progress = 0.4;
    await writeFile(statePath, JSON.stringify(saved));

    const acq = fakeAcquire();
    const { deps: d2, committed } = deps({ statePath });
    const again = new Getter(d2);
    expect((await settle(again, a.id)).state).toBe("done");
    expect((await settle(again, b.id)).state).toBe("done");
    expect(acq).toHaveBeenCalledTimes(2);
    expect(committed).toHaveLength(2);
    expect(again.list().find((j) => j.id === a.id)?.by).toBe("Dennis");
    // The line is saved after each song; let the last save land before the
    // folder is cleaned up (CI caught ENOTEMPTY on rmdir).
    await vi.waitFor(async () => {
      await again.flushed();
      expect(JSON.parse(await readFile(statePath, "utf8")).requests).toEqual([]);
    });
    await g.flushed();
  });

  it("says where each waiting song is in line, and lets one be taken out", async () => {
    const { deps: d } = deps({ passRunning: () => true });
    const g = new Getter(d);
    const a = g.get({ title: "STARGAZING", artist: "Travis Scott" });
    const b = g.get({ title: "CAROUSEL", artist: "Travis Scott" });
    const c = g.get({ title: "SICKO MODE", artist: "Travis Scott" });
    const pos = (id: string) => g.list().find((j) => j.id === id)?.position;
    expect([pos(a.id), pos(b.id), pos(c.id)]).toEqual([1, 2, 3]);
    expect(g.cancel(b.id)).toBe(true);
    expect([pos(a.id), pos(c.id)]).toEqual([1, 2]);
    expect(g.cancel(b.id)).toBe(false);
    // Taken out, not failed: a cleared line is not a list of failures.
    expect(g.list().find((j) => j.id === b.id)?.state).toBe("cancelled");
    // And asking again starts a new get rather than handing back the old one.
    expect(g.get({ title: "CAROUSEL", artist: "Travis Scott" }).id).not.toBe(b.id);
    await g.flushed();
  });

  it("waits for Soulseek to log in rather than failing a resumed get", async () => {
    fakeAcquire();
    let online = false;
    const { deps: d } = deps({ api: { loggedIn: async () => online } });
    vi.useFakeTimers({ shouldAdvanceTime: true });
    try {
      const g = new Getter(d);
      const job = g.get({ title: "SICKO MODE", artist: "Travis Scott", durationMs: 312_000 });
      await vi.advanceTimersByTimeAsync(25_000);
      expect(g.list()[0]?.state).toBe("queued");
      online = true;
      await vi.advanceTimersByTimeAsync(11_000);
      await vi.waitFor(() => expect(g.list().find((j) => j.id === job.id)?.state).toBe("done"), {
        timeout: 5_000,
        interval: 20,
      });
    } finally {
      vi.useRealTimers();
    }
  });
});

describe("who asked", () => {
  it("names the account from the token, and nothing from junk", async () => {
    const { askerName } = await import("../src/serve.js");
    const tok = (claims: object) =>
      `Bearer x.${Buffer.from(JSON.stringify(claims)).toString("base64url")}.y`;
    expect(askerName(tok({ sub: "acct-dennis" }))).toBe("Dennis");
    expect(askerName(tok({ sub: 42 }))).toBeNull();
    expect(askerName("Bearer nonsense")).toBeNull();
    expect(askerName(undefined)).toBeNull();
  });
});

describe("the week's gets", () => {
  it("a day by default, up to a week when asked", () => {
    let now = new Date("2026-10-20T12:00:00Z");
    const g = new Getter({
      api: { loggedIn: async () => true } as never,
      inLibrary: () => "have",
      log: { info() {}, warn() {}, error() {} } as never,
      now: () => now,
    } as never);
    g.get({ title: "Old", artist: "A" });
    now = new Date("2026-10-23T12:00:00Z");
    g.get({ title: "New", artist: "A" });
    expect(g.list().map((j) => j.title)).toEqual(["New"]);
    expect(g.list(7).map((j) => j.title)).toEqual(["New", "Old"]);
    expect(g.list(30).map((j) => j.title)).toEqual(["New", "Old"]);
  });
});
