import 'discography.dart';

class ManifestTrack {
  const ManifestTrack({
    required this.sha,
    required this.size,
    required this.codec,
    required this.sampleRate,
    required this.channels,
    required this.bitrate,
    required this.durationMs,
    required this.title,
    required this.artist,
    required this.album,
    required this.year,
    required this.artSha,
    required this.releaseId,
    required this.trackNumber,
    required this.discNumber,
    this.releaseIds = const [],
    this.addedAt,
    this.totalTracks,
    this.embeddedTitle,
    this.embeddedArtist,
    this.embeddedAlbum,
    this.embeddedYear,
    this.lyrics,
    this.lyricsSource,
    this.lyricsRev,
    this.primaryArtist,
    this.featured = const [],
  });

  final String sha;
  final int size;
  final String? codec;
  final int? sampleRate;
  final int? channels;
  final int? bitrate;
  final int? durationMs;
  final String title;
  final String artist;
  final String album;
  final String? year;
  final String? artSha;
  final String? releaseId;
  final int? trackNumber;
  final int? discNumber;
  final List<String> releaseIds;
  final int? totalTracks;
  final DateTime? addedAt;
  // v4 wire: extracted from embedded tags by ffprobe on the daemon.
  // The app's query layer applies the local-wins policy (user edit >
  // embedded > daemon-supplied) so these stay raw.
  final String? embeddedTitle;
  final String? embeddedArtist;
  final String? embeddedAlbum;
  final String? embeddedYear;
  // Lyrics content + provenance. Source is one of: 'user' (typed by
  // the user in-app), 'lrc' (parsed from a sidecar LRC), or a remote
  // source identifier.
  final String? lyrics;
  final String? lyricsSource;

  /// The box's stamp of the lyrics' words (tunesd lyricsRev): the same
  /// stamp, the same words. A lean manifest carries only this, and the
  /// words that changed are fetched by it (ManifestStore.staleLyrics).
  final String? lyricsRev;

  /// The same song with [text] as its lyrics, for filling lyrics in after
  /// the library is already on screen (ManifestStore, slim read).
  ManifestTrack withLyrics(String text, String? source) => ManifestTrack(
    sha: sha,
    size: size,
    codec: codec,
    sampleRate: sampleRate,
    channels: channels,
    bitrate: bitrate,
    durationMs: durationMs,
    title: title,
    artist: artist,
    album: album,
    year: year,
    artSha: artSha,
    releaseId: releaseId,
    trackNumber: trackNumber,
    discNumber: discNumber,
    releaseIds: releaseIds,
    addedAt: addedAt,
    totalTracks: totalTracks,
    embeddedTitle: embeddedTitle,
    embeddedArtist: embeddedArtist,
    embeddedAlbum: embeddedAlbum,
    embeddedYear: embeddedYear,
    lyrics: text,
    lyricsSource: source,
    lyricsRev: lyricsRev,
    primaryArtist: primaryArtist,
    featured: featured,
  );
  // The act this track belongs to, with guest credits separated out by the
  // daemon. `artist` stays exactly as the tagger wrote it, so it is what we
  // display; `primaryArtist` is what we group by, otherwise one album lands
  // under nine artists ("Yeat", "Yeat;Don Toliver", "Yeat, Kodak Black"...).
  final String? primaryArtist;
  final List<String> featured;

  /// What a list row should show for this track's artist: the act alone.
  /// The raw `artist` tag is a storage string — it separates collaborators
  /// with ";" or "/", which is Vorbis multi-value syntax and not something a
  /// listener should ever be shown. Guests are reachable as their own entries
  /// in the artist list instead.
  String get artistDisplay => artistKey;

  /// The album tag, or null when we never resolved one.
  ///
  /// [ManifestTrack.fromJson] fills an absent album with the string
  /// `'unknown album'`. That is a parsing detail, and a surface that prints
  /// it is showing a listener our placeholder rather than saying it does not
  /// know. Detail views should render their usual em dash for null instead.
  String? get albumOrNull {
    final a = album.trim();
    if (a.isEmpty) return null;
    if (a.toLowerCase() == 'unknown album') return null;
    return album;
  }

