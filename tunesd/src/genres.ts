/**
 * Clean genres from messy artist tags.
 *
 * Last.fm/Deezer tags arrive as the crowd typed them: "hip hop", "Hip-Hop",
 * "rap" and "trap" for one family; "atlanta", "female vocalists" and artist
 * names mixed in. The app's genre mixes took the two biggest raw tags, which
 * in a library that is mostly hip-hop were two spellings of the same thing,
 * every week (owner, 17 Oct: the genre mixes are stuck in one genre).
 *
 * Here every tag is folded to a known genre with a family, or dropped. The
 * map is small on purpose: genres a listener would recognise as different
 * moods, not a taxonomy for its own sake. Pure and deterministic.
 */

export interface Genre {
  /** Display name: "Rage", "Neo Soul". */
  name: string;
  /** The family it belongs to: "Hip-Hop", "R&B & Soul". */
  family: string;
  /** 0..1: how strongly the artist's tags say it (earlier tags count more). */
  weight: number;
}

type Entry = [family: string, name: string];

const HIP = "Hip-Hop";
const RNB = "R&B & Soul";
const POP = "Pop";
const ELEC = "Electronic";
const REG = "Reggae & Dancehall";
const AFR = "African";
const ROCK = "Rock & Metal";
const JAZZ = "Jazz";
const CHILL = "Ambient & Chill";

/** Folded tag -> [family, genre]. Family-level tags map to the family's
 * own broad genre (named like the family), which a more specific tag of the
 * same artist outranks. */
const MAP: Record<string, Entry> = {
  // Hip-Hop and its rooms
  "hip hop": [HIP, "Hip-Hop"],
  rap: [HIP, "Hip-Hop"],
  "hip hop rap": [HIP, "Hip-Hop"],
  trap: [HIP, "Trap"],
  "southern rap": [HIP, "Trap"],
  "dirty south": [HIP, "Trap"],
  rage: [HIP, "Rage"],
  plugg: [HIP, "Plugg"],
  pluggnb: [HIP, "Plugg"],
  "dark plugg": [HIP, "Plugg"],
  "dream plugg": [HIP, "Plugg"],
  "cloud rap": [HIP, "Cloud Rap"],
  "underground rap": [HIP, "Underground"],
  "underground hip hop": [HIP, "Underground"],
  "experimental rap": [HIP, "Underground"],
  "experimental hip hop": [HIP, "Underground"],
  sigilkore: [HIP, "Underground"],
  "new jazz": [HIP, "New Jazz"],
  drill: [HIP, "Drill"],
  "uk drill": [HIP, "Drill"],
  "west coast": [HIP, "West Coast"],
  "west coast rap": [HIP, "West Coast"],
  "g funk": [HIP, "West Coast"],
  "boom bap": [HIP, "Boom Bap"],
  "east coast": [HIP, "Boom Bap"],
  "conscious hip hop": [HIP, "Boom Bap"],
  "uk hip hop": [HIP, "UK Rap"],
  grime: [HIP, "UK Rap"],
  // R&B & Soul
  rnb: [RNB, "R&B"],
  "r b": [RNB, "R&B"],
  "contemporary r b": [RNB, "R&B"],
  "alternative rnb": [RNB, "Alternative R&B"],
  "alternative r b": [RNB, "Alternative R&B"],
  "neo soul": [RNB, "Neo Soul"],
  soul: [RNB, "Soul"],
  funk: [RNB, "Soul"],
  // Pop
  pop: [POP, "Pop"],
  "indie pop": [POP, "Indie Pop"],
  "art pop": [POP, "Art Pop"],
  hyperpop: [POP, "Hyperpop"],
  digicore: [POP, "Hyperpop"],
  synthpop: [POP, "Synthpop"],
  // Electronic
  electronic: [ELEC, "Electronic"],
  electronica: [ELEC, "Electronic"],
  electro: [ELEC, "Electronic"],
  dubstep: [ELEC, "Dubstep"],
  idm: [ELEC, "IDM"],
  breakcore: [ELEC, "Breakcore"],
  house: [ELEC, "House"],
  techno: [ELEC, "Techno"],
  "drum and bass": [ELEC, "Drum & Bass"],
  indietronica: [ELEC, "Electronic"],
  // Reggae & Dancehall
  reggae: [REG, "Reggae"],
  "roots reggae": [REG, "Roots Reggae"],
  roots: [REG, "Roots Reggae"],
  dancehall: [REG, "Dancehall"],
  dub: [REG, "Dub"],
  ska: [REG, "Ska"],
  // African
  afrobeats: [AFR, "Afrobeats"],
  afrobeat: [AFR, "Afrobeats"],
  afropop: [AFR, "Afrobeats"],
  amapiano: [AFR, "Amapiano"],
  "bongo flava": [AFR, "Bongo Flava"],
  gengetone: [AFR, "Gengetone"],
  // Rock & Metal
  rock: [ROCK, "Rock"],
  "stoner rock": [ROCK, "Stoner Rock"],
  "desert rock": [ROCK, "Stoner Rock"],
  "post punk": [ROCK, "Post-Punk"],
  punk: [ROCK, "Punk"],
  "alternative rock": [ROCK, "Alternative Rock"],
  "indie rock": [ROCK, "Alternative Rock"],
  metal: [ROCK, "Metal"],
  "death metal": [ROCK, "Metal"],
  "alternative metal": [ROCK, "Metal"],
  "nu metal": [ROCK, "Metal"],
  "post metal": [ROCK, "Metal"],
  "hard rock": [ROCK, "Rock"],
  // Jazz
  jazz: [JAZZ, "Jazz"],
  "jazz rap": [JAZZ, "Jazz"],
  // Ambient & Chill
  ambient: [CHILL, "Ambient"],
  chillout: [CHILL, "Chill"],
  "lo fi": [CHILL, "Lo-Fi"],
  lofi: [CHILL, "Lo-Fi"],
};

