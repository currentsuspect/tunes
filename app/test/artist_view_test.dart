import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/domain/artist_view.dart';
import 'package:tunes/domain/discography.dart';
import 'package:tunes/domain/manifest.dart';

ManifestTrack _t(
  String sha,
  String artist, {
  String album = 'A',
  String? year,
  int? n,
  int? disc,
  List<String> featured = const [],
  String? title,
}) => ManifestTrack(
  sha: sha,
  size: 1,
  codec: 'flac',
  sampleRate: 44100,
  channels: 2,
  bitrate: 1000,
  durationMs: 180000,
  title: title ?? sha,
  artist: artist,
  album: album,
  year: year,
  artSha: null,
  releaseId: null,
  trackNumber: n,
  discNumber: disc,
  primaryArtist: artist,
  featured: featured,
);

DiscographyGroup _g(
  String id, {
  bool owned = false,
  String? year,
  int ownedTracks = 0,
  int? total,
}) => DiscographyGroup(
  id: id,
  title: id,
  type: 'Album',
  year: year,
  date: null,
  owned: owned,
  releaseId: null,
  ownedTracks: ownedTracks,
  totalTracks: total,
);

ArtistDiscography _disc(List<DiscographyGroup> g) =>
    ArtistDiscography(artist: 'Yeat', mbid: null, fetchedAt: null, groups: g);

TunesManifest _m(List<ManifestTrack> t) =>
    TunesManifest(tracks: t, releases: const []);

void main() {
  group('songs you have', () {
    test('the artist\'s own songs come first, newest record first', () {
      final v = buildArtistView(
        artist: 'Yeat',
        manifest: _m([
          _t('old', 'Yeat', album: 'Old', year: '2021', n: 1),
          _t('guest', 'Ken', featured: ['Yeat'], year: '2024'),
          _t('new', 'Yeat', album: 'New', year: '2024', n: 1),
        ]),
      );
      expect(v.ownedSongs.map((t) => t.sha), ['new', 'old', 'guest']);
      expect(v.leadSongCount, 2);
    });

    test('within a record, disc then track order; no year goes last', () {
      final v = buildArtistView(
        artist: 'Yeat',
        manifest: _m([
          _t('b2', 'Yeat', year: '2024', disc: 2, n: 1),
          _t('a2', 'Yeat', year: '2024', disc: 1, n: 2),
          _t('a1', 'Yeat', year: '2024', disc: 1, n: 1),
          _t('none', 'Yeat'),
        ]),
      );
      expect(v.ownedSongs.map((t) => t.sha), ['a1', 'a2', 'b2', 'none']);
    });

    test('other artists are left out', () {
      final v = buildArtistView(
        artist: 'Yeat',
        manifest: _m([_t('x', 'Ken'), _t('y', 'Yeat')]),
      );
      expect(v.ownedSongs.map((t) => t.sha), ['y']);
    });
  });

  group('songs you do not have', () {
    final groups = [
      _g('full', owned: true, year: '2024', ownedTracks: 12, total: 12),
      _g('almost', owned: true, year: '2022', ownedTracks: 9, total: 10),
      _g('half', owned: true, year: '2023', ownedTracks: 5, total: 10),
      _g('gone-new', year: '2025'),
      _g('gone-old', year: '2019'),
      _g('gone-nodate'),
    ];

    test('part-owned records are listed nearest to finished first', () {
      final v = buildArtistView(
        artist: 'Yeat',
        manifest: _m([_t('x', 'Yeat')]),
        discography: _disc(groups),
      );
      expect(v.unfinished.map((g) => g.id), ['almost', 'half']);
    });

    test('records you have none of are newest first, undated last', () {
      final v = buildArtistView(
        artist: 'Yeat',
        manifest: _m([_t('x', 'Yeat')]),
        discography: _disc(groups),
      );
      expect(v.absent.map((g) => g.id), [
        'gone-new',
        'gone-old',
        'gone-nodate',
      ]);
    });

    test('a complete record is in neither list', () {
      final v = buildArtistView(
        artist: 'Yeat',
        manifest: _m([_t('x', 'Yeat')]),
        discography: _disc(groups),
      );
      expect(
        [...v.unfinished, ...v.absent].map((g) => g.id),
        isNot(contains('full')),
      );
    });

    test('completion is owned over catalogue, null when unknown', () {
      final withCat = buildArtistView(
        artist: 'Yeat',
        manifest: _m([_t('x', 'Yeat')]),
        discography: _disc(groups),
      );
      expect(withCat.catalogueTotal, 6);
      expect(withCat.catalogueOwned, 3);
      expect(withCat.completion, closeTo(0.5, 1e-9));

      final without = buildArtistView(
        artist: 'Yeat',
        manifest: _m([_t('x', 'Yeat')]),
      );
      expect(without.completion, isNull);
      expect(without.hasCatalogue, isFalse);
      expect(without.complete, isFalse);
    });

    test('an artist whose catalogue is all held is complete', () {
      final v = buildArtistView(
        artist: 'Yeat',
        manifest: _m([_t('x', 'Yeat')]),
        discography: _disc([_g('a', owned: true, ownedTracks: 5, total: 5)]),
      );
      expect(v.complete, isTrue);
    });
  });

  group('collaborators', () {
    test('counts guests on their songs and hosts of theirs, most first', () {
      final v = buildArtistView(
        artist: 'Yeat',
        manifest: _m([
          _t('1', 'Yeat', featured: ['Ken']),
          _t('2', 'Yeat', featured: ['Ken', 'Lil']),
          _t('3', 'Doja', featured: ['Yeat']),
        ]),
      );
      expect(v.collaborators.map((c) => '${c.name}:${c.songs}'), [
        'Ken:2',
        'Doja:1',
        'Lil:1',
      ]);
    });

    test(
      'the artist is never their own collaborator, and the list is capped',
      () {
        final tracks = [
          for (var i = 0; i < 30; i++)
            _t('$i', 'Yeat', featured: ['G$i', 'Yeat']),
        ];
        final v = buildArtistView(
          artist: 'Yeat',
          manifest: _m(tracks),
          maxCollaborators: 5,
        );
        expect(v.collaborators.length, 5);
        expect(v.collaborators.any((c) => c.name == 'Yeat'), isFalse);
      },
    );
  });
}
