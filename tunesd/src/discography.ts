import { normalize } from "./manifest.js";

export interface DiscographyGroup {
  id: string;
  title: string;
  type: string | null;
  year: string | null;
  date: string | null;
  artist?: string | null;
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

/** A release group by an act in the library that the library does not have. */
export interface MissingRelease extends DiscographyGroup {
  /** The act it belongs to, spelled the way the library spells it. */
  forArtist: string;
  /** How many of that act's tracks are held, which is the ranking signal. */
  artistTracks: number;
  /**
   * How far through that act's catalogue the library is: releases held, out of
   * releases that exist.
   *
   * Counted over exactly the same set the suggestions are drawn from -- albums
   * and EPs, never singles -- so held plus missing equals the total and the
   * arithmetic on screen is checkable. A denominator that quietly included two
   * hundred singles would make every collection look abandoned.
   */
  artistOwnedReleases: number;
  artistTotalReleases: number;
}

/**
 * Titles compare more strictly than names do. `normName` only lowercases and
 * collapses spaces, which is right for artists but leaves "Don't Be Dumb" and
 * "Don’t Be Dumb" — a straight apostrophe against a curly one — looking like
 * two different albums, and the whole feature turns on deciding whether a
 * title is already owned.
 */
function titleKey(s: string): string {
  return s
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

/**
 * The same title with a trailing edition qualifier dropped, so "2093 (P2)"
 * and "2093" are one record when asking "do you already have this?".
 *
 * Deliberately only a *trailing bracketed* suffix. Trimming more — a token
 * subset, say — would fold "Alivë" into "2 Alivë", which are two different
 * Yeat albums, and quietly stop recommending one of them.
 */
function baseTitleKey(s: string): string {
  const stripped = titleKey(s.replace(/\s*[([{][^)\]}]*[)\]}]\s*$/, ""));
  return stripped === "" ? titleKey(s) : stripped;
}

/**
 * Albums by acts already in the library that the library does not have.
 *
 * This replaces a "missing" count derived from track totals, which could only
 * ever say "you have 14 of 16 of something you already own" and, once the
 * totals were made truthful, said nothing at all.
 *
 * **An artist whose discography we cannot corroborate is skipped, not
 * guessed.** Discographies are fetched by name, and MusicBrainz answers a
 * common name with whichever artist it likes: asking for "Lunchbox" returns an
 * indie act with none of the rapper's records, and "Len" returns the nineties
 * band. Recommending those would swap one untruth for another. So an act only
 * contributes suggestions when at least one group in its discography matches
 * something already held — proof we resolved the right artist.
 *
 * The cost is real and worth naming: an act whose held material is not an
 * official release (a leak, a mixtape) corroborates against nothing and is
 * skipped even when the discography is correct.
 *
 * Singles and compilations are excluded by default. A discography is mostly
 * singles, and a list of two hundred of them is not a thing anyone can act on.
 */
export function missingFromCollection(
  libraryArtists: Array<{ name: string; tracks: number }>,
  discographies: Map<string, ArtistDiscography>,
  releases: Array<{ title: string; groupId?: string | null }>,
  opts: { limit?: number; types?: ReadonlySet<string> } = {}
): MissingRelease[] {
  const types = opts.types ?? new Set(["album", "ep"]);
  const ownedGroupIds = new Set(
    releases.map((r) => r.groupId).filter((id): id is string => id != null)
  );
  const ownedTitles = new Set(releases.map((r) => titleKey(r.title)));
  const ownedBaseTitles = new Set(releases.map((r) => baseTitleKey(r.title)));
  const isOwned = (g: DiscographyGroup): boolean =>
    ownedGroupIds.has(g.id) ||
    ownedTitles.has(titleKey(g.title)) ||
    ownedBaseTitles.has(baseTitleKey(g.title));

  const out: MissingRelease[] = [];
  const seen = new Set<string>();
  // Strongest signal first, so a cap keeps the acts the owner listens to most.
  const ranked = [...libraryArtists].sort(
    (a, b) => b.tracks - a.tracks || a.name.localeCompare(b.name)
  );
  for (const artist of ranked) {
    const d = discographies.get(normName(artist.name));
    if (!d) continue;
    if (!d.groups.some(isOwned)) continue;
    const catalogue = d.groups.filter((g) => types.has((g.type ?? "").toLowerCase()));
    const ownedReleases = catalogue.filter(isOwned).length;
    for (const g of d.groups) {
      if (isOwned(g)) continue;
      if (!types.has((g.type ?? "").toLowerCase())) continue;
      // One album can sit in two acts' discographies; credit it to the act
      // with more tracks held, which the ranking above visits first.
      if (seen.has(g.id)) continue;
      seen.add(g.id);
      out.push({
        ...g,
        forArtist: artist.name,
        artistTracks: artist.tracks,
        artistOwnedReleases: ownedReleases,
        artistTotalReleases: catalogue.length,
      });
    }
  }
  out.sort(
    (a, b) =>
      b.artistTracks - a.artistTracks ||
      (b.date ?? b.year ?? "").localeCompare(a.date ?? a.year ?? "") ||
      a.title.localeCompare(b.title)
  );
  return opts.limit != null ? out.slice(0, opts.limit) : out;
}

export interface ExternalArtist {
  name: string;
  mbid: string;
  type: string | null;
  disambiguation: string | null;
  score: number | null;
}

export function dedupeExternalReleases(
  hits: DiscographyGroup[],
  localTitles: Iterable<string>
): DiscographyGroup[] {
  const local = new Set([...localTitles].map((t) => normName(t)));
  const seen = new Set<string>();
  const out: DiscographyGroup[] = [];
  for (const h of hits) {
    const key = normName(h.title);
    if (local.has(key) || seen.has(key)) continue;
    seen.add(key);
    out.push(h);
  }
  return out;
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
