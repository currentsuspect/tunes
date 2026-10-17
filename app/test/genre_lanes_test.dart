import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/domain/genre_lanes.dart';
import 'package:tunes/domain/manifest.dart';
import 'package:tunes/domain/mixes.dart';

ManifestTrack _t(String sha, String artist) => ManifestTrack(
  sha: sha,
  size: 1,
  codec: 'flac',
  sampleRate: 44100,
  channels: 2,
  bitrate: 1000,
  durationMs: 120000,
  title: 'Song $sha',
  artist: artist,
  album: 'A',
  year: '2026',
  artSha: null,
  releaseId: null,
  trackNumber: null,
  discNumber: null,
  primaryArtist: artist,
  featured: const [],
  addedAt: null,
);

const _hip = 'Hip-Hop';

ArtistGenre _g(String name, String family, [double w = 1]) =>
    ArtistGenre(name: name, family: family, weight: w);

/// A library shaped like the owner's: mostly hip-hop rooms, some others.
/// Ten artists per genre, three songs each: 30 per genre, past the 25 floor
/// and the three-per-artist cap of a mix.
final _kinds = <String, List<ArtistGenre>>{
  'Rage A': [_g('Rage', _hip), _g(_hip, _hip, .4)],
  'Plugg A': [_g('Plugg', _hip), _g(_hip, _hip, .4)],
  'Cloud A': [_g('Cloud Rap', _hip)],
  'Trap A': [_g('Trap', _hip)],
  'Drill A': [_g('Drill', _hip)],
  'Rnb A': [_g('R&B', 'R&B & Soul')],
  'Reggae A': [_g('Reggae', 'Reggae & Dancehall')],
  'Afro A': [_g('Afrobeats', 'African')],
};

final _shape = <String, List<ArtistGenre>>{
  for (final e in _kinds.entries)
    for (var n = 0; n < 10; n++) '${e.key}$n': e.value,
};

List<ManifestTrack> _library() => [
  for (final a in _shape.keys)
    for (var i = 0; i < 3; i++) _t('${a.replaceAll(' ', '')}-$i', a),
];

List<GenreLane> _pick(DateTime now, {Map<String, int> plays = const {}}) =>
    pickGenreLanes(
      tracks: _library(),
      genresByArtist: _shape,
      plays: plays,
      now: now,
    );

void main() {
  final monday = DateTime(2026, 10, 12);

  test('three lanes from three families, never a name twice', () {
    final lanes = _pick(monday);
    expect(lanes, hasLength(3));
    expect(lanes.map((l) => l.name).toSet(), hasLength(3));
    // Four families are big enough here, so three lanes are three families.
    expect(lanes.map((l) => l.family).toSet(), hasLength(3));
  });

  test('the broad Hip-Hop lane steps aside for its rooms', () {
    for (var w = 0; w < 12; w++) {
      final lanes = _pick(monday.add(Duration(days: 7 * w)));
      expect(lanes.map((l) => l.name), isNot(contains(_hip)));
    }
  });

  test('holds for a week, then moves on', () {
    List<String> names(DateTime d) => _pick(d).map((l) => l.name).toList();
    expect(names(monday), names(monday.add(const Duration(days: 6))));
    final seen = <String>{};
    for (var w = 0; w < 8; w++) {
      seen.addAll(names(monday.add(Duration(days: 7 * w))));
    }
    // Over two months it has been round most of the library, not two lanes.
    expect(seen.length, greaterThanOrEqualTo(7));
  });

  test('the discovery lane is one she has barely played', () {
    // Every genre played a lot except Reggae.
    final plays = <String, int>{
      for (final t in _library())
        if (!t.artistKey.startsWith('Reggae A')) t.sha: 5,
    };
    var hits = 0;
    for (var w = 0; w < 10; w++) {
      final lanes = _pick(monday.add(Duration(days: 7 * w)), plays: plays);
      final quiet = lanes.where((l) => l.discovery).toList();
      expect(quiet, hasLength(lessThanOrEqualTo(1)));
      if (lanes.any((l) => l.name == 'Reggae')) hits++;
    }
    // Reggae is quietest, so it turns up far more than its 1-in-7 share.
    expect(hits, greaterThanOrEqualTo(2));
  });

  test('a genre under 25 songs is not a lane', () {
    final lanes = pickGenreLanes(
      tracks: [for (var i = 0; i < 10; i++) _t('j$i', 'Jazz A$i')],
      genresByArtist: {
        for (var i = 0; i < 10; i++) 'Jazz A$i': [_g('Jazz', 'Jazz')],
      },
      plays: const {},
      now: monday,
    );
    expect(lanes, isEmpty);
  });

  test('buildMixes uses genres when the box sends them', () {
    final mixes = buildMixes(
      MixInputs(
        tracks: _library(),
        artists: [
          for (final e in _shape.entries)
            ManifestArtist(
              name: e.key,
              artSha: null,
              tags: const ['hip hop'],
              genres: e.value,
            ),
        ],
        releases: const [],
        stamps: const [],
        liked: const {},
        now: monday,
      ),
    ).where((m) => m.kind == MixKind.genre).toList();
    expect(mixes, hasLength(3));
    // Not the raw tag: every artist is tagged "hip hop" here.
    expect(mixes.map((m) => m.title), isNot(contains('Hip Hop')));
    expect(mixes.map((m) => m.id).toSet(), hasLength(3));
  });
}
