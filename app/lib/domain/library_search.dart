/// Search over everything on the device: songs, records, artists and
/// playlists, from one query (design approved 23 Oct).
///
/// The old search matched song fields only, so a record or an artist was
/// found only when the box answered, and "travis 2018" found nothing because
/// no single song field contains both words. Here the query is read first:
/// a year becomes a year, an artist's name next to other words becomes "by
/// that artist", and `artist:`, `album:` and `year:` say so outright. Each
/// reading is a chip the listener can tap off, after which those words are
/// matched as plain text again.
///
/// Pure: no Flutter, no I/O, so every rule here is tested directly.
library;

import 'fuzzy.dart';
import 'manifest.dart';

enum SearchKind { all, songs, lyrics, albums, artists, playlists }

enum SongSort { best, mostPlayed, newest, az }

enum FacetKind { artist, album, year }

/// One reading of the query: "by Travis Scott", "from 2018".
class Facet {
  const Facet(this.kind, this.value, {this.inferred = false});

  final FacetKind kind;
  final String value;

  /// Read from plain words rather than said with `artist:` and the like. A
  /// guess that finds nothing is dropped (see [SearchIndex.search]).
  final bool inferred;

  String get label => switch (kind) {
    FacetKind.artist => 'by $value',
    FacetKind.album => 'on $value',
    FacetKind.year => 'from $value',
  };

  @override
  bool operator ==(Object other) =>
      other is Facet && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);
}

/// What the query was read as: facets, and the words left to match.
class ParsedQuery {
  const ParsedQuery({required this.text, this.facets = const []});

  /// Folded words still to be matched against names.
  final String text;
  final List<Facet> facets;

  Facet? of(FacetKind k) {
    for (final f in facets) {
      if (f.kind == k) return f;
    }
    return null;
  }

  bool get isEmpty => text.isEmpty && facets.isEmpty;
}

final _keyed = RegExp(r'\b(artist|by|album|year):("([^"]*)"|(\S+))');
final _year = RegExp(r'^(19|20)\d\d$');

/// Reads [raw]. [artists] are the names the library knows, most-heard first
/// so a tie goes to the one the listener means. Kinds in [off] were tapped
/// off: their words are plain text.
ParsedQuery parseQuery(
  String raw,
  List<String> artists, {
  Set<FacetKind> off = const {},
}) {
  final facets = <Facet>[];
  var rest = raw;

  // Said outright: artist:"travis scott" album:utopia year:2018.
  for (final m in _keyed.allMatches(raw)) {
    final key = m.group(1)!;
    final value = (m.group(3) ?? m.group(4) ?? '').trim();
    final kind = switch (key) {
      'album' => FacetKind.album,
      'year' => FacetKind.year,
      _ => FacetKind.artist,
    };
    if (value.isEmpty || off.contains(kind)) continue;
    final named = kind == FacetKind.artist
        ? _bestArtist(foldForSearch(value).split(' '), artists) ?? value
        : value;
    facets.add(Facet(kind, named));
    rest = rest.replaceFirst(m.group(0)!, ' ');
  }

  var tokens = foldForSearch(rest).split(' ').where((t) => t.isNotEmpty);
  var words = tokens.toList();

  // A year on its own is a year.
  if (!off.contains(FacetKind.year) &&
      facets.every((f) => f.kind != FacetKind.year)) {
    final i = words.indexWhere(_year.hasMatch);
    if (i >= 0) {
      facets.add(Facet(FacetKind.year, words[i], inferred: true));
      words = [...words]..removeAt(i);
    }
  }

  // An artist's name at either end, next to something else to narrow by.
  // Just the name ("travis") is left alone: the top result is the artist.
  if (!off.contains(FacetKind.artist) &&
      facets.every((f) => f.kind != FacetKind.artist) &&
      words.isNotEmpty &&
      (words.length >= 2 || facets.isNotEmpty)) {
    for (var k = words.length; k >= 1; k--) {
      if (k == words.length && facets.isEmpty) continue;
      final head = _bestArtist(words.sublist(0, k), artists, guess: true);
      if (head != null) {
        facets.add(Facet(FacetKind.artist, head, inferred: true));
        words = words.sublist(k);
        break;
      }
      final tail = _bestArtist(
        words.sublist(words.length - k),
        artists,
        guess: true,
      );
      if (tail != null) {
        facets.add(Facet(FacetKind.artist, tail, inferred: true));
        words = words.sublist(0, words.length - k);
        break;
      }
    }
  }
  return ParsedQuery(text: words.join(' '), facets: facets);
}

