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
      trackNumber: (json['trackNumber'] as num?)?.toInt(),
      discNumber: (json['discNumber'] as num?)?.toInt(),
    );
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
  });

  final String id;
  final String title;
  final String artist;
  final String? year;
  final String? artSha;
  final String? type;
  final int? totalTracks;
  final List<String> trackShas;

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

class ManifestArtist {
  const ManifestArtist({required this.name, required this.artSha});

  final String name;
  final String? artSha;

  factory ManifestArtist.fromJson(Map<String, dynamic> json) {
    return ManifestArtist(
      name: (json['name'] as String?) ?? '',
      artSha: json['artSha'] as String?,
    );
  }
}

class TunesManifest {
  const TunesManifest({
    required this.tracks,
    required this.releases,
    this.artists = const [],
  });

  final List<ManifestTrack> tracks;
  final List<ManifestRelease> releases;
  final List<ManifestArtist> artists;

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
    if (releases.isEmpty) {
      return TunesManifest(
        tracks: tracks,
        releases: groupReleases(tracks),
        artists: artists,
      );
    }
    return TunesManifest(tracks: tracks, releases: releases, artists: artists);
  }

  List<ManifestTrack> tracksFor(String releaseId) {
    return tracks.where((t) => t.releaseId == releaseId).toList();
  }

  List<ManifestRelease> releasesFor(String artist) {
    return releases.where((r) => r.artist == artist).toList()..sort((a, b) {
      final ta = a.year ?? '9999';
      final tb = b.year ?? '9999';
      final byYear = tb.compareTo(ta);
      if (byYear != 0) return byYear;
      return a.title.compareTo(b.title);
    });
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
