import { createHash } from "node:crypto";

import { parseCredits, releaseArtistOf, stripFeatured } from "./credits.js";
import { parseArtistTitle } from "./enrich.js";
import type { ProbeResult } from "./probe.js";

export interface ManifestTrack {
  sha: string;
  size: number;
  codec: string | null;
  sampleRate: number | null;
  channels: number | null;
  bitrate: number | null;
  durationMs: number | null;
  title: string;
  artist: string;
  album: string;
  year: string | null;
  artSha: string | null;
  releaseId: string | null;
  releaseIds: string[];
  trackNumber: number | null;
  discNumber: number | null;
  // Emitted since v4 but previously undeclared here.
  totalTracks: number | null;
  // The act this track belongs to, with guest credits separated out. `artist`
  // stays exactly as the tagger wrote it for display.
  primaryArtist: string;
  featured: string[];
  addedAt: string | null;
  // v4: embedded tag values from ffprobe, exposed so the app can
  // implement a local-wins policy for identity fields.
  embeddedTitle: string | null;
  embeddedArtist: string | null;
  embeddedAlbum: string | null;
  embeddedYear: string | null;
  lyrics: string | null;
  lyricsSource: string | null;
}

export interface ManifestRelease {
  id: string;
  title: string;
  artist: string;
  year: string | null;
  artSha: string | null;
  type: string | null;
  totalTracks: number | null;
  groupId: string | null;
  trackShas: string[];
  tracks: Array<{ sha: string; trackNumber: number | null; discNumber: number | null }>;
}

export interface ManifestV4 {
  schema: 4;
  generatedAt: string;
  integrity: string;
  tracks: ManifestTrack[];
  releases: ManifestRelease[];
  artists: Array<{ name: string; artSha: string | null }>;
}

// Schema 3 was the v3 wire format. Keep the type so callers that import
// ManifestV3 still compile while the app rolls over to v4.
export type ManifestV3 = ManifestV4;

export interface TrackMeta {
  caption: string | null;
  fileName: string | null;
}

export interface TrackEnrichment {
  artist: string | null;
  album: string | null;
  year: string | null;
  artSha: string | null;
  releaseId: string | null;
  releaseType: string | null;
  trackNumber: number | null;
  discNumber: number | null;
  totalTracks: number | null;
  membership: Array<{ id: string; position: number | null; disc: number | null }>;
}

export interface ReleaseLinkMeta {
  title: string;
  type: string | null;
  totalTracks: number | null;
  groupId?: string | null;
  date?: string | null;
}

export function normalize(s: string): string {
  return s.toLowerCase().replace(/\s+/g, " ").trim();
}

const norm = normalize;

const CATEGORY_RELEASES = new Set([
  "alt rap", "rap", "hip hop", "hip-hop", "r&b", "rnb", "drill", "afrobeats",
  "house", "techno", "edm", "rock", "pop", "indie", "metal", "jazz", "grime",
  "phonk", "soul", "gospel", "reggae", "dancehall", "amapiano", "trap",
  "ambient", "lo-fi", "lofi", "classical", "drum and bass", "dnb", "garage",
  "synthwave", "vaporwave", "punk", "country", "folk", "blues", "funk",
  "disco", "latin", "k-pop", "j-pop", "soundtrack", "instrumental",
  "remixes", "remix", "greatest hits", "best of", "hits", "singles",
]);

export function isCategoryRelease(title: string): boolean {
  return CATEGORY_RELEASES.has(norm(title));
}

function titleTokens(title: string): string[] {
  return norm(title)
    .split(/[\/\-\s]+/)
    .filter((t) => t.length > 0);
}

function tokenSubset(small: string, big: string): boolean {
  const s = titleTokens(small);
  const b = new Set(titleTokens(big));
  return s.length > 0 && s.every((t) => b.has(t));
}

function fallbackReleaseKey(track: {
  artist: string;
  album: string;
  sha: string;
}): string {
  const artist = norm(track.artist);
  const album = norm(track.album);
  if (artist === "unknown artist" && album === "unknown album") {
    return `sha:${track.sha}`;
  }
  return `name:${artist}|${album}`;
}