  /// The album line for a surface that already shows the title next to it,
  /// or null when it would only repeat.
  ///
  /// Singles are named after their only track, so Now Playing was printing
  /// the same words twice in a row under the artwork. Callers render nothing
  /// when this is null rather than reserving a blank line, so the block stays
  /// vertically centred either way.
  String? get albumLabel {
    final a = albumOrNull;
    if (a == null) return null;
    if (a.trim().toLowerCase() == title.trim().toLowerCase()) return null;
    return a;
  }

  /// The one-line "who and where from" caption under a track title.
  ///
  /// Four screens were each building this by hand, and they had already
  /// drifted: two used the raw `artist` tag, so a collaboration showed up as
  /// `Yeat;Don Toliver` -- Vorbis multi-value syntax leaking to the listener.
  /// Keeping it here means the next surface inherits the rule rather than
  /// deriving it a fifth time.
  String get artistAlbumLine {
    final a = albumLabel;
    return a == null ? artistDisplay : '$artistDisplay — $a';
  }

  /// Grouping key for the artist list. Falls back to the raw credit for
  /// tracks synced before the daemon started sending primaryArtist.
  String get artistKey {
    final act = primaryArtist;
    if (act != null && act.isNotEmpty) return act;
    return artist;
  }

  factory ManifestTrack.fromJson(Map<String, dynamic> json) {
    return ManifestTrack(
      sha: json['sha'] as String,
      size: (json['size'] as num?)?.toInt() ?? 0,
      codec: json['codec'] as String?,
      sampleRate: (json['sampleRate'] as num?)?.toInt(),
      channels: (json['channels'] as num?)?.toInt(),
      bitrate: (json['bitrate'] as num?)?.toInt(),
      durationMs: (json['durationMs'] as num?)?.toInt(),
      title: (json['title'] as String?) ?? 'untitled',
      artist: (json['artist'] as String?) ?? 'unknown artist',
      album: (json['album'] as String?) ?? 'unknown album',
      year: json['year'] as String?,
      artSha: json['artSha'] as String?,
      releaseId: json['releaseId'] as String?,
      releaseIds: (json['releaseIds'] as List<dynamic>? ?? const [])
          .map((s) => s as String)
          .toList(),
      trackNumber: (json['trackNumber'] as num?)?.toInt(),
      discNumber: (json['discNumber'] as num?)?.toInt(),
      totalTracks: (json['totalTracks'] as num?)?.toInt(),
      addedAt: _parseAddedAt(json['addedAt']),
      embeddedTitle: json['embeddedTitle'] as String?,
      embeddedArtist: json['embeddedArtist'] as String?,
      embeddedAlbum: json['embeddedAlbum'] as String?,
      embeddedYear: json['embeddedYear'] as String?,
      lyrics: json['lyrics'] as String?,
      lyricsSource: json['lyricsSource'] as String?,
      lyricsRev: json['lyricsRev'] as String?,
      primaryArtist: json['primaryArtist'] as String?,
      featured: (json['featured'] as List<dynamic>? ?? const [])
          .map((s) => s as String)
          .toList(),
    );
  }

  static DateTime? _parseAddedAt(Object? raw) {
    if (raw == null) return null;
    if (raw is String && raw.isEmpty) return null;
    return DateTime.tryParse(raw as String);
  }

  String get qualityLabel {
    if (codec == null) return 'unknown';
    final label = codec!.toUpperCase();
    if (bitrate == null) return label;
    return '$label ${(bitrate! / 1000).round()}k';
  }

