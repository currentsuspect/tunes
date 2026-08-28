import { readFileSync } from "node:fs";
import { join } from "node:path";
import { MusicBrainzClient } from "../src/enrich.js";
import type { EnrichmentEntry } from "../src/enrich.js";
import { ObjectStore } from "../src/store.js";
import { probeFile } from "../src/probe.js";

const norm = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
const bare = (s: string) => norm(s.replace(/\s*\(.*?\)\s*/g, " "));

async function main() {
  const dataDir = join(process.cwd(), "data");
  const enrichRaw = JSON.parse(readFileSync(join(dataDir, "enrich.json"), "utf8")) as {
    entries: Record<string, EnrichmentEntry>;
  };
  const enrich = new Map(Object.entries(enrichRaw.entries ?? {}));
  const store = new ObjectStore(dataDir);
  const groups = new Map<string, string[]>();
  for (const [sha, e] of enrich) {
    if (!e.releaseId) continue;
    const list = groups.get(e.releaseId) ?? [];
    list.push(sha);
    groups.set(e.releaseId, list);
  }
  const mb = new MusicBrainzClient("tunes/0.1-debug ( https://github.com/currentsuspect/tunes )", dataDir);
  for (const [releaseId, shas] of groups) {
    if (!releaseId.startsWith("mb:")) continue;
    if (shas.length < 2) continue;
    console.log("== release", releaseId.slice(0, 12), "shas", shas.length);
    const release = await mb.releaseWithRecordings(releaseId.slice(3));
    console.log("   fetched:", release ? release.title + " (" + release.tracks.length + " tracks)" : "NULL");
    if (!release) continue;
    for (const sha of shas) {
      const e = enrich.get(sha);
      if (!e || e.trackNumber != null) continue;
      const probe = await probeFile(sha, 0, store.pathOf(sha)).catch(() => null);
      const state2 = JSON.parse(readFileSync(join(dataDir, "state.json"), "utf8")) as {
        seen: Record<string, { sha?: string; fileName?: string } | string>;
      };
      const metaFor = (target: string): string | null => {
        for (const v of Object.values(state2.seen)) {
          if (typeof v === "string") continue;
          if (v.sha === target && v.fileName) {
            return v.fileName.replace(/\.[^.]+$/, "").replace(/\s+/g, " ").trim();
          }
        }
        return null;
      };
      const metaTitle = metaFor(sha);
      const dash = metaTitle ? metaTitle.indexOf(" - ") : -1;
      const parsedArtist = dash > 0 ? metaTitle!.slice(0, dash).trim() : null;
      const parsedTitle = dash > 0 ? metaTitle!.slice(dash + 3).trim() : null;
      const title = (probe?.tags.title ?? null) ?? (parsedTitle ?? metaTitle);
      const durMs = probe?.durationMs ?? null;
      const b = title ?? e.album;
      const match = release.tracks.find((t) => {
        const titleOk = bare(t.title) === bare(b ?? "") || norm(t.title) === norm(b ?? "");
        const durOk = t.lengthMs == null || durMs == null || Math.abs(t.lengthMs - durMs) <= 4000;
        return titleOk && durOk;
      });
      console.log("   ", (title ?? e.album ?? "?").slice(0, 34), "dur", durMs ? Math.round(durMs/1000)+"s" : "?",
        "->", match ? "d" + match.discNumber + "#" + match.position : "NO MATCH");
    }
  }
}
void main().catch((e) => { console.error(String(e)); process.exit(1); });