/// The first artist (in the given order) whose name every word starts a
/// word of, in order: "travis" and "travis sc" are Travis Scott; "scott
/// travis" is not.
///
/// A [guess] needs every word to be three letters or more, so "lo fi" is not
/// read as an artist called Lou.
String? _bestArtist(
  List<String> words,
  List<String> artists, {
  bool guess = false,
}) {
  if (words.isEmpty) return null;
  if (guess && words.any((w) => w.length < 3)) return null;
  for (final a in artists) {
    final names = foldForSearch(a).split(' ');
    var j = 0;
    var ok = true;
    for (final w in words) {
      while (j < names.length && !names[j].startsWith(w)) {
        j++;
      }
      if (j == names.length) {
        ok = false;
        break;
      }
      j++;
    }
    if (ok) return a;
  }
  return null;
}

/// A playlist as search sees it.
class SearchPlaylist {
  const SearchPlaylist({
    required this.id,
    required this.name,
    required this.count,
  });

  final int id;
  final String name;
  final int count;
}

/// An artist with what the library holds of theirs.
class SearchArtist {
  const SearchArtist({
    required this.name,
    required this.songs,
    required this.records,
    required this.featuredOn,
    this.artSha,
  });

  final String name;
  final int songs;
  final int records;

  /// Songs by others that they are on.
  final int featuredOn;
  final String? artSha;
}

/// What the top of All shows.
sealed class TopResult {
  const TopResult();
}

class TopArtist extends TopResult {
  const TopArtist(this.artist);
  final SearchArtist artist;
}

class TopRecord extends TopResult {
  const TopRecord(this.release);
  final ManifestRelease release;
}

class TopSong extends TopResult {
  const TopSong(this.track);
  final ManifestTrack track;
}

/// A song found by its words, and the line that matched.
class LyricHit {
  const LyricHit(this.track, this.line);

  final ManifestTrack track;

  /// The line as written (timestamps off), to quote back.
  final String line;
}

class LibrarySearchResults {
  const LibrarySearchResults({
    this.lyrics = const [],
    required this.query,
    required this.songs,
    required this.featuring,
    required this.records,
    required this.artists,
    required this.playlists,
    this.top,
  });

  final ParsedQuery query;

  /// Songs that match. With an artist chip: that artist's own songs.
  final List<ManifestTrack> songs;

  /// With an artist chip: other people's songs that artist is on.
  final List<ManifestTrack> featuring;
  final List<ManifestRelease> records;
  final List<SearchArtist> artists;
  final List<SearchPlaylist> playlists;
  final TopResult? top;

  /// Songs whose lyrics hold the words, with the line. Songs already found by
  /// name are left out of here.
  final List<LyricHit> lyrics;

  int get songCount => songs.length + featuring.length;
  bool get isEmpty =>
      songCount == 0 &&
      records.isEmpty &&
      artists.isEmpty &&
      playlists.isEmpty &&
      lyrics.isEmpty;
}

/// The library, prepared once so a keystroke only scores.
class SearchIndex {
  SearchIndex({
    required List<ManifestTrack> tracks,
    required List<ManifestRelease> releases,
    required List<ManifestArtist> artists,
    Map<String, int> plays = const {},
  }) : _tracks = tracks,
       _releases = releases,
       _plays = plays {
    for (final t in tracks) {
      _trackFields[t.sha] = [
        SearchField(t.title, weight: 1.2),
        SearchField(t.artist),
        SearchField(t.album, weight: 0.8),
      ];
    }
    final bySha = {for (final t in tracks) t.sha: t};
    for (final r in releases) {
      _releaseTracks[r.id] = [for (final s in r.trackShas) ?bySha[s]];
      _releaseFields[r.id] = [
        SearchField(r.title, weight: 1.2),
        SearchField(r.artist, weight: 0.9),
      ];
    }
    // Every act a song is credited to, with what they have here.
    final art = {for (final a in artists) a.name: a.artSha};
    final own = <String, int>{};
    final feat = <String, int>{};
    final records = <String, int>{};
    final heard = <String, int>{};
    for (final t in tracks) {
      own[t.artistKey] = (own[t.artistKey] ?? 0) + 1;
      heard[t.artistKey] = (heard[t.artistKey] ?? 0) + (plays[t.sha] ?? 0);
      for (final f in t.featured) {
        if (f == t.artistKey) continue;
        feat[f] = (feat[f] ?? 0) + 1;
      }
    }
    for (final r in releases) {
      records[r.artist] = (records[r.artist] ?? 0) + 1;
    }
    final names = {...own.keys, ...feat.keys};
    for (final n in names) {
      _artists.add(
        SearchArtist(
          name: n,
          songs: own[n] ?? 0,
          records: records[n] ?? 0,
          featuredOn: feat[n] ?? 0,
          artSha: art[n],
        ),
      );
      _artistFields[n] = [SearchField(n)];
    }
    // Most heard first, then most held: who a short name most likely means.
    _artists.sort((a, b) {
      final h = (heard[b.name] ?? 0).compareTo(heard[a.name] ?? 0);
      if (h != 0) return h;
      return (b.songs + b.featuredOn).compareTo(a.songs + a.featuredOn);
    });
    _artistNames = [for (final a in _artists) a.name];
  }

