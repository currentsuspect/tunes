/**
 * What Genius knows about the music: a song's story and who made it, an
 * album's and an artist's write-up (the Roon pass, approved 24 Oct).
 *
 * Genius's own web API (the one its pages use) answers without a token, as
 * the lyrics already rely on (lyricsources.ts). Asked politely: one song at a
 * time in the background, and on demand when a page is opened for something
 * not yet asked about. Everything is kept on disk (about.json), so a page
 * opens from the box, not from Genius.
 */
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import { sameSong, type Ours } from "./lyricsources.js";

const UA =
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36";

/** Long write-ups are cut here; the page offers Read more on Genius. */
const kMaxDescription = 2400;

export class GeniusUnavailable extends Error {}

export interface Named {
  id: number;
  name: string;
}

export interface Credit {
  /** Genius's own words: "Mixing Engineer", "Label", "Additional Vocals". */
  role: string;
  names: string[];
}

export interface Connection {
  /** samples, sampled_in, interpolates, interpolated_by, covers, ... */
  type: string;
  songs: Array<{ title: string; artist: string }>;
}

export interface SongAbout {
  geniusId: number;
  url: string;
  description: string | null;
  releaseDate: string | null;
  producers: string[];
  writers: string[];
  featured: string[];
  credits: Credit[];
  connections: Connection[];
  album: Named | null;
  artist: Named | null;
  fetchedAt: string;
}

export interface AlbumAbout {
  geniusId: number;
  url: string;
  name: string;
  description: string | null;
  releaseDate: string | null;
  credits: Credit[];
  fetchedAt: string;
}

export interface ArtistAbout {
  geniusId: number;
  url: string;
  name: string;
  description: string | null;
  alternateNames: string[];
  imageUrl: string | null;
  fetchedAt: string;
}

type Raw = Record<string, unknown>;

const str = (v: unknown): string | null => (typeof v === "string" && v.trim() !== "" ? v : null);
const names = (v: unknown): string[] =>
  Array.isArray(v) ? v.map((a) => str((a as Raw)["name"])).filter((n): n is string => n != null) : [];
const named = (v: unknown): Named | null => {
  const o = v as Raw | null;
  if (!o || typeof o["id"] !== "number" || str(o["name"]) == null) return null;
  return { id: o["id"] as number, name: o["name"] as string };
};
const plain = (v: unknown): string | null => {
  const t = str((v as Raw | null)?.["plain"]) ?? str(v);
  if (t == null || t === "?") return null;
  return t.length > kMaxDescription ? `${t.slice(0, kMaxDescription).trimEnd()}…` : t.trim();
};
const credits = (v: unknown): Credit[] =>
  Array.isArray(v)
    ? v
        .map((p) => ({ role: str((p as Raw)["label"]) ?? "", names: names((p as Raw)["artists"]) }))
        .filter((c) => c.role !== "" && c.names.length > 0)
    : [];

/** The parts of a Genius song a page shows. Exported for tests. */
export function songAboutFrom(s: Raw): SongAbout {
  const connections: Connection[] = [];
  for (const r of Array.isArray(s["song_relationships"]) ? s["song_relationships"] : []) {
    const rel = r as Raw;
    const type = str(rel["relationship_type"]);
    // Translations are not music.
    if (type == null || type === "translations" || type === "translation_of") continue;
    const songs = (Array.isArray(rel["songs"]) ? rel["songs"] : [])
      .map((x) => ({
        title: str((x as Raw)["title"]) ?? "",
        artist: str(((x as Raw)["primary_artist"] as Raw | undefined)?.["name"]) ?? "",
      }))
      .filter((x) => x.title !== "");
    if (songs.length > 0) connections.push({ type, songs });
  }
  return {
    geniusId: s["id"] as number,
    url: str(s["url"]) ?? "",
    description: plain(s["description"]),
    releaseDate: str(s["release_date"]),
    producers: names(s["producer_artists"]),
    writers: names(s["writer_artists"]),
    featured: names(s["featured_artists"]),
    credits: credits(s["custom_performances"]),
    connections,
    album: named(s["album"]),
    artist: named(s["primary_artist"]),
    fetchedAt: new Date().toISOString(),
  };
}

