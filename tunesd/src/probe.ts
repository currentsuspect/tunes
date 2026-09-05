import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileP = promisify(execFile);

/**
 * Bump whenever probing extracts something new or differently, so persisted
 * results from an older reader are discarded instead of masking the change.
 * v2: case-insensitive tags, aliases, track/disc numbering, embedded art.
 */
export const PROBE_VERSION = 2;

export interface ProbeTags {
  title?: string;
  artist?: string;
  album?: string;
  year?: string;
  albumArtist?: string;
  genre?: string;
  trackNumber?: number;
  discNumber?: number;
  totalTracks?: number;
}

export interface ProbeResult {
  sha: string;
  size: number;
  codec: string | null;
  sampleRate: number | null;
  channels: number | null;
  bitrate: number | null;
  durationMs: number | null;
  tags: ProbeTags;
  /** The file carries its own cover art (FLAC PICTURE / ID3 APIC). */
  hasEmbeddedArt: boolean;
  probedAt: string;
}

interface FfprobeStream {
  codec_name?: string;
  codec_type?: string;
  sample_rate?: string;
  channels?: number;
  bit_rate?: string;
  duration?: string;
  disposition?: Record<string, number>;
  tags?: Record<string, string>;
}

interface FfprobeOutput {
  format?: {
    duration?: string;
    bit_rate?: string;
    tags?: Record<string, string>;
  };
  streams?: FfprobeStream[];
}

/**
 * Tag keys are not case-stable: FLAC Vorbis comments come back as ALBUM/TITLE,
 * ID3 frames as album/title, and a single file routinely mixes the two
 * (TITLE + track + GENRE). Fold to lower case once, then look names up there —
 * a reader that only tries the literal key and its lower case silently loses
 * every uppercase-tagged file.
 */
export function foldTags(...sources: Array<Record<string, string> | undefined>): Map<string, string> {
  const folded = new Map<string, string>();
  for (const source of sources) {
    for (const [key, value] of Object.entries(source ?? {})) {
      if (value == null) continue;
      const text = String(value).trim();
      if (text === "") continue;
      const name = key.toLowerCase();
      if (!folded.has(name)) folded.set(name, text);
    }
  }
  return folded;
}

/** First non-empty value among the given aliases. */
function firstOf(folded: Map<string, string>, ...names: string[]): string | undefined {
  for (const name of names) {
    const value = folded.get(name);
    if (value != null && value !== "") return value;
  }
  return undefined;
}

/** Parses "7" and the "7/12" form taggers still emit. */
export function parseIndex(raw: string | undefined): { index: number | null; total: number | null } {
  if (raw == null) return { index: null, total: null };
  const match = /^\s*(\d+)\s*(?:\/\s*(\d+))?\s*$/.exec(raw);
  if (!match) return { index: null, total: null };
  const index = Number(match[1]);
  const total = match[2] != null ? Number(match[2]) : null;
  return {
    index: Number.isFinite(index) && index > 0 ? index : null,
    total: total != null && Number.isFinite(total) && total > 0 ? total : null,
  };
}

export function tagsFromFfprobe(raw: FfprobeOutput): ProbeTags {
  const streamTags = (raw.streams ?? [])
    .filter((s) => s.codec_type === "audio")
    .map((s) => s.tags);
  const folded = foldTags(raw.format?.tags, ...streamTags);

  const track = parseIndex(firstOf(folded, "track", "tracknumber"));
  const disc = parseIndex(firstOf(folded, "disc", "discnumber"));
  const totalTracks =
    parseIndex(firstOf(folded, "tracktotal", "totaltracks")).index ?? track.total;

  const tags: ProbeTags = {};
  const title = firstOf(folded, "title");
  if (title != null) tags.title = title;
  // ARTISTS (plural) and main_artist are common in channel rips.
  const artist = firstOf(folded, "artist", "artists", "main_artist");
  if (artist != null) tags.artist = artist;
  const album = firstOf(folded, "album");
  if (album != null) tags.album = album;
  const year = firstOf(folded, "date", "year", "originaldate", "originalyear");
  if (year != null) tags.year = year;
  const albumArtist = firstOf(folded, "albumartist", "album_artist", "main_artist");
  if (albumArtist != null) tags.albumArtist = albumArtist;
  const genre = firstOf(folded, "genre");
  if (genre != null) tags.genre = genre;
  if (track.index != null) tags.trackNumber = track.index;
  if (disc.index != null) tags.discNumber = disc.index;
  if (totalTracks != null) tags.totalTracks = totalTracks;
  return tags;
}

export function hasAttachedPicture(raw: FfprobeOutput): boolean {
  return (raw.streams ?? []).some(
    (s) => s.disposition?.["attached_pic"] === 1 || s.codec_type === "video"
  );
}

export async function probeFile(sha: string, size: number, path: string): Promise<ProbeResult> {
  const { stdout } = await execFileP(
    "ffprobe",
    ["-v", "error", "-print_format", "json", "-show_format", "-show_streams", path],
    { timeout: 30_000, maxBuffer: 4 * 1024 * 1024 }
  );
  const raw = JSON.parse(stdout) as FfprobeOutput;
  // Cover art rides along as a video stream, so "the first stream" is not
  // reliably the audio one — ask for the audio stream by type.
  const audio =
    (raw.streams ?? []).find((s) => s.codec_type === "audio") ?? raw.streams?.[0];
  const format = raw.format ?? {};

  let bitrate = audio?.bit_rate ? Number(audio.bit_rate) : null;
  if (!bitrate || !Number.isFinite(bitrate)) {
    const fb = format.bit_rate ? Number(format.bit_rate) : null;
    bitrate = fb && Number.isFinite(fb) ? fb : null;
  }
  const durRaw = audio?.duration ?? format.duration ?? null;
  const durationMs = durRaw ? Math.round(Number(durRaw) * 1000) : null;

  return {
    sha,
    size,
    codec: audio?.codec_name ?? null,
    sampleRate: audio?.sample_rate ? Number(audio.sample_rate) : null,
    channels: audio?.channels ?? null,
    bitrate,
    durationMs,
    tags: tagsFromFfprobe(raw),
    hasEmbeddedArt: hasAttachedPicture(raw),
    probedAt: new Date().toISOString(),
  };
}

/**
 * Copies the cover art out of the file. Never re-encodes (AGENTS.md: the
 * pipeline probes, it does not transcode) — the picture is stream-copied
 * exactly as the tagger embedded it.
 */
export async function extractEmbeddedArt(path: string): Promise<Uint8Array | null> {
  try {
    const { stdout } = await execFileP(
      "ffmpeg",
      ["-v", "error", "-i", path, "-map", "0:v:0", "-c", "copy", "-f", "image2pipe", "-"],
      { timeout: 30_000, maxBuffer: 32 * 1024 * 1024, encoding: "buffer" }
    );
    const bytes = new Uint8Array(stdout);
    return bytes.length > 1000 ? bytes : null;
  } catch {
    return null;
  }
}
