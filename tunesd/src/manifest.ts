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

export function buildManifest(probes: ProbeResult[]): ManifestV1 {
  const tracks: ManifestTrack[] = probes
    .map((p) => ({
      sha: p.sha,
      size: p.size,
      codec: p.codec,
      sampleRate: p.sampleRate,
      channels: p.channels,
      bitrate: p.bitrate,
      durationMs: p.durationMs,
      title: p.tags.title ?? "untitled",
      artist: p.tags.artist ?? "unknown artist",
      album: p.tags.album ?? "unknown album",
      year: p.tags.year ?? null,
    }))
    .sort((a, b) => (a.sha < b.sha ? -1 : a.sha > b.sha ? 1 : 0));

  const integrityBody = JSON.stringify({ schema: 1, tracks });
  const integrity = createHash("sha256").update(integrityBody).digest("hex").slice(0, 16);

  return {
    schema: 1,
    generatedAt: new Date().toISOString(),
    integrity,
    tracks,
  };
}