/** Where a place-only tag points, when it is the strongest signal left. */
const PLACE: Record<string, Entry> = {
  nigeria: [AFR, "Afrobeats"],
  nigerian: [AFR, "Afrobeats"],
  ghana: [AFR, "Afrobeats"],
  kenya: [AFR, "Kenyan"],
  kenyan: [AFR, "Kenyan"],
  jamaican: [REG, "Reggae"],
};

export function foldTag(tag: string): string {
  return tag
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/&/g, " ")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

/**
 * An artist's genres, strongest first, from their tags in the order the
 * provider gave them (most-used first). A broad family genre counts for
 * less than a specific one, so "hip hop, rap, rage" reads as Rage first,
 * Hip-Hop second. Unknown tags (places that say nothing, descriptors,
 * names) are dropped. At most [limit] genres.
 */
export function genresFromTags(tags: readonly string[], limit = 3): Genre[] {
  const score = new Map<string, { family: string; name: string; w: number }>();
  const add = (e: Entry, w: number, broad: boolean) => {
    const key = `${e[0]}|${e[1]}`;
    const prev = score.get(key)?.w ?? 0;
    // Spellings of a broad genre ("hip hop", "rap") say one thing, once:
    // they never add up past a specific room the artist is also tagged with.
    score.set(key, { family: e[0], name: e[1], w: broad ? Math.max(prev, w) : prev + w });
  };
  tags.slice(0, 8).forEach((raw, i) => {
    const t = foldTag(raw);
    const e = MAP[t];
    const position = 1 / (1 + i * 0.5);
    if (e) {
      const broad = e[1] === e[0] || (e[0] === HIP && e[1] === "Hip-Hop");
      add(e, broad ? position * 0.4 : position, broad);
    }
  });
  if (score.size === 0) {
    for (const raw of tags.slice(0, 5)) {
      const e = PLACE[foldTag(raw)];
      if (e) {
        add(e, 0.5, false);
        break;
      }
    }
  }
  const out = [...score.values()].sort(
    (a, b) => b.w - a.w || a.name.localeCompare(b.name)
  );
  const top = out[0]?.w ?? 1;
  return out.slice(0, limit).map((g) => ({
    name: g.name,
    family: g.family,
    weight: Math.round((g.w / top) * 100) / 100,
  }));
}
