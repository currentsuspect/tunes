class DiscographyGroup {
  const DiscographyGroup({
    required this.id,
    required this.title,
    required this.type,
    required this.year,
    required this.date,
    required this.owned,
    required this.releaseId,
    required this.ownedTracks,
    required this.totalTracks,
  });

  final String id;
  final String title;
  final String? type;
  final String? year;
  final String? date;
  final bool owned;
  final String? releaseId;
  final int ownedTracks;
  final int? totalTracks;

  factory DiscographyGroup.fromJson(Map<String, dynamic> json) {
    return DiscographyGroup(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      type: json['type'] as String?,
      year: json['year'] as String?,
      date: json['date'] as String?,
      owned: json['owned'] as bool? ?? false,
      releaseId: json['releaseId'] as String?,
      ownedTracks: (json['ownedTracks'] as num?)?.toInt() ?? 0,
      totalTracks: (json['totalTracks'] as num?)?.toInt(),
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

class ExternalArtist {
  const ExternalArtist({
    required this.name,
    required this.mbid,
    required this.type,
    required this.disambiguation,
    required this.score,
  });

  final String name;
  final String mbid;
  final String? type;
  final String? disambiguation;
  final int? score;

  factory ExternalArtist.fromJson(Map<String, dynamic> json) {
    return ExternalArtist(
      name: (json['name'] as String?) ?? '',
      mbid: (json['mbid'] as String?) ?? '',
      type: json['type'] as String?,
      disambiguation: json['disambiguation'] as String?,
      score: (json['score'] as num?)?.toInt(),
    );
  }
}

class ExternalRelease {
  const ExternalRelease({
    required this.id,
    required this.title,
    required this.artist,
    required this.type,
    required this.year,
    required this.date,
    required this.owned,
    required this.releaseId,
    required this.ownedTracks,
    required this.totalTracks,
  });

  final String id;
  final String title;
  final String? artist;
  final String? type;
  final String? year;
  final String? date;
  final bool owned;
  final String? releaseId;
  final int ownedTracks;
  final int? totalTracks;

  factory ExternalRelease.fromJson(Map<String, dynamic> json) {
    return ExternalRelease(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      artist: json['artist'] as String?,
      type: json['type'] as String?,
      year: json['year'] as String?,
      date: json['date'] as String?,
      owned: json['owned'] as bool? ?? false,
      releaseId: json['releaseId'] as String?,
      ownedTracks: (json['ownedTracks'] as num?)?.toInt() ?? 0,
      totalTracks: (json['totalTracks'] as num?)?.toInt(),
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

class ArtistDiscography {
  const ArtistDiscography({
    required this.artist,
    required this.mbid,
    required this.fetchedAt,
    required this.groups,
  });

  final String artist;
  final String? mbid;
  final int? fetchedAt;
  final List<DiscographyGroup> groups;

  bool get available => groups.isNotEmpty;

  factory ArtistDiscography.fromJson(Map<String, dynamic> json) {
    return ArtistDiscography(
      artist: (json['artist'] as String?) ?? '',
      mbid: json['mbid'] as String?,
      fetchedAt: (json['fetchedAt'] as num?)?.toInt(),
      groups: (json['groups'] as List<dynamic>? ?? const [])
          .map((g) => DiscographyGroup.fromJson(g as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// An album by an act in the library that the library does not have.
///
/// Distinct from [DiscographyGroup], which describes one entry in a single
/// artist's catalogue and carries the owned/not-owned answer. This is the
/// cross-library view: the daemon has already decided it is missing, and
/// which act to credit it to.
class MissingRelease {
  const MissingRelease({
    required this.id,
    required this.title,
    required this.artist,
    required this.type,
    required this.year,
    required this.artistTracks,
    this.artSha,
    this.artistOwnedReleases,
    this.artistTotalReleases,
  });

  final String id;
  final String title;

  /// The act, spelled the way the library spells it, so tapping through
  /// reaches the artist page.
  final String artist;
  final String? type;
  final String? year;

  /// How many of that act's tracks are held. The daemon ranks on this; the
  /// app shows it so a suggestion carries its own justification.
  final int artistTracks;

  /// The real sleeve, once the daemon has fetched one from Deezer. Null is
  /// ordinary and not an error: covers arrive on the enrichment cycle, and a
  /// record we could not confidently match keeps none rather than borrowing
  /// the wrong one.
  final String? artSha;

  /// How far through this act's catalogue the library is. Null when the daemon
  /// predates the field, which is why nothing shows a completion figure it did
  /// not receive rather than computing a plausible-looking one.
  final int? artistOwnedReleases;
  final int? artistTotalReleases;

  factory MissingRelease.fromJson(Map<String, dynamic> json) {
    return MissingRelease(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      artist: (json['forArtist'] as String?) ?? '',
      type: json['type'] as String?,
      year:
          (json['year'] as String?) ??
          (json['date'] as String?)?.split('-').first,
      artistTracks: (json['artistTracks'] as num?)?.toInt() ?? 0,
      artSha: json['artSha'] as String?,
      artistOwnedReleases: (json['artistOwnedReleases'] as num?)?.toInt(),
      artistTotalReleases: (json['artistTotalReleases'] as num?)?.toInt(),
    );
  }
}