  final List<ManifestTrack> _tracks;
  final List<ManifestRelease> _releases;
  final Map<String, int> _plays;
  final Map<String, List<SearchField>> _trackFields = {};
  final Map<String, List<SearchField>> _releaseFields = {};
  final Map<String, List<ManifestTrack>> _releaseTracks = {};
  final Map<String, List<SearchField>> _artistFields = {};
  final List<SearchArtist> _artists = [];
  late final List<String> _artistNames;

  List<String> get artistNames => _artistNames;

  LibrarySearchResults search(
    String raw, {
    Set<FacetKind> off = const {},
    SongSort sort = SongSort.best,
    bool Function(ManifestTrack)? onlyWhere,
    List<SearchPlaylist> playlists = const [],
  }) {
    final r = _search(
      parseQuery(raw, _artistNames, off: off),
      sort,
      onlyWhere,
      playlists,
    );
    // A guess that empties the page was the wrong guess: "1999" is a song
    // as well as a year. Search the words as they were typed instead.
    final guessed = {
      for (final f in r.query.facets)
        if (f.inferred) f.kind,
    };
    if (guessed.isEmpty || !r.isEmpty) return r;
    return _search(
      parseQuery(raw, _artistNames, off: {...off, ...guessed}),
      sort,
      onlyWhere,
      playlists,
    );
  }

  LibrarySearchResults _search(
    ParsedQuery q,
    SongSort sort,
    bool Function(ManifestTrack)? onlyWhere,
    List<SearchPlaylist> playlists,
  ) {
    // Plain matches first. A typo means some word lands nowhere, so the
    // plain pass finds nothing at all; only then is typo matching (most of
    // the cost) worth running.
    final plain = _searchWith(q, sort, onlyWhere, playlists, typos: false);
    if (!plain.isEmpty || q.text.isEmpty) return plain;
    return _searchWith(q, sort, onlyWhere, playlists, typos: true);
  }