export class GeniusAboutClient {
  constructor(private readonly fetcher: typeof fetch = fetch) {}

  private async get(path: string): Promise<Raw | null> {
    let res: Response;
    try {
      res = await this.fetcher(`https://genius.com/api${path}`, {
        headers: { "User-Agent": UA, Accept: "application/json" },
        signal: AbortSignal.timeout(20_000),
      });
    } catch (e) {
      throw new GeniusUnavailable(String(e));
    }
    if (res.status === 404) return null;
    if (!res.ok) throw new GeniusUnavailable(`genius ${res.status}`);
    try {
      return ((await res.json()) as { response?: Raw }).response ?? null;
    } catch (e) {
      throw new GeniusUnavailable(String(e));
    }
  }

  /** The Genius song for ours, or null when none is a match. */
  async song(ours: Ours): Promise<SongAbout | null> {
    const q = `${ours.artist.split(/,|;|\//)[0]?.trim() ?? ours.artist} ${ours.title.replace(/\(.*?\)|\[.*?\]/g, " ")}`;
    const search = await this.get(`/search/song?per_page=5&q=${encodeURIComponent(q.trim())}`);
    const hits = ((search?.["sections"] as Raw[] | undefined) ?? [])
      .flatMap((s) => (s["hits"] as Raw[] | undefined) ?? [])
      .map((h) => h["result"] as Raw);
    const hit = hits.find((r) =>
      sameSong(
        {
          title: str(r["title"]) ?? "",
          artists: [str((r["primary_artist"] as Raw | undefined)?.["name"]) ?? ""],
          durationMs: null,
        },
        ours,
      ),
    );
    if (!hit || typeof hit["id"] !== "number") return null;
    const got = await this.get(`/songs/${hit["id"]}?text_format=plain`);
    const s = got?.["song"] as Raw | undefined;
    return s ? songAboutFrom(s) : null;
  }

  async album(id: number): Promise<AlbumAbout | null> {
    const a = (await this.get(`/albums/${id}?text_format=plain`))?.["album"] as Raw | undefined;
    if (!a) return null;
    return {
      geniusId: id,
      url: str(a["url"]) ?? "",
      name: str(a["name"]) ?? "",
      description: plain(a["description_preview"]),
      releaseDate: str(a["release_date"]),
      credits: credits(a["song_performances"]),
      fetchedAt: new Date().toISOString(),
    };
  }

  async artist(id: number): Promise<ArtistAbout | null> {
    const a = (await this.get(`/artists/${id}?text_format=plain`))?.["artist"] as Raw | undefined;
    if (!a) return null;
    return {
      geniusId: id,
      url: str(a["url"]) ?? "",
      name: str(a["name"]) ?? "",
      description: plain(a["description"]),
      alternateNames: Array.isArray(a["alternate_names"])
        ? (a["alternate_names"] as unknown[]).filter((n): n is string => typeof n === "string")
        : [],
      imageUrl: str(a["image_url"]),
      fetchedAt: new Date().toISOString(),
    };
  }
}

/** A song Genius had nothing for: asked again after this long. */
export const kRetryMissAfterMs = 30 * 24 * 3600_000;

interface AboutFile {
  songs: Record<string, SongAbout | { missedAt: string }>;
  albums: Record<string, AlbumAbout>;
  artists: Record<string, ArtistAbout>;
}

/** Everything asked of Genius, kept on disk. */
export class AboutStore {
  private data: AboutFile = { songs: {}, albums: {}, artists: {} };

  constructor(private readonly file: string) {}

  async load(): Promise<this> {
    try {
      const raw = JSON.parse(await readFile(this.file, "utf8")) as Partial<AboutFile>;
      this.data = { songs: raw.songs ?? {}, albums: raw.albums ?? {}, artists: raw.artists ?? {} };
    } catch {
      // None yet.
    }
    return this;
  }

