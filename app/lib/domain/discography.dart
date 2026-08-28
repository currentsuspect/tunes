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