  LibrarySearchResults _searchWith(
    ParsedQuery q,
    SongSort sort,
    bool Function(ManifestTrack)? onlyWhere,
    List<SearchPlaylist> playlists, {
    required bool typos,
  }) {
    final text = q.text;
    final pq = PreparedQuery(text, typos: typos);
    final artist = q.of(FacetKind.artist)?.value;
    final year = q.of(FacetKind.year)?.value;
    final album = q.of(FacetKind.album)?.value;
    final albumFold = album == null ? null : foldForSearch(album);

    bool yearOk(String? y) => year == null || (y ?? '').startsWith(year);
    bool albumOk(String a) =>
        albumFold == null || foldForSearch(a).contains(albumFold);

    // Songs.
    final own = <(ManifestTrack, double)>[];
    final feat = <(ManifestTrack, double)>[];
    for (final t in _tracks) {
      if (!yearOk(t.year) || !albumOk(t.album)) continue;
      if (onlyWhere != null && !onlyWhere(t)) continue;
      var isFeat = false;
      if (artist != null) {
        if (t.artistKey == artist) {
          // theirs
        } else if (t.featured.contains(artist) ||
            foldForSearch(t.artist).contains(foldForSearch(artist))) {
          isFeat = true;
        } else {
          continue;
        }
      }
      final s = text.isEmpty ? 1.0 : pq.score(_trackFields[t.sha]!);
      if (s <= 0) continue;
      (isFeat ? feat : own).add((t, s));
    }
    var songs = _sortSongs(own, sort);
    final featuring = _sortSongs(feat, sort);

    // Records.
    final recs = <(ManifestRelease, double)>[];
    for (final r in _releases) {
      if (!yearOk(r.year) || !albumOk(r.title)) continue;
      if (artist != null && r.artist != artist) continue;
      if (onlyWhere != null &&
          !(_releaseTracks[r.id] ?? const []).any(onlyWhere)) {
        continue;
      }
      final s = text.isEmpty ? 1.0 : pq.score(_releaseFields[r.id]!);
      if (s > 0) recs.add((r, s));
    }
    recs.sort((a, b) {
      final c = b.$2.compareTo(a.$2);
      if (c != 0) return c;
      return (b.$1.year ?? '').compareTo(a.$1.year ?? '');
    });

    // Artists: by name only, and not when the query already named one.
    final arts = <(SearchArtist, double)>[];
    if (artist == null && text.isNotEmpty) {
      for (final a in _artists) {
        final s = pq.score(_artistFields[a.name]!);
        if (s > 0) arts.add((a, s));
      }
      // Stable: the list is already most-heard first.
      arts.sort((a, b) => b.$2.compareTo(a.$2));
    }

    // Playlists.
    final lists = <(SearchPlaylist, double)>[];
    if (q.facets.isEmpty && text.isNotEmpty) {
      for (final p in playlists) {
        final s = pq.score([SearchField(p.name)]);
        if (s > 0) lists.add((p, s));
      }
      lists.sort((a, b) => b.$2.compareTo(a.$2));
    }

    final top = _top(q, arts, recs, own);
    final byName = {
      for (final t in own) t.$1.sha,
      for (final t in feat) t.$1.sha,
    };
    // Words are matched as typed; the typo pass is for names.
    final lyricHits = typos
        ? const <LyricHit>[]
        : _lyricSearch(
            text,
            (t) =>
                !byName.contains(t.sha) &&
                yearOk(t.year) &&
                albumOk(t.album) &&
                (artist == null ||
                    t.artistKey == artist ||
                    t.featured.contains(artist)) &&
                (onlyWhere == null || onlyWhere(t)),
          );
    // An artist on top: their own songs lead, most played first, the way
    // their page would list them; songs that only mention them follow.
    if (top is TopArtist && sort == SongSort.best) {
      final name = top.artist.name;
      final theirs = [
        for (final t in songs)
          if (t.artistKey == name) t,
      ]..sort((a, b) => (_plays[b.sha] ?? 0).compareTo(_plays[a.sha] ?? 0));
      songs = [
        ...theirs,
        for (final t in songs)
          if (t.artistKey != name) t,
      ];
    }
    return LibrarySearchResults(
      query: q,
      songs: songs,
      featuring: featuring,
      records: [for (final r in recs) r.$1],
      artists: [for (final a in arts) a.$1],
      playlists: [for (final p in lists) p.$1],
      top: top,
      lyrics: lyricHits,
    );
  }

  /// Lyric lines per song, folded, with their words split out. Built in
  /// small batches by [warmLyrics] (about 1,500 songs and 90,000 lines), so
  /// it never holds up a frame; until it is ready, lyric search finds
  /// nothing rather than stall the keyboard.
  final List<_Lyrics> _lyricIndex = [];
  bool _lyricsReady = false;
  Future<void>? _warming;

  bool get lyricsReady => _lyricsReady;

  static final _stamp = RegExp(r'^\s*(\[[^\]]*\]\s*)+');

  /// Prepares lyric search, yielding between batches. Safe to call often.
  Future<void> warmLyrics() => _warming ??= () async {
    var n = 0;
    for (final t in _tracks) {
      final text = t.lyrics;
      if (text == null || text.trim().isEmpty) continue;
      final raw = <String>[];
      for (final l in text.split('\n')) {
        final line = l.replaceFirst(_stamp, '').trim();
        if (line.isNotEmpty) raw.add(line);
      }
      final folded = [for (final l in raw) foldForSearch(l)];
      _lyricIndex.add(
        _Lyrics(t, raw, folded, folded.join(' '), [
          for (final l in folded) l.split(' '),
        ]),
      );
      if (++n % 60 == 0) await Future<void>.delayed(Duration.zero);
    }
    _lyricsReady = true;
  }();

