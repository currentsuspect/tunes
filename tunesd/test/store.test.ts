import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { ObjectStore } from "../src/store.js";
import { RetryableError } from "../src/telegram/ports.js";

let dir: string;
let store: ObjectStore;

beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), "tunes-store-"));
  store = new ObjectStore(dir);
});

afterEach(async () => {
  await rm(dir, { recursive: true, force: true });
});

describe("ObjectStore", () => {
  it("finalizes a staged file into its content-addressed path", async () => {
    const staging = await store.beginStaging();
    await writeFile(staging.path, "hello tunes");
    const { sha, size } = await staging.done(11);
    expect(size).toBe(11);
    expect(store.has(sha)).toBe(true);
    const bytes = await readFile(store.pathOf(sha), "utf8");
    expect(bytes).toBe("hello tunes");
  });

  it("rejects a size mismatch and discards the staging file", async () => {
    const staging = await store.beginStaging();
    const stagingPath = staging.path;
    await writeFile(stagingPath, "x");
    await expect(staging.done(999)).rejects.toBeInstanceOf(RetryableError);
    await expect(readFile(stagingPath)).rejects.toThrow();
  });

  it("dedupes identical bytes in the object store", async () => {
    const a = await store.beginStaging();
    const b = await store.beginStaging();
    await writeFile(a.path, "same bytes");
    await writeFile(b.path, "same bytes");
    const ra = await a.done(10);
    const rb = await b.done(10);
    expect(ra.sha).toBe(rb.sha);
  });

  it("verify() detects corruption", async () => {
    const staging = await store.beginStaging();
    await writeFile(staging.path, "original");
    const { sha } = await staging.done(8);
    expect(await store.verify(sha)).toBe(true);
    await writeFile(store.pathOf(sha), "tampered!!!");
    expect(await store.verify(sha)).toBe(false);
  });
});