/**
 * Which release a track belongs to.
 *
 * SPEC §1.2 puts release metadata at the bottom of the identity hierarchy:
 * MusicBrainz "tells us what something probably is", it never decides what a
 * thing *is*. So when the file states its own album, that answer wins and the
 * track is grouped by (act, album) — keyed on the act rather than the raw
 * credit line, so guests do not split an album apart. A provider release id is
 * only the key when the file said nothing.
 */
function releaseKeyFor(
  track: { primaryArtist: string; album: string; sha: string; artist: string },
  fileStatedAlbum: boolean,
  providerReleaseId: string | null | undefined
): string {
  if (fileStatedAlbum) {
    const act = norm(track.primaryArtist) || norm(track.artist);
    return `name:${act}|${norm(track.album)}`;
  }
  return providerReleaseId ?? fallbackReleaseKey(track);
}

export function buildManifest(
  probes: ProbeResult[],
  metaBySha: Map<string, TrackMeta> = new Map(),
  enrichBySha: Map<string, TrackEnrichment> = new Map(),
  objects: Array<{ sha: string; size: number }> = [],
  artists: Array<{ name: string; artSha: string | null }> = [],
  linkMeta: Map<string, ReleaseLinkMeta> = new Map(),
  addedAtBySha: Map<string, string> = new Map(),
  embeddedArtBySha: Map<string, string> = new Map()
): ManifestV4 {
  const probeFor = new Map(probes.map((p) => [p.sha, p]));
  for (const obj of objects) {
    if (!probeFor.has(obj.sha)) {
      probeFor.set(obj.sha, {
        sha: obj.sha,
        size: obj.size,
        codec: null,
        sampleRate: null,
        channels: null,
        bitrate: null,
        durationMs: null,
        tags: {},
        hasEmbeddedArt: false,
        probedAt: "",
      });
    }
  }
  const allProbes = [...probeFor.values()];
  const tracks: ManifestTrack[] = allProbes
    .map((p) => {
      const meta = metaBySha.get(p.sha);
      const enrich = enrichBySha.get(p.sha);
      const tagged = Boolean(p.tags.title) || Boolean(p.tags.artist) || Boolean(p.tags.album);
      // Filename parse is the last-resort seed for both title and artist
      // when no embedded tags and no enrich hit. Available even when
      // tags ARE present (e.g. title tagged, artist not), since
      // parseArtistTitle returns null when the filename doesn't have
      // the "Artist - Title" shape.
      const filenameParse = meta?.fileName
        ? parseArtistTitle(meta.fileName)
        : null;
      const captionTitle =
        meta?.caption && meta.caption.trim() !== ""
          ? meta.caption.trim()
          : null;
      let title = p.tags.title?.trim() ?? captionTitle ?? filenameParse?.title ?? "";
      if (title === "" && meta?.fileName) {
        title = meta.fileName.replace(/\.[^.]+$/, "").replace(/\s+/g, " ").trim();
        const dash = title.indexOf(" - ");
        const enrichArtist = enrich?.artist ?? null;
        if (dash > 0 && enrichArtist && norm(title.slice(0, dash)) === norm(enrichArtist)) {
          title = title.slice(dash + 3).trim();
        }
      }
      const artist = p.tags.artist?.trim()
        ?? filenameParse?.artist
        ?? enrich?.artist
        ?? "unknown artist";
      const album = p.tags.album?.trim()
        ?? enrich?.album
        ?? "unknown album";
      const year = p.tags.year ?? enrich?.year ?? null;
      // One album routinely carries a different artist string per track
      // ("Yeat", "Yeat, Don Toliver", "Yeat;Summrs"), which used to shatter it
      // into a release per credit line. Recover the act and the guests.
      const credits = parseCredits(artist);
      const titleCredits = stripFeatured(title);
      const featured = [...credits.featured];
      for (const name of titleCredits.featured) {
        if (!featured.some((f) => f.toLowerCase() === name.toLowerCase())) featured.push(name);
      }
      const releaseArtist = releaseArtistOf(p.tags.albumArtist ?? null, artist);
      // A genre-compilation match ("Trap", "Phonk") is not a real album, so we
      // drop it — but only when it is the *only* thing we have. The file's own
      // ALBUM tag is ground truth and outranks any network guess about it.
      const categoryRelease =
        enrich?.releaseId != null &&
        isCategoryRelease(enrich?.album ?? "") &&
        !p.tags.album;
      const fileNamedAlbum = Boolean(p.tags.album?.trim());
      const releaseKey = releaseKeyFor(
        { primaryArtist: releaseArtist, album: categoryRelease ? "unknown album" : album, sha: p.sha, artist },
        fileNamedAlbum,
        categoryRelease ? null : enrich?.releaseId
      );
      // Cover art the tagger embedded is always about this exact recording;
      // a release-level cover fetched from a provider is an approximation.
      const embeddedArtSha = embeddedArtBySha.get(p.sha) ?? null;
      return {
        sha: p.sha,
        size: p.size,
        codec: p.codec,
        sampleRate: p.sampleRate,
        channels: p.channels,
        bitrate: p.bitrate,
        durationMs: p.durationMs,
        title: title !== "" ? title : "untitled",
        artist,
        album: categoryRelease ? "unknown album" : album,
        year,
        artSha: (categoryRelease ? null : enrich?.artSha ?? null) ?? embeddedArtSha,
        // The id of the release this track is actually grouped into. Keeping a
        // provider id here while grouping by the file's album would leave a
        // track pointing at a release that does not contain it.
        releaseId: releaseKey.startsWith("sha:") ? null : releaseKey,
        // Provider ids stay as cross-references for anything that wants them.
        releaseIds: [
          ...new Set([
            ...(releaseKey.startsWith("sha:") ? [] : [releaseKey]),
            ...(categoryRelease ? [] : enrich?.releaseId != null ? [enrich.releaseId] : []),
            ...(fileNamedAlbum ? [] : (enrich?.membership ?? []).map((m) => m.id)),
          ]),
        ],
        // Track/disc position decides running order inside a release, so the
        // tagger's own numbering wins over a position we inferred from a
        // provider's tracklist.
        trackNumber: p.tags.trackNumber ?? enrich?.trackNumber ?? null,
        discNumber: p.tags.discNumber ?? enrich?.discNumber ?? null,
        totalTracks: p.tags.totalTracks ?? enrich?.totalTracks ?? null,
        primaryArtist: releaseArtist,
        featured,
        addedAt: addedAtBySha.get(p.sha) ?? null,
        // v4: embedded tag values as discovered by ffprobe. The app's
        // query layer applies a local-wins policy over these.
        embeddedTitle: p.tags.title?.trim() || null,
        embeddedArtist: p.tags.artist?.trim() || null,
        embeddedAlbum: p.tags.album?.trim() || null,
        embeddedYear: p.tags.year ?? null,
        lyrics: null,
        lyricsSource: null,
      };
    })
    .sort((a: ManifestTrack, b: ManifestTrack) => (a.sha < b.sha ? -1 : a.sha > b.sha ? 1 : 0));

  // Tracks whose album came from the file itself, not from a provider.
  const fileStatedAlbum = new Set(
    allProbes.filter((p) => Boolean(p.tags.album?.trim())).map((p) => p.sha)
  );
  const releaseMap = new Map<string, ManifestRelease>();
  // Everyone credited on each release, so a joint album can be recognised even
  // when the tagger rotates the running order of the names track by track.
  const releaseCredits = new Map<string, Set<string>>();
  const creditsOf = (id: string): Set<string> => {
    let set = releaseCredits.get(id);
    if (!set) {
      set = new Set<string>();
      releaseCredits.set(id, set);
    }
    return set;
  };
  const ensureRelease = (
    t: ManifestTrack,
    enrich: TrackEnrichment | undefined,
    id: string,
    meta?: ReleaseLinkMeta
  ): ManifestRelease => {
    let release = releaseMap.get(id);
    if (release) return release;
    release = {
      id,
      title: meta?.title ?? t.album,
      // The act, not the per-track credit line — the merge pass below compares
      // release artists for equality and "Yeat" never equalled "Yeat;Summrs".
      artist: t.primaryArtist || t.artist,
      year: enrich?.year ?? t.year,
      artSha: t.artSha,
      type: meta?.type ?? enrich?.releaseType ?? null,
      totalTracks: meta?.totalTracks ?? enrich?.totalTracks ?? null,
      groupId: meta?.groupId ?? null,
      trackShas: [],
      tracks: [],
    };
    releaseMap.set(id, release);
    return release;
  };
  const addTrackToRelease = (
    release: ManifestRelease,
    sha: string,
    num: number | null,
    disc: number | null
  ) => {
    if (!release.trackShas.includes(sha)) release.trackShas.push(sha);
    if (!release.tracks.some((x) => x.sha === sha)) {
      release.tracks.push({ sha, trackNumber: num, discNumber: disc });
    }
  };
  for (const t of tracks) {
    const enrich = enrichBySha.get(t.sha);
    const key =
      t.releaseId ?? releaseKeyFor(t, fileStatedAlbum.has(t.sha), enrich?.releaseId);
    const primary = ensureRelease(t, enrich, key);
    if (primary.groupId == null) {
      const meta = linkMeta.get(key);
      if (meta?.groupId != null) primary.groupId = meta.groupId;
    }
    const credited = creditsOf(key);
    for (const name of [t.primaryArtist, ...t.featured]) {
      const clean = norm(name);
      if (clean !== "" && clean !== "unknown artist") credited.add(clean);
    }
    addTrackToRelease(primary, t.sha, enrich?.trackNumber ?? null, enrich?.discNumber ?? null);
    if (primary.artSha == null) primary.artSha = t.artSha;
    if (primary.totalTracks == null) {
      const meta = linkMeta.get(key);
      if (meta?.totalTracks != null) primary.totalTracks = meta.totalTracks;
    }
    // Membership crosslinks place a track inside a provider's release. When the
    // file already names its album that is just a second, competing home for
    // the same track, so it would show up as a phantom extra album.
    for (const m of fileStatedAlbum.has(t.sha) ? [] : enrich?.membership ?? []) {
      let member = releaseMap.get(m.id);
      if (!member) {
        const meta = linkMeta.get(m.id);
        member = ensureRelease(t, undefined, m.id, meta);
      }
      addTrackToRelease(member, t.sha, m.position, m.disc);
      if (member.artSha == null) member.artSha = t.artSha;
      if (member.totalTracks == null) {
        const meta = linkMeta.get(m.id);
        if (meta?.totalTracks != null) member.totalTracks = meta.totalTracks;
      }
    }
  }
  const merged = new Map<string, ManifestRelease>();
  for (const r of releaseMap.values()) {
    merged.set(r.id, { ...r, trackShas: [...r.trackShas] });
  }
  // Absorbed release id -> surviving release id. Merging without this leaves
  // the absorbed release's tracks naming an id that no longer exists.
  const redirected = new Map<string, string>();
  let mergedAnything = true;
  while (mergedAnything) {
    mergedAnything = false;
    const ids = [...merged.keys()];
    for (const id of ids) {
      const r = merged.get(id);
      if (!r) continue;
      for (const [oid, other] of merged) {
        if (oid === id) continue;
        // Same act, or the same album credited to an overlapping cast. The
        // second case is a joint album: CONGLOMERATE lists "Fimiguerrero, Len",
        // "Len, Fimiguerrero" and "Lancey Foux, Fimiguerrero, Len" across its
        // tracks, which is one record, not three. Disjoint casts stay apart, so
        // two different albums that happen to share a title are unaffected.
        const sameAct = other.artist === r.artist;
        const sharedCast = [...creditsOf(r.id)].some((n) => creditsOf(other.id).has(n));
        const jointAlbum = norm(other.title) === norm(r.title) && sharedCast;
        if (!sameAct && !jointAlbum) continue;
        if (other.year !== r.year && other.year != null && r.year != null) continue;
        const rSmaller = r.trackShas.length <= other.trackShas.length;
        const small = rSmaller ? r : other;
        const big = rSmaller ? other : r;
        if (small.trackShas.length === 0) continue;
        const bothUnknown =
          small.title === "unknown album" && big.title === "unknown album";
        const exactTitle = norm(small.title) === norm(big.title);
        if (small.trackShas.length > 8 && !bothUnknown && !exactTitle) continue;
        if (!bothUnknown && !tokenSubset(small.title, big.title)) continue;
        for (const sha of small.trackShas) {
          if (!big.trackShas.includes(sha)) big.trackShas.push(sha);
        }
        for (const tr of small.tracks) {
          if (!big.tracks.some((x) => x.sha === tr.sha)) big.tracks.push(tr);
        }
        big.totalTracks = Math.max(
          big.totalTracks ?? 0,
          small.totalTracks ?? 0,
          big.trackShas.length
        );
        const bigCast = creditsOf(big.id);
        for (const n of creditsOf(small.id)) bigCast.add(n);
        if (jointAlbum && !sameAct) {
          // Credit the whole cast, deterministically, so the card does not
          // claim a joint record belongs to whichever name sorted first.
          const names = new Set<string>();
          for (const part of [...big.artist.split(", "), ...small.artist.split(", ")]) {
            const name = part.trim();
            if (name !== "") names.add(name);
          }
          big.artist = [...names].sort((x, y) => x.localeCompare(y)).join(", ");
        }
        redirected.set(small.id, big.id);
        merged.delete(small.id);
        mergedAnything = true;
        break;
      }
    }
  }
  if (redirected.size > 0) {
    const resolve = (id: string): string => {
      let current = id;
      for (let hops = 0; hops < redirected.size + 1; hops++) {
        const next = redirected.get(current);
        if (next == null) break;
        current = next;
      }
      return current;
    };
    for (const t of tracks) {
      if (t.releaseId != null) t.releaseId = resolve(t.releaseId);
      t.releaseIds = [...new Set(t.releaseIds.map(resolve))];
    }
  }
  for (const r of merged.values()) {
    if (r.artSha == null) {
      for (const t of tracks) {
        if (r.trackShas.includes(t.sha) && t.artSha != null) {
          r.artSha = t.artSha;
          break;
        }
      }
    }
  }
  const releases = [...merged.values()]
    .sort((a, b) =>
      a.artist !== b.artist ? a.artist.localeCompare(b.artist) : a.title.localeCompare(b.title)
    )
    .map((r) => {
      const fallbackRows = r.tracks.length > 0
        ? r.tracks
        : [...r.trackShas].map((sha) => {
            const t = tracks.find((x) => x.sha === sha);
            return {
              sha,
              trackNumber: t?.trackNumber ?? null,
              discNumber: t?.discNumber ?? null,
            };
          });
      const sorted = [...fallbackRows].sort((a, b) => {
        const da = a.discNumber ?? 1;
        const db = b.discNumber ?? 1;
        if (da !== db) return da - db;
        const na = a.trackNumber ?? 999;
        const nb = b.trackNumber ?? 999;
        if (na !== nb) return na - nb;
        return a.sha < b.sha ? -1 : 1;
      });
      const groupId = r.groupId ?? linkMeta.get(r.id)?.groupId ?? null;
      return { ...r, groupId, trackShas: sorted.map((x) => x.sha), tracks: sorted };
    });

  const integrityBody = JSON.stringify({ schema: 4, tracks, releases });
  const integrity = createHash("sha256").update(integrityBody).digest("hex").slice(0, 16);

  return {
    schema: 4,
    generatedAt: new Date().toISOString(),
    integrity,
    tracks,
    releases,
    artists: [...artists].sort((a, b) => a.name.localeCompare(b.name)),
  };
}