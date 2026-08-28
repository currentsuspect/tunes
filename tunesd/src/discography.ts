import { normalize } from "./manifest.js";

export interface DiscographyGroup {
  id: string;
  title: string;
  type: string | null;
  year: string | null;
  date: string | null;
}

export interface ArtistDiscography {
  name: string;
  mbid: string;
  fetchedAt: number;
  groups: DiscographyGroup[];
}

export interface JoinedGroup extends DiscographyGroup {
  owned: boolean;
  releaseId: string | null;
  ownedTracks: number;
  totalTracks: number | null;
}

export function joinDiscography(
  groups: DiscographyGroup[],
  releases: Array<{
    id: string;
    groupId: string | null;
    title: string;
    trackShas: string[];
    totalTracks: number | null;
  }>
): JoinedGroup[] {
  return groups.map((g) => {
    const byId = releases.find((r) => r.groupId != null && r.groupId === g.id);
    const byTitle =
      byId ??
      releases.find((r) => r.groupId == null && normalize(r.title) === normalize(g.title));
    return {
      ...g,
      owned: byTitle != null,
      releaseId: byTitle?.id ?? null,
      ownedTracks: byTitle?.trackShas.length ?? 0,
      totalTracks: byTitle?.totalTracks ?? null,
    };
  });
}

export interface ExternalArtist {
  name: string;
  mbid: string;
  type: string | null;
  disambiguation: string | null;
  score: number | null;
}

export function dedupeExternalArtists(
  hits: ExternalArtist[],
  localNames: Iterable<string>,
  seenNames = new Set<string>()
): ExternalArtist[] {
  const local = new Set([...localNames].map((n) => normName(n)));
  const out: ExternalArtist[] = [];
  for (const h of hits) {
    const key = normName(h.name);
    if (local.has(key) || seenNames.has(key)) continue;
    seenNames.add(key);
    out.push(h);
  }
  return out;
}

export function normName(s: string): string {
  return s.toLowerCase().replace(/\s+/g, " ").trim();
}

export async function loadDiscographies(
  file: string
): Promise<Map<string, ArtistDiscography>> {
  const m = new Map<string, ArtistDiscography>();
  try {
    const { readFile } = await import("node:fs/promises");
    const raw = JSON.parse(await readFile(file, "utf8")) as {
      artists: Record<string, ArtistDiscography>;
    };
    for (const [name, d] of Object.entries(raw.artists ?? {})) {
      m.set(normName(name), { ...d, name: d.name ?? name });
    }
  } catch {
    // fresh start
  }
  return m;
}

export async function persistDiscographies(
  file: string,
  map: Map<string, ArtistDiscography>
): Promise<void> {
  const { mkdir, rename, writeFile } = await import("node:fs/promises");
  const { dirname } = await import("node:path");
  await mkdir(dirname(file), { recursive: true });
  const tmp = `${file}.${process.pid}.tmp`;
  await writeFile(tmp, JSON.stringify({ artists: Object.fromEntries(map) }, null, 1));
  await rename(tmp, file);
}
