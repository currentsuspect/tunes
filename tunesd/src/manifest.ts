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
  trackNumber: number | null;
  discNumber: number | null;
}

export interface ManifestRelease {
  id: string;
  title: string;
  artist: string;
  year: string | null;
  artSha: string | null;
  type: string | null;
  trackShas: string[];
}

export interface ManifestV2 {
  schema: 2;
  generatedAt: string;
  integrity: string;
  tracks: ManifestTrack[];
  releases: ManifestRelease[];
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
}

function norm(s: string): string {
  return s.toLowerCase().replace(/\s+/g, " ").trim();
}

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
  objects: Array<{ sha: string; size: number }> = []
): ManifestV2 {
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
        trackNumber: enrich?.trackNumber ?? null,
        discNumber: enrich?.discNumber ?? null,
      };
    })
    .sort((a: ManifestTrack, b: ManifestTrack) => (a.sha < b.sha ? -1 : a.sha > b.sha ? 1 : 0));

  const releaseMap = new Map<string, ManifestRelease>();
  for (const t of tracks) {
    const enrich = enrichBySha.get(t.sha);
    const key =
      enrich?.releaseId ??
      fallbackReleaseKey({ artist: t.artist, album: t.album, sha: t.sha });
    let release = releaseMap.get(key);
    if (!release) {
      release = {
        id: key,
        title: t.album,
        artist: t.artist,
        year: enrich?.year ?? t.year,
        artSha: t.artSha,
        type: enrich?.releaseType ?? null,
        trackShas: [],
      };
      releaseMap.set(key, release);
    }
    if (!release.trackShas.includes(t.sha)) release.trackShas.push(t.sha);
    if (release.artSha == null) release.artSha = t.artSha;
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
        if (small.trackShas.length > 8 && !bothUnknown) continue;
        if (!bothUnknown && !tokenSubset(small.title, big.title)) continue;
        for (const sha of small.trackShas) {
          if (!big.trackShas.includes(sha)) big.trackShas.push(sha);
        }
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
      const byNumber = new Map<string, number | null>();
      const discOf = new Map<string, number>();
      for (const t of tracks) {
        if (r.trackShas.includes(t.sha)) {
          byNumber.set(t.sha, t.trackNumber ?? null);
          if (t.discNumber != null) discOf.set(t.sha, t.discNumber);
        }
      }
      const ordered = [...r.trackShas].sort((a, b) => {
        const da = discOf.get(a) ?? 1;
        const db = discOf.get(b) ?? 1;
        if (da !== db) return da - db;
        const na = byNumber.get(a) ?? 999;
        const nb = byNumber.get(b) ?? 999;
        if (na !== nb) return na - nb;
        return a < b ? -1 : a > b ? 1 : 0;
      });
      return { ...r, trackShas: ordered };
    });

  const integrityBody = JSON.stringify({ schema: 2, tracks, releases });
  const integrity = createHash("sha256").update(integrityBody).digest("hex").slice(0, 16);

  return {
    schema: 2,
    generatedAt: new Date().toISOString(),
    integrity,
    tracks,
    releases,
  };
}