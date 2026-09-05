/**
 * Credit parsing: who made this, and who is along for the ride.
 *
 * Channel rips write the whole cast into the artist tag ("Yeat;Don Toliver",
 * "Yeat, Kodak Black") and sometimes into the title ("AWOL (feat. no one)").
 * Treating those strings as opaque means one album shows up under nine
 * different "artists" and shatters into nine releases, so the primary artist
 * has to be recoverable from the credit string.
 *
 * This never changes what a track *is* (SPEC §1.2 — identity is content, not
 * metadata); it only recovers structure the tagger flattened.
 */

export interface Credits {
  primary: string;
  featured: string[];
}

/** feat. / ft. / featuring / with / w/ , optionally wrapped in brackets. */
const FEATURE_MARKER = /[([\-–]?\s*\b(?:feat|feats|featuring|ft|w\/|with)\b\.?\s*/i;

/** Unambiguous multi-value separators in tag strings. */
const HARD_SEPARATORS = /[;/]|\s+&\s+|\s+\+\s+|\s+[xX]\s+/;

/**
 * A comma is a separator in "Yeat, Don Toliver" but part of the name in
 * "Tyler, The Creator". Treat it as a separator unless the next segment reads
 * like a continuation of the same name.
 */
const NAME_CONTINUATION = /^(the|a|an|and|jr|sr|ii|iii)\b/i;

function splitOnCommas(segment: string): string[] {
  const parts = segment.split(",");
  if (parts.length === 1) return [segment.trim()];
  const out: string[] = [];
  for (const part of parts) {
    const piece = part.trim();
    if (piece === "") continue;
    if (out.length > 0 && NAME_CONTINUATION.test(piece)) {
      out[out.length - 1] = `${out[out.length - 1]}, ${piece}`;
      continue;
    }
    out.push(piece);
  }
  return out;
}

function splitNames(raw: string): string[] {
  const names: string[] = [];
  for (const hard of raw.split(HARD_SEPARATORS)) {
    for (const name of splitOnCommas(hard)) {
      const trimmed = name.trim().replace(/[\s,;/&+]+$/, "").trim();
      if (trimmed !== "" && !names.some((n) => n.toLowerCase() === trimmed.toLowerCase())) {
        names.push(trimmed);
      }
    }
  }
  return names;
}

/**
 * Splits an artist credit into the act the release belongs to and everyone
 * guesting on it. The first name wins: taggers put the primary artist first.
 */
export function parseCredits(raw: string | null | undefined): Credits {
  if (raw == null || raw.trim() === "") return { primary: "", featured: [] };
  const marked = raw.split(FEATURE_MARKER);
  const head = marked[0] ?? raw;
  const tail = marked.slice(1).join(" ");

  const headNames = splitNames(head);
  const tailNames = tail.trim() === "" ? [] : splitNames(tail);

  if (headNames.length === 0) return { primary: raw.trim(), featured: [] };
  const primary = headNames[0]!;
  const featured: string[] = [];
  for (const name of [...headNames.slice(1), ...tailNames]) {
    const clean = name.replace(/[)\]]+$/, "").trim();
    if (
      clean !== "" &&
      clean.toLowerCase() !== primary.toLowerCase() &&
      !featured.some((f) => f.toLowerCase() === clean.toLowerCase())
    ) {
      featured.push(clean);
    }
  }
  return { primary, featured };
}

/**
 * Pulls a "(feat. X)" credit out of a track title. Only bracketed or
 * clearly-marked credits are taken — a title that merely contains the word
 * "with" keeps it, since "Dancing with Myself" is not a collaboration.
 */
export function stripFeatured(title: string | null | undefined): {
  title: string;
  featured: string[];
} {
  if (title == null || title.trim() === "") return { title: "", featured: [] };
  const bracketed =
    /\s*[([]\s*(?:feat|feats|featuring|ft|w\/|with)\b\.?\s*([^)\]]+)[)\]]\s*/i;
  let working = title;
  const featured: string[] = [];
  for (;;) {
    const match = bracketed.exec(working);
    if (!match) break;
    for (const name of splitNames(match[1] ?? "")) {
      if (!featured.some((f) => f.toLowerCase() === name.toLowerCase())) featured.push(name);
    }
    working = `${working.slice(0, match.index)} ${working.slice(match.index + match[0].length)}`;
  }
  const cleaned = working.replace(/\s{2,}/g, " ").trim();
  return { title: cleaned === "" ? title.trim() : cleaned, featured };
}

/**
 * The act a release belongs to. The album-artist tag is authoritative when the
 * tagger supplied one; otherwise fall back to the primary of the track credit,
 * which is stable across an album even when each track lists different guests.
 */
export function releaseArtistOf(
  albumArtist: string | null | undefined,
  trackArtist: string | null | undefined
): string {
  const tagged = albumArtist?.trim();
  if (tagged != null && tagged !== "") return parseCredits(tagged).primary || tagged;
  const primary = parseCredits(trackArtist).primary;
  return primary !== "" ? primary : (trackArtist ?? "").trim();
}
