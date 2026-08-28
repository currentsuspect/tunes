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
}

function norm(s: string): string {
  return s.toLowerCase().replace(/\s+/g, " ").trim();
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
  enrichBySha: Map<string, TrackEnrichment> = new Map()
): ManifestV2 {
  const tracks: ManifestTrack[] = probes
    .map((p) => {
      const meta = metaBySha.get(p.sha);
      const enrich = enrichBySha.get(p.sha);
      const tagged = Boolean(p.tags.title) || Boolean(p.tags.artist) || Boolean(p.tags.album);
      let title = p.tags.title?.trim() ?? "";
      if (title === "" && meta?.caption && meta.caption.trim() !== "") title = meta.caption.trim();
      if (title === "" && meta?.fileName) {
        title = meta.fileName.replace(/\.[^.]+$/, "").trim();
      }
      const artist = tagged
        ? p.tags.artist?.trim() ?? "unknown artist"
        : enrich?.artist ?? "unknown artist";
      const album = tagged
        ? p.tags.album?.trim() ?? "unknown album"
        : enrich?.album ?? "unknown album";
      const year = tagged ? p.tags.year ?? null : enrich?.year ?? null;
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
        album,
        year,
        artSha: enrich?.artSha ?? null,
        releaseId: enrich?.releaseId ?? null,
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
  const releases = [...releaseMap.values()]
    .sort((a, b) =>
      a.artist !== b.artist ? a.artist.localeCompare(b.artist) : a.title.localeCompare(b.title)
    )
    .map((r) => ({ ...r, trackShas: [...r.trackShas].sort() }));

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