  String get durationLabel {
    final ms = durationMs;
    if (ms == null) return '';
    final seconds = (ms / 1000).round();
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class ManifestRelease {
  const ManifestRelease({
    required this.id,
    required this.title,
    required this.artist,
    required this.year,
    required this.artSha,
    required this.type,
    required this.totalTracks,
    required this.trackShas,
    this.tracks = const [],
  });

  final String id;
  final String title;
  final String artist;
  final String? year;
  final String? artSha;
  final String? type;
  final int? totalTracks;
  final List<String> trackShas;
  final List<ManifestReleaseTrack> tracks;

  factory ManifestRelease.fromJson(Map<String, dynamic> json) {
    return ManifestRelease(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? 'unknown album',
      artist: (json['artist'] as String?) ?? 'unknown artist',
      year: json['year'] as String?,
      artSha: json['artSha'] as String?,
      type: json['type'] as String?,
      totalTracks: (json['totalTracks'] as num?)?.toInt(),
      trackShas: (json['trackShas'] as List<dynamic>? ?? const [])
          .map((s) => s as String)
          .toList(),
      tracks: (json['tracks'] as List<dynamic>? ?? const [])
          .map((t) => ManifestReleaseTrack.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }

  String get typeLabel {
    final t = type?.toLowerCase();
    if (t == null) return 'Release';
    if (t == 'album') return 'Album';
    if (t == 'single') return 'Single';
    if (t == 'ep') return 'EP';
    if (t == 'compilation') return 'Compilation';
    if (t == 'live') return 'Live';
    return type!;
  }
}

class ManifestReleaseTrack {
  const ManifestReleaseTrack({
    required this.sha,
    required this.trackNumber,
    required this.discNumber,
  });

  final String sha;
  final int? trackNumber;
  final int? discNumber;

  factory ManifestReleaseTrack.fromJson(Map<String, dynamic> json) {
    return ManifestReleaseTrack(
      sha: json['sha'] as String,
      trackNumber: (json['trackNumber'] as num?)?.toInt(),
      discNumber: (json['discNumber'] as num?)?.toInt(),
    );
  }
}

class SearchResults {
  const SearchResults({
    required this.tracks,
    required this.releases,
    required this.artists,
    this.externalArtists = const [],
    this.externalReleases = const [],
  });

  final List<ManifestTrack> tracks;
  final List<ManifestRelease> releases;
  final List<ManifestArtist> artists;
  final List<ExternalArtist> externalArtists;
  final List<ExternalRelease> externalReleases;

  factory SearchResults.fromJson(Map<String, dynamic> json) {
    return SearchResults(
      tracks: (json['tracks'] as List<dynamic>? ?? const [])
          .map((t) => ManifestTrack.fromJson(t as Map<String, dynamic>))
          .toList(),
      releases: (json['releases'] as List<dynamic>? ?? const [])
          .map((r) => ManifestRelease.fromJson(r as Map<String, dynamic>))
          .toList(),
      artists: (json['artists'] as List<dynamic>? ?? const [])
          .map((a) => ManifestArtist.fromJson(a as Map<String, dynamic>))
          .toList(),
      externalArtists: (json['externalArtists'] as List<dynamic>? ?? const [])
          .map((a) => ExternalArtist.fromJson(a as Map<String, dynamic>))
          .toList(),
      externalReleases: (json['externalReleases'] as List<dynamic>? ?? const [])
          .map((a) => ExternalRelease.fromJson(a as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// One of an artist's genres as the box names it (tunesd genres.ts).
class ArtistGenre {
  const ArtistGenre({
    required this.name,
    required this.family,
    required this.weight,
  });

  final String name;
  final String family;

  /// 0..1, strongest first.
  final double weight;

  /// The family's own broad genre ("Hip-Hop" in Hip-Hop): less telling than
  /// a specific room like "Rage".
  bool get broad => name == family;

  static ArtistGenre? tryParse(Object? j) {
    if (j is! Map) return null;
    final n = j['name'];
    final f = j['family'];
    final w = j['weight'];
    if (n is! String || n.isEmpty || f is! String || f.isEmpty) return null;
    return ArtistGenre(name: n, family: f, weight: w is num ? w.toDouble() : 0);
  }

  Map<String, Object> toJson() => {
    'name': name,
    'family': family,
    'weight': weight,
  };
}

class ManifestArtist {
  const ManifestArtist({
    required this.name,
    required this.artSha,
    this.tags = const [],
    this.genres = const [],
  });

  final String name;
  final String? artSha;

  /// Crowd tags for the act: what kind of music it is called ("trap", "cloud
  /// rap"). Empty when the providers had nothing for it, or the box predates the
  /// field.
  final List<String> tags;

  /// Clean genres, strongest first. Empty from a box that predates them.
  final List<ArtistGenre> genres;

  factory ManifestArtist.fromJson(Map<String, dynamic> json) {
    return ManifestArtist(
      name: (json['name'] as String?) ?? '',
      artSha: json['artSha'] as String?,
      tags: [
        for (final t in (json['tags'] as List<dynamic>? ?? const []))
          if (t is String && t.trim().isNotEmpty) t.trim(),
      ],
      genres: [
        for (final g in (json['genres'] as List<dynamic>? ?? const []))
          ?ArtistGenre.tryParse(g),
      ],
    );
  }
}

class TunesManifest {
  const TunesManifest({
    required this.tracks,
    required this.releases,
    this.artists = const [],
    this.integrity,
    this.generatedAt,
    this.pointers = const {},
    this.lean = false,
  });

  /// The box left the lyrics' words out (tunesd leanManifest): what is
  /// stored stays, and the words that changed are fetched by stamp.
  final bool lean;

  final List<ManifestTrack> tracks;

  /// Copies of a recording that are not listed, each pointing at the copy
  /// that is: the daemon's `dupeShas`. A copy can stop being listed because
  /// its source was deleted while an identical one survives; anything this
  /// phone kept under the old sha (a like, a playlist entry, plays, the
  /// queue) is moved onto the listed one (ManifestStore.repoint).
  final Map<String, String> pointers;
  final List<ManifestRelease> releases;
  final List<ManifestArtist> artists;

  /// The daemon's fingerprint of this whole manifest. It moves whenever
  /// anything in it does -- a new song, but also a song whose tags or cover
  /// arrived after it was first shown -- so it is how the app tells that a
  /// library it already has has changed.
  final String? integrity;

  /// When the daemon built this snapshot of the library.
  ///
  /// The edge can hand out a cached copy from R2 while the live daemon keeps
  /// naming what arrived since, so this is the only timestamp that says how
  /// much of the library this copy is known to cover. The sync watermark is
  /// taken from it (domain/sync_watermark).
  final DateTime? generatedAt;

  /// The library as it is without a connection: only the songs [held] says are
  /// on the phone, the records that have any of them left, and each record cut
  /// to those songs.
  ///
  /// A record's total is dropped rather than kept. "5 of 12, 7 missing" would be
  /// true of the library but not of the phone, and offline the question is only
  /// what can be played.
  TunesManifest onlyHeld(bool Function(String sha) held) {
    final kept = [
      for (final t in tracks)
        if (held(t.sha)) t,
    ];
    final shas = {for (final t in kept) t.sha};
    final cut = <ManifestRelease>[];
    for (final r in releases) {
      final here = [
        for (final sha in r.trackShas)
          if (shas.contains(sha)) sha,
      ];
      if (here.isEmpty) continue;
      cut.add(
        ManifestRelease(
          id: r.id,
          title: r.title,
          artist: r.artist,
          year: r.year,
          artSha: r.artSha,
          type: r.type,
          totalTracks: null,
          trackShas: here,
          tracks: [
            for (final rt in r.tracks)
              if (shas.contains(rt.sha)) rt,
          ],
        ),
      );
    }
    return TunesManifest(tracks: kept, releases: cut, artists: artists);
  }

  String? artistArt(String name) {
    for (final a in artists) {
      if (a.name == name) return a.artSha;
    }
    return null;
  }

  factory TunesManifest.fromJson(Map<String, dynamic> json) {
    final tracks = (json['tracks'] as List<dynamic>? ?? const [])
        .map((t) => ManifestTrack.fromJson(t as Map<String, dynamic>))
        .toList();
    final releases = (json['releases'] as List<dynamic>? ?? const [])
        .map((r) => ManifestRelease.fromJson(r as Map<String, dynamic>))
        .toList();
    final artists = (json['artists'] as List<dynamic>? ?? const [])
        .map((a) => ManifestArtist.fromJson(a as Map<String, dynamic>))
        .toList();
    final pointers = <String, String>{};
    for (final t in json['tracks'] as List<dynamic>? ?? const []) {
      final m = t as Map<String, dynamic>;
      final listed = m['sha'] as String;
      for (final d in m['dupeShas'] as List<dynamic>? ?? const []) {
        if (d is String && d != listed) pointers[d] = listed;
      }
    }
    if (releases.isEmpty) {
      return TunesManifest(
        tracks: tracks,
        releases: groupReleases(tracks),
        artists: artists,
        integrity: json['integrity'] as String?,
        generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? ''),
        pointers: pointers,
        lean: json['lean'] == true,
      );
    }
    return TunesManifest(
      tracks: tracks,
      releases: releases,
      artists: artists,
      integrity: json['integrity'] as String?,
      generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? ''),
      pointers: pointers,
      lean: json['lean'] == true,
    );
  }

  List<ManifestTrack> tracksFor(String releaseId) {
    return tracks.where((t) => t.releaseId == releaseId).toList();
  }

  /// Releases belonging to an act. A joint album is credited to its whole
  /// cast ("Fimiguerrero, Lancey Foux, Len"), so a member matches it too.
  static bool _creditsInclude(String credited, String artist) {
    if (credited == artist) return true;
    for (final part in credited.split(',')) {
      if (part.trim() == artist) return true;
    }
    return false;
  }

  List<ManifestRelease> releasesFor(String artist) {
    final matched = releases
        .where((r) => _creditsInclude(r.artist, artist))
        .toList();
    matched.sort((a, b) {
      final ta = a.year ?? '9999';
      final tb = b.year ?? '9999';
      final byYear = tb.compareTo(ta);
      if (byYear != 0) return byYear;
      return a.title.compareTo(b.title);
    });
    return matched;
  }
}

List<ManifestRelease> groupReleases(List<ManifestTrack> tracks) {
  final map = <String, ManifestRelease>{};
  for (final t in tracks) {
    final key =
        t.releaseId ??
        (t.artist.toLowerCase() == 'unknown artist' &&
                t.album.toLowerCase() == 'unknown album'
            ? 'sha:${t.sha}'
            : 'name:${t.artist.toLowerCase()}|${t.album.toLowerCase()}');
    final existing = map[key];
    if (existing == null) {
      map[key] = ManifestRelease(
        id: key,
        title: t.album,
        artist: t.artist,
        year: t.year,
        artSha: t.artSha,
        type: null,
        totalTracks: null,
        trackShas: [t.sha],
      );
    } else if (!existing.trackShas.contains(t.sha)) {
      map[key] = ManifestRelease(
        id: existing.id,
        title: existing.title,
        artist: existing.artist,
        year: existing.year ?? t.year,
        artSha: existing.artSha ?? t.artSha,
        type: existing.type,
        totalTracks: existing.totalTracks,
        trackShas: [...existing.trackShas, t.sha],
      );
    }
  }
  final out = map.values.toList()
    ..sort(
      (a, b) => a.artist != b.artist
          ? a.artist.compareTo(b.artist)
          : a.title.compareTo(b.title),
    );
  for (final r in out) {
    r.trackShas.sort((a, b) {
      final ta = tracks.firstWhere((t) => t.sha == a).trackNumber ?? 999;
      final tb = tracks.firstWhere((t) => t.sha == b).trackNumber ?? 999;
      if (ta != tb) return ta - tb;
      return a.compareTo(b);
    });
  }
  return out;
}