  private async save(): Promise<void> {
    await mkdir(dirname(this.file), { recursive: true });
    const tmp = `${this.file}.${process.pid}.tmp`;
    await writeFile(tmp, JSON.stringify(this.data));
    await rename(tmp, this.file);
  }

  song(sha: string): SongAbout | null {
    const s = this.data.songs[sha];
    return s && "geniusId" in s ? s : null;
  }

  /** Not asked yet, or a miss old enough to ask again. */
  songDue(sha: string): boolean {
    const s = this.data.songs[sha];
    if (!s) return true;
    return "missedAt" in s && Date.now() - Date.parse(s.missedAt) > kRetryMissAfterMs;
  }

  album(id: number): AlbumAbout | null {
    return this.data.albums[String(id)] ?? null;
  }

  artist(id: number): ArtistAbout | null {
    return this.data.artists[String(id)] ?? null;
  }

  /** Every song's credits, for a person's page and an artist's people. */
  allSongs(): Array<[string, SongAbout]> {
    return Object.entries(this.data.songs).filter((e): e is [string, SongAbout] => "geniusId" in e[1]);
  }

  async setSong(sha: string, about: SongAbout | null): Promise<void> {
    this.data.songs[sha] = about ?? { missedAt: new Date().toISOString() };
    await this.save();
  }

  async setAlbum(a: AlbumAbout): Promise<void> {
    this.data.albums[String(a.geniusId)] = a;
    await this.save();
  }

  async setArtist(a: ArtistAbout): Promise<void> {
    this.data.artists[String(a.geniusId)] = a;
    await this.save();
  }
}

const fold = (s: string) =>
  s
    .toLowerCase()
    .normalize("NFKD")
    .replace(/\(producer\)|®/g, "")
    .replace(/[^a-z0-9]+/g, "");

/** Whether a Genius credit is this person ("Bangs (Producer)" is Bangs). */
export function sameCredit(a: string, b: string): boolean {
  const x = fold(a);
  return x !== "" && x === fold(b);
}

export type Role = "produced" | "written" | "featured";

/** The songs a person worked on, and how, from the credits kept. */
export function workOf(
  person: string,
  songs: Array<[string, SongAbout]>,
): Array<{ sha: string; roles: Role[] }> {
  const out: Array<{ sha: string; roles: Role[] }> = [];
  for (const [sha, s] of songs) {
    const roles: Role[] = [];
    if (s.producers.some((n) => sameCredit(n, person))) roles.push("produced");
    if (s.writers.some((n) => sameCredit(n, person))) roles.push("written");
    if (s.featured.some((n) => sameCredit(n, person))) roles.push("featured");
    if (roles.length > 0) out.push({ sha, roles });
  }
  return out;
}

/**
 * The people around an artist: everyone credited on their songs, by how
 * many songs, the artist themself left out. [mine] is the artist's songs.
 */
export function peopleAround(
  artist: string,
  mine: SongAbout[],
): Array<{ name: string; songs: number; roles: Role[] }> {
  const by = new Map<string, { name: string; songs: Set<number>; roles: Set<Role> }>();
  const add = (name: string, song: number, role: Role) => {
    if (sameCredit(name, artist)) return;
    const k = fold(name);
    const e = by.get(k) ?? { name: name.replace(/\s*\(Producer\)$/, ""), songs: new Set(), roles: new Set() };
    e.songs.add(song);
    e.roles.add(role);
    by.set(k, e);
  };
  for (const s of mine) {
    for (const n of s.producers) add(n, s.geniusId, "produced");
    for (const n of s.featured) add(n, s.geniusId, "featured");
  }
  return [...by.values()]
    .map((e) => ({ name: e.name, songs: e.songs.size, roles: [...e.roles] }))
    .sort((a, b) => b.songs - a.songs || a.name.localeCompare(b.name));
}
