import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileP = promisify(execFile);

export interface ProbeResult {
  sha: string;
  size: number;
  codec: string | null;
  sampleRate: number | null;
  channels: number | null;
  bitrate: number | null;
  durationMs: number | null;
  tags: { title?: string; artist?: string; album?: string; year?: string };
  probedAt: string;
}

interface FfprobeOutput {
  format?: {
    duration?: string;
    bit_rate?: string;
    tags?: Record<string, string>;
  };
  streams?: Array<{
    codec_name?: string;
    sample_rate?: string;
    channels?: number;
    bit_rate?: string;
    duration?: string;
    tags?: Record<string, string>;
  }>;
}

export async function probeFile(sha: string, size: number, path: string): Promise<ProbeResult> {
  const { stdout } = await execFileP(
    "ffprobe",
    ["-v", "error", "-print_format", "json", "-show_format", "-show_streams", path],
    { timeout: 30_000, maxBuffer: 4 * 1024 * 1024 }
  );
  const raw = JSON.parse(stdout) as FfprobeOutput;
  const audio = (raw.streams ?? []).find((s) => s.codec_name !== null) ?? raw.streams?.[0];
  const format = raw.format ?? {};

  let bitrate = audio?.bit_rate ? Number(audio.bit_rate) : null;
  if (!bitrate || !Number.isFinite(bitrate)) {
    const fb = format.bit_rate ? Number(format.bit_rate) : null;
    bitrate = fb && Number.isFinite(fb) ? fb : null;
  }
  const durRaw = audio?.duration ?? format.duration ?? null;
  const durationMs = durRaw ? Math.round(Number(durRaw) * 1000) : null;

  const tags = { ...(format.tags ?? {}), ...(audio?.tags ?? {}) };
  const pick = (k: string): string | undefined => {
    const v = tags[k] ?? tags[k.toLowerCase()];
    return v != null && String(v).trim() !== "" ? String(v).trim() : undefined;
  };

  return {
    sha,
    size,
    codec: audio?.codec_name ?? null,
    sampleRate: audio?.sample_rate ? Number(audio.sample_rate) : null,
    channels: audio?.channels ?? null,
    bitrate,
    durationMs,
    tags: {
      title: pick("title"),
      artist: pick("artist"),
      album: pick("album"),
      year: pick("date"),
    },
    probedAt: new Date().toISOString(),
  };
}