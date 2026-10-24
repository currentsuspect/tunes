/**
 * The Roon pass's pages, answered from what Genius said (genius.ts): a song's
 * story and makers, an album's and an artist's write-up, the people around an
 * artist, and a person's work in the library.
 *
 * Kept small for the phone: a page asks for its one thing and gets it from
 * disk; only something not yet asked about goes to Genius, once, while the
 * page waits a few seconds at most.
 */
import {
  AboutStore,
  GeniusAboutClient,
  GeniusUnavailable,
  peopleAround,
  sameCredit,
  workOf,
  type AlbumAbout,
  type ArtistAbout,
  type Role,
  type SongAbout,
} from "./genius.js";
import type { Log } from "./logger.js";

/** What the service needs of a library song. */
export interface AboutTrack {
  sha: string;
  title: string;
  artist: string;
  primaryArtist?: string | null;
  album: string;
  releaseId: string | null;
  durationMs: number | null;
}

/** How long a page waits on Genius for something not yet asked about. */
const kOnDemandMs = 8_000;

export class AboutService {
  /** Per song, the ask in flight, so a page and the pass never ask twice. */
  private inFlight = new Map<string, Promise<SongAbout | null>>();
  private reported = false;

  constructor(
    private readonly store: AboutStore,
    private readonly client: GeniusAboutClient,
    private readonly tracks: () => AboutTrack[],
    private readonly log: Log,
  ) {}

  private within<T>(p: Promise<T>, fallback: T): Promise<T> {
    return Promise.race([
      p,
      new Promise<T>((resolve) => setTimeout(() => resolve(fallback), kOnDemandMs).unref()),
    ]);
  }

  /** Genius's song for a library song: kept, else asked now. */
  private fetchSong(t: AboutTrack): Promise<SongAbout | null> {
    const kept = this.store.song(t.sha);
    if (kept || !this.store.songDue(t.sha)) return Promise.resolve(kept);
    const flying = this.inFlight.get(t.sha);
    if (flying) return flying;
    const p = (async () => {
      try {
        const s = await this.client.song({
          title: t.title,
          artist: t.primaryArtist || t.artist,
          album: t.album,
          durationMs: t.durationMs,
        });
        await this.store.setSong(t.sha, s);
        return s;
      } catch (e) {
        if (!(e instanceof GeniusUnavailable)) throw e;
        if (!this.reported) {
          this.log.warn({ event: "GENIUS_UNAVAILABLE", err: String(e).slice(0, 160) });
          this.reported = true;
        }
        return null;
      } finally {
        this.inFlight.delete(t.sha);
      }
    })();
    this.inFlight.set(t.sha, p);
    return p;
  }

  private async fetchAlbum(id: number): Promise<AlbumAbout | null> {
    const kept = this.store.album(id);
    if (kept) return kept;
    try {
      const a = await this.client.album(id);
      if (a) await this.store.setAlbum(a);
      return a;
    } catch (e) {
      if (e instanceof GeniusUnavailable) return null;
      throw e;
    }
  }

  private async fetchArtist(id: number): Promise<ArtistAbout | null> {
    const kept = this.store.artist(id);
    if (kept) return kept;
    try {
      const a = await this.client.artist(id);
      if (a) await this.store.setArtist(a);
      return a;
    } catch (e) {
      if (e instanceof GeniusUnavailable) return null;
      throw e;
    }
  }

  /** GET /about/song?sha= */
  async song(sha: string): Promise<{ song: SongAbout | null; album: AlbumAbout | null } | null> {
    const t = this.tracks().find((x) => x.sha === sha);
    if (!t) return null;
    const song = await this.within(this.fetchSong(t), this.store.song(sha));
    const album = song?.album ? await this.within(this.fetchAlbum(song.album.id), null) : null;
    return { song, album };
  }

  private songsBy(name: string): AboutTrack[] {
    return this.tracks().filter((t) => sameCredit(t.primaryArtist || t.artist, name));
  }

  /** GET /about/artist?name= : the write-up and the people around them. */
  async artist(name: string): Promise<{
    artist: ArtistAbout | null;
    people: Array<{ name: string; songs: number; roles: Role[] }>;
  }> {
    const theirs = this.songsBy(name);
    const known = theirs.map((t) => this.store.song(t.sha)).filter((s): s is SongAbout => s != null);
    // Nothing asked about them yet: ask about a few songs now, so the page
    // has a write-up the first time it opens.
    if (known.length === 0) {
      for (const t of theirs.slice(0, 2)) {
        const s = await this.within(this.fetchSong(t), null);
        if (s) known.push(s);
      }
    }
    const id = known.find((s) => s.artist && sameCredit(s.artist.name, name))?.artist?.id;
    const artist = id != null ? await this.within(this.fetchArtist(id), null) : null;
    return { artist, people: peopleAround(name, known).slice(0, 12) };
  }

  /** GET /about/album?release= : the album's write-up. */
  async album(releaseId: string): Promise<{ album: AlbumAbout | null }> {
    const songs = this.tracks().filter((t) => t.releaseId === releaseId);
    let id: number | undefined;
    for (const t of songs) {
      id = this.store.song(t.sha)?.album?.id;
      if (id != null) break;
    }
    if (id == null && songs[0]) {
      id = (await this.within(this.fetchSong(songs[0]), null))?.album?.id;
    }
    return { album: id != null ? await this.within(this.fetchAlbum(id), null) : null };
  }

  /** GET /about/person?name= : what they made in the library. */
  person(name: string): { work: Array<{ sha: string; roles: Role[] }> } {
    const held = new Set(this.tracks().map((t) => t.sha));
    return { work: workOf(name, this.store.allSongs()).filter((w) => held.has(w.sha)) };
  }

  /**
   * The background pass: [limit] songs not yet asked about, one at a time,
   * a pause between each so Genius is asked at a walk. Returns how many were
   * asked and how many Genius knew.
   */
  async pass(limit: number, pauseMs = 3_000): Promise<{ asked: number; found: number }> {
    let asked = 0;
    let found = 0;
    for (const t of this.tracks()) {
      if (asked >= limit) break;
      if (!this.store.songDue(t.sha)) continue;
      asked++;
      const s = await this.fetchSong(t);
      if (s) {
        found++;
        if (s.album) await this.fetchAlbum(s.album.id);
        if (s.artist) await this.fetchArtist(s.artist.id);
      }
      await new Promise((r) => setTimeout(r, pauseMs));
    }
    return { asked, found };
  }
}
