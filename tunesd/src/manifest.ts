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
}

export interface ManifestV1 {
  schema: 1;
  generatedAt: string;
  integrity: string;
  tracks: ManifestTrack[];
}

export interface TrackMeta {
  caption: string | null;
  fileName: string | null;
}

export function buildManifest(probes: ProbeResult[], metaBySha: Map<string, TrackMeta> = new Map()): ManifestV1 {
  const tracks: ManifestTrack[] = probes
    .map((p) => {
      const meta = metaBySha.get(p.sha);
      const tagged = Boolean(p.tags.title) || Boolean(p.tags.artist) || Boolean(p.tags.album);
      let title = p.tags.title?.trim() ?? "";
      if (title === "" && meta?.caption && meta.caption.trim() !== "") title = meta.caption.trim();
      if (title === "" && meta?.fileName) {
        title = meta.fileName.replace(/\.[^.]+$/, "").trim();
      }
      const artist = (tagged ? p.tags.artist?.trim() : undefined) ?? "unknown artist";
      const album = (tagged ? p.tags.album?.trim() : undefined) ?? "unknown album";
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
        year: p.tags.year ?? null,
      };
    })
    .sort((a: ManifestTrack, b: ManifestTrack) => (a.sha < b.sha ? -1 : a.sha > b.sha ? 1 : 0));

  const integrityBody = JSON.stringify({ schema: 1, tracks });
  const integrity = createHash("sha256").update(integrityBody).digest("hex").slice(0, 16);

  return {
    schema: 1,
    generatedAt: new Date().toISOString(),
    integrity,
    tracks,
  };
}