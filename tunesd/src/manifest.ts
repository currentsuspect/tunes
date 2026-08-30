import { createHash } from "node:crypto";
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
  addedAt: string | null;
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

export interface ManifestV3 {
  schema: 3;
  generatedAt: string;
  integrity: string;
  tracks: ManifestTrack[];
  releases: ManifestRelease[];
  artists: Array<{ name: string; artSha: string | null }>;
}

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

export function buildManifest(
  probes: ProbeResult[],
  metaBySha: Map<string, TrackMeta> = new Map(),
  enrichBySha: Map<string, TrackEnrichment> = new Map(),
  objects: Array<{ sha: string; size: number }> = [],
  artists: Array<{ name: string; artSha: string | null }> = [],
  linkMeta: Map<string, ReleaseLinkMeta> = new Map(),
  addedAtBySha: Map<string, string> = new Map()
): ManifestV3 {
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
      let title = p.tags.title?.trim() ?? "";
      if (title === "" && meta?.caption && meta.caption.trim() !== "") title = meta.caption.trim();
      if (title === "" && meta?.fileName) {
        title = meta.fileName.replace(/\.[^.]+$/, "").replace(/\s+/g, " ").trim();
        const dash = title.indexOf(" - ");
        const enrichArtist = enrich?.artist ?? null;
        if (dash > 0 && enrichArtist && norm(title.slice(0, dash)) === norm(enrichArtist)) {
          title = title.slice(dash + 3).trim();
        }
      }
      const artist = tagged
        ? p.tags.artist?.trim() ?? "unknown artist"
        : enrich?.artist ?? "unknown artist";
      const album = tagged
        ? p.tags.album?.trim() ?? "unknown album"
        : enrich?.album ?? "unknown album";
      const year = tagged ? p.tags.year ?? null : enrich?.year ?? null;
      const categoryRelease =
        enrich?.releaseId != null &&
        isCategoryRelease(enrich?.album ?? "");
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
        artSha: categoryRelease ? null : enrich?.artSha ?? null,
        releaseId: categoryRelease ? null : enrich?.releaseId ?? null,
        releaseIds: [
          ...new Set([
            ...(categoryRelease ? [] : enrich?.releaseId != null ? [enrich.releaseId] : []),
            ...(enrich?.membership ?? []).map((m) => m.id),
          ]),
        ],
        trackNumber: enrich?.trackNumber ?? null,
        discNumber: enrich?.discNumber ?? null,
        totalTracks: enrich?.totalTracks ?? null,
        addedAt: addedAtBySha.get(p.sha) ?? null,
      };
    })
    .sort((a: ManifestTrack, b: ManifestTrack) => (a.sha < b.sha ? -1 : a.sha > b.sha ? 1 : 0));

  const releaseMap = new Map<string, ManifestRelease>();
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
      artist: t.artist,
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
      enrich?.releaseId ??
      fallbackReleaseKey({ artist: t.artist, album: t.album, sha: t.sha });
    const primary = ensureRelease(t, enrich, key);
    if (primary.groupId == null) {
      const meta = linkMeta.get(key);
      if (meta?.groupId != null) primary.groupId = meta.groupId;
    }
    addTrackToRelease(primary, t.sha, enrich?.trackNumber ?? null, enrich?.discNumber ?? null);
    if (primary.artSha == null) primary.artSha = t.artSha;
    if (primary.totalTracks == null) {
      const meta = linkMeta.get(key);
      if (meta?.totalTracks != null) primary.totalTracks = meta.totalTracks;
    }
    for (const m of enrich?.membership ?? []) {
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
  let mergedAnything = true;
  while (mergedAnything) {
    mergedAnything = false;
    const ids = [...merged.keys()];
    for (const id of ids) {
      const r = merged.get(id);
      if (!r) continue;
      for (const [oid, other] of merged) {
        if (oid === id) continue;
        if (other.artist !== r.artist) continue;
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
        merged.delete(small.id);
        mergedAnything = true;
        break;
      }
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

  const integrityBody = JSON.stringify({ schema: 3, tracks, releases });
  const integrity = createHash("sha256").update(integrityBody).digest("hex").slice(0, 16);

  return {
    schema: 3,
    generatedAt: new Date().toISOString(),
    integrity,
    tracks,
    releases,
    artists: [...artists].sort((a, b) => a.name.localeCompare(b.name)),
  };
}