  /// Songs by their words: the phrase as typed anywhere in a song (across
  /// line breaks too), else every typed word in one line. Needs two words or
  /// eight letters, so a short name does not drag in every song saying it.
  List<LyricHit> _lyricSearch(
    String text,
    bool Function(ManifestTrack) keep, {
    int limit = 30,
  }) {
    final words = text.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.length < 2 && text.length < 8) return const [];
    final phrase = <LyricHit>[];
    final loose = <LyricHit>[];
    if (!_lyricsReady) return const [];
    for (final x in _lyricIndex) {
      final (t, raw, folded, all) = (x.track, x.raw, x.folded, x.all);
      if (!keep(t)) continue;
      if (all.contains(text)) {
        // Quote the line the phrase starts in: the first whose next few
        // lines, read on, hold it.
        var at = 0;
        for (var i = 0; i < folded.length; i++) {
          final window = folded
              .sublist(i, i + 3 > folded.length ? folded.length : i + 3)
              .join(' ');
          if (window.contains(text)) {
            at = i;
            break;
          }
        }
        // Then on to the line it actually starts in.
        while (at + 1 < folded.length &&
            folded
                .sublist(
                  at + 1,
                  at + 4 > folded.length ? folded.length : at + 4,
                )
                .join(' ')
                .contains(text)) {
          at++;
        }
        phrase.add(LyricHit(t, raw[at]));
        continue;
      }
      if (words.length < 2) continue;
      for (var i = 0; i < folded.length; i++) {
        final ws = x.words[i];
        if (words.every((w) => ws.any((y) => y.startsWith(w)))) {
          loose.add(LyricHit(t, raw[i]));
          break;
        }
      }
    }
    int byPlays(LyricHit a, LyricHit b) =>
        (_plays[b.track.sha] ?? 0).compareTo(_plays[a.track.sha] ?? 0);
    phrase.sort(byPlays);
    loose.sort(byPlays);
    return [...phrase, ...loose].take(limit).toList();
  }

  List<ManifestTrack> _sortSongs(
    List<(ManifestTrack, double)> scored,
    SongSort sort,
  ) {
    int byPlays(ManifestTrack a, ManifestTrack b) =>
        (_plays[b.sha] ?? 0).compareTo(_plays[a.sha] ?? 0);
    scored.sort((a, b) {
      switch (sort) {
        case SongSort.best:
          final c = b.$2.compareTo(a.$2);
          return c != 0 ? c : byPlays(a.$1, b.$1);
        case SongSort.mostPlayed:
          final c = byPlays(a.$1, b.$1);
          return c != 0 ? c : b.$2.compareTo(a.$2);
        case SongSort.newest:
          final c = (b.$1.year ?? '').compareTo(a.$1.year ?? '');
          if (c != 0) return c;
          final at = b.$1.addedAt, bt = a.$1.addedAt;
          if (at != null && bt != null) return at.compareTo(bt);
          return 0;
        case SongSort.az:
          return foldForSearch(a.$1.title).compareTo(foldForSearch(b.$1.title));
      }
    });
    return [for (final s in scored) s.$1];
  }

  /// The one thing the query most plainly names: an artist whose name it is
  /// (or starts), else a record whose title it is, else the best song.
  TopResult? _top(
    ParsedQuery q,
    List<(SearchArtist, double)> arts,
    List<(ManifestRelease, double)> recs,
    List<(ManifestTrack, double)> songs,
  ) {
    if (q.facets.isNotEmpty || q.text.isEmpty) {
      return songs.isEmpty ? null : TopSong(_bestSong(songs));
    }
    final text = q.text;
    for (final a in arts) {
      if (foldForSearch(a.$1.name).startsWith(text)) return TopArtist(a.$1);
    }
    for (final r in recs) {
      if (foldForSearch(r.$1.title) == text) return TopRecord(r.$1);
    }
    if (songs.isNotEmpty) return TopSong(_bestSong(songs));
    if (arts.isNotEmpty) return TopArtist(arts.first.$1);
    if (recs.isNotEmpty) return TopRecord(recs.first.$1);
    return null;
  }

  ManifestTrack _bestSong(List<(ManifestTrack, double)> songs) {
    var best = songs.first;
    for (final s in songs) {
      if (s.$2 > best.$2 ||
          (s.$2 == best.$2 &&
              (_plays[s.$1.sha] ?? 0) > (_plays[best.$1.sha] ?? 0))) {
        best = s;
      }
    }
    return best.$1;
  }
}

class _Lyrics {
  _Lyrics(this.track, this.raw, this.folded, this.all, this.words);

  final ManifestTrack track;
  final List<String> raw;
  final List<String> folded;
  final String all;
  final List<List<String>> words;
}
