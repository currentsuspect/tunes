import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { FetchEngine } from "../src/fetch.js";
import { State } from "../src/state.js";
import { ObjectStore } from "../src/store.js";

const log = { info() {}, warn() {}, error() {}, debug() {} } as any;

let dir: string;
beforeEach(async () => void (dir = await mkdtemp(join(tmpdir(), "engine-"))));
afterEach(async () => rm(dir, { recursive: true, force: true }));

function fakeClient(files: Record<number, string>) {
  return {
    chatAlive: async () => true,
    async *iterAudioMessages() {
      for (const id of Object.keys(files).map(Number)) {
        yield { messageId: id, size: files[id]!.length, caption: `song ${id}`, fileName: `${id}.mp3` };
      }
    },
    downloadAudioTo: async (_c: number, id: number, path: string) => {
      await writeFile(path, files[id]!);
      return files[id]!.length;
    },
  } as any;
}

describe("FetchEngine onDownloaded hook", () => {
  it("fires once per stored file, with its sha, as each lands", async () => {
    const state = await new State(join(dir, "state.json")).load();
    const got: string[] = [];
    const engine = new FetchEngine(
      fakeClient({ 1: "aaaa", 2: "bbbbb" }),
      new ObjectStore(dir),
      state,
      { dataDir: dir, fetch: { perChannelDelayMs: 0, jitterMs: 0, dailyCapFiles: 100 } },
      log,
      { onDownloaded: (d) => void got.push(`${d.sha.length}:${d.size}`) }
    );
    const r = await engine.runCycle([{ id: 7, title: "t", enabled: true }]);
    expect(r.channels[0]!.downloaded).toBe(2);
    expect(got).toEqual(["64:4", "64:5"]);
  });

  it("a throwing hook never breaks ingest", async () => {
    const state = await new State(join(dir, "state.json")).load();
    const engine = new FetchEngine(
      fakeClient({ 1: "aaaa", 2: "bbbbb" }),
      new ObjectStore(dir),
      state,
      { dataDir: dir, fetch: { perChannelDelayMs: 0, jitterMs: 0, dailyCapFiles: 100 } },
      log,
      {
        onDownloaded: () => {
          throw new Error("hook bug");
        },
      }
    );
    const r = await engine.runCycle([{ id: 7, title: "t", enabled: true }]);
    expect(r.channels[0]!.downloaded).toBe(2);
  });
});
