/// What Genius knows about the music, as the box hands it on (tunesd
/// about.ts): a song's story and makers, an album's and an artist's
/// write-up, the people around an artist, a person's work. The Roon pass
/// (approved 24 Oct).
library;

List<String> _strings(Object? v) => [
  for (final x in (v as List<dynamic>? ?? const [])) '$x',
];

class Credit {
  const Credit(this.role, this.names);

  /// Genius's words: "Mixing Engineer", "Label", "Additional Vocals".
  final String role;
  final List<String> names;

  static Credit fromJson(Map<String, dynamic> j) =>
      Credit('${j['role']}', _strings(j['names']));
}

class Connection {
  const Connection(this.type, this.songs);

  /// samples, sampled_in, interpolates, interpolated_by, cover_of, ...
  final String type;
  final List<({String title, String artist})> songs;

  /// The type in plain words, for a badge.
  String get label => switch (type) {
    'samples' => 'Samples',
    'sampled_in' => 'Sampled in',
    'interpolates' => 'Interpolates',
    'interpolated_by' => 'Interpolated by',
    'cover_of' => 'Covers',
    'covered_by' => 'Covered by',
    'remix_of' => 'Remix of',
    'remixed_by' => 'Remixed by',
    'live_version_of' => 'Live version of',
    'performed_live_as' => 'Performed live as',
    _ => type.replaceAll('_', ' '),
  };

  static Connection fromJson(Map<String, dynamic> j) =>
      Connection('${j['type']}', [
        for (final s in (j['songs'] as List<dynamic>? ?? const []))
          (
            title: '${(s as Map<String, dynamic>)['title']}',
            artist: '${s['artist'] ?? ''}',
          ),
      ]);
}

class SongAbout {
  const SongAbout({
    required this.url,
    required this.description,
    required this.releaseDate,
    required this.producers,
    required this.writers,
    required this.featured,
    required this.credits,
    required this.connections,
    required this.albumName,
  });

  final String url;
  final String? description;
  final String? releaseDate;
  final List<String> producers;
  final List<String> writers;
  final List<String> featured;
  final List<Credit> credits;
  final List<Connection> connections;
  final String? albumName;

  static SongAbout fromJson(Map<String, dynamic> j) => SongAbout(
    url: '${j['url'] ?? ''}',
    description: j['description'] as String?,
    releaseDate: j['releaseDate'] as String?,
    producers: _strings(j['producers']),
    writers: _strings(j['writers']),
    featured: _strings(j['featured']),
    credits: [
      for (final c in (j['credits'] as List<dynamic>? ?? const []))
        Credit.fromJson(c as Map<String, dynamic>),
    ],
    connections: [
      for (final c in (j['connections'] as List<dynamic>? ?? const []))
        Connection.fromJson(c as Map<String, dynamic>),
    ],
    albumName: (j['album'] as Map<String, dynamic>?)?['name'] as String?,
  );
}

class AlbumAbout {
  const AlbumAbout({
    required this.url,
    required this.description,
    required this.releaseDate,
    required this.credits,
  });

  final String url;
  final String? description;
  final String? releaseDate;
  final List<Credit> credits;

  /// The album's label(s), from its credits.
  List<String> get labels => [
    for (final c in credits)
      if (c.role == 'Label') ...c.names,
  ];

  static AlbumAbout fromJson(Map<String, dynamic> j) => AlbumAbout(
    url: '${j['url'] ?? ''}',
    description: j['description'] as String?,
    releaseDate: j['releaseDate'] as String?,
    credits: [
      for (final c in (j['credits'] as List<dynamic>? ?? const []))
        Credit.fromJson(c as Map<String, dynamic>),
    ],
  );
}

class ArtistAbout {
  const ArtistAbout({
    required this.url,
    required this.description,
    required this.alternateNames,
  });

  final String url;
  final String? description;
  final List<String> alternateNames;

  static ArtistAbout fromJson(Map<String, dynamic> j) => ArtistAbout(
    url: '${j['url'] ?? ''}',
    description: j['description'] as String?,
    alternateNames: _strings(j['alternateNames']),
  );
}

/// Someone credited on an artist's songs, by how many.
class Collaborator {
  const Collaborator(this.name, this.songs, this.roles);

  final String name;
  final int songs;
  final List<String> roles;

  static Collaborator fromJson(Map<String, dynamic> j) => Collaborator(
    '${j['name']}',
    (j['songs'] as num?)?.toInt() ?? 0,
    _strings(j['roles']),
  );
}

/// A song a person worked on, and how ("produced", "written", "featured").
class Work {
  const Work(this.sha, this.roles);

  final String sha;
  final List<String> roles;

  static Work fromJson(Map<String, dynamic> j) =>
      Work('${j['sha']}', _strings(j['roles']));
}

/// A credit's name as a person is called: Genius adds "(Producer)".
String personName(String credit) =>
    credit.replaceAll(RegExp(r'\s*\(Producer\)$'), '').trim();
