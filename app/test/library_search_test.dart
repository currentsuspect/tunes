import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/domain/library_search.dart';
import 'package:tunes/domain/manifest.dart';

ManifestTrack _t(
  String sha,
  String title,
  String artist, {
  String album = 'A',
  String? year,
  String? primary,
  List<String> featured = const [],
  String? lyrics,
}) => ManifestTrack(
  sha: sha,
  size: 1,
  codec: 'flac',
  sampleRate: 44100,
  channels: 2,
  bitrate: 1000,
  durationMs: 180000,
  title: title,
  artist: artist,
  album: album,
  year: year,
  artSha: null,
  releaseId: null,
  trackNumber: null,
  discNumber: null,
  primaryArtist: primary ?? artist,
  featured: featured,
  lyrics: lyrics,
);

ManifestRelease _r(
  String id,
  String title,
  String artist,
  String year,
  List<String> shas,
) => ManifestRelease.fromJson({
  'id': id,
  'title': title,
  'artist': artist,
  'year': year,
  'trackShas': shas,
  'tracks': [
    for (final s in shas) {'sha': s},
  ],
});

void main() {
  final tracks = [
    _t('s1', 'STARGAZING', 'Travis Scott', album: 'ASTROWORLD', year: '2018'),
    _t(
      's2',
      'NO BYSTANDERS',
      'Travis Scott',
      album: 'ASTROWORLD',
      year: '2018',
    ),
    _t('s3', 'MY EYES', 'Travis Scott', album: 'UTOPIA', year: '2023'),
    _t(
      's4',
      'Sky Walker',
      'Miguel/ Travis Scott',
      album: 'War & Leisure',
      year: '2018',
      primary: 'Miguel',
      featured: ['Travis Scott'],
    ),
    _t('s5', '1999', 'Prince', album: '1999', year: '1982'),
    _t('s6', 'Love Story', 'Taylor Swift', album: 'Fearless', year: '2008'),
    _t('s7', 'Lovers Rock', 'TV Girl', album: 'French Exit', year: '2014'),
    _t('s8', 'Daylight', 'Lovejoy', album: 'Are You Alright?', year: '2021'),
  ];
  final releases = [
    _r('r1', 'ASTROWORLD', 'Travis Scott', '2018', ['s1', 's2']),
    _r('r2', 'UTOPIA', 'Travis Scott', '2023', ['s3']),
    _r('r3', '1999', 'Prince', '1982', ['s5']),
  ];
  final plays = {'s1': 41, 's2': 18, 's3': 3};
  SearchIndex index() => SearchIndex(
    tracks: tracks,
    releases: releases,
    artists: const [],
    plays: plays,
  );

  group('reading the query', () {
    test('a name alone is left alone: the artist is the top result', () {
      final r = index().search('travis');
      expect(r.query.facets, isEmpty);
      expect(r.top, isA<TopArtist>());
      expect((r.top! as TopArtist).artist.name, 'Travis Scott');
      expect((r.top! as TopArtist).artist.featuredOn, 1);
    });

    test('"travis 2018" is by Travis Scott, from 2018', () {
      final r = index().search('travis 2018');
      expect(r.query.facets.map((f) => f.label), [
        'from 2018',
        'by Travis Scott',
      ]);
      expect(r.songs.map((t) => t.sha), ['s1', 's2']);
      // Songs of others he is on, kept apart.
      expect(r.featuring.map((t) => t.sha), ['s4']);
      expect(r.records.map((x) => x.id), ['r1']);
    });

    test('an artist next to a title narrows to that artist', () {
      final r = index().search('travis stargazing');
      expect(r.query.of(FacetKind.artist)?.value, 'Travis Scott');
      expect(r.songs.map((t) => t.sha), ['s1']);
    });

    test('a chip tapped off makes those words plain text again', () {
      final r = index().search('travis 2018', off: {FacetKind.year});
      expect(r.query.of(FacetKind.year), isNull);
      // "2018" is now a word to match, and no title holds it.
      expect(r.songCount, 0);
    });

    test('said outright: artist:, album:, year:', () {
      final r = index().search('artist:"travis scott" album:utopia');
      expect(r.query.of(FacetKind.artist)?.value, 'Travis Scott');
      expect(r.query.of(FacetKind.album)?.value, 'utopia');
      expect(r.songs.map((t) => t.sha), ['s3']);
    });

    test('"1999" is a song too: a year that finds nothing is dropped', () {
      final r = index().search('1999');
      expect(r.query.facets, isEmpty);
      expect(r.songs.map((t) => t.sha), ['s5']);
      expect(r.records.map((x) => x.id), ['r3']);
    });

    test('"love story" is not "by Lovejoy"', () {
      final r = index().search('love story');
      expect(r.songs.first.sha, 's6');
    });
  });

  group('ranking and narrowing', () {
    test('typos still land', () {
      expect(index().search('stargazng').songs.map((t) => t.sha), ['s1']);
    });

    test('most played first', () {
      final r = index().search('travis', sort: SongSort.mostPlayed);
      expect(r.songs.map((t) => t.sha).take(3), ['s1', 's2', 's3']);
    });

    test('newest first', () {
      final r = index().search('travis', sort: SongSort.newest);
      expect(r.songs.first.sha, 's3');
    });

    test('on this phone only', () {
      final r = index().search('travis', onlyWhere: (t) => t.sha == 's2');
      expect(r.songs.map((t) => t.sha), ['s2']);
      expect(r.records.map((x) => x.id), ['r1']);
    });

    test('a record named exactly is the top result', () {
      final r = index().search('utopia');
      expect(r.top, isA<TopRecord>());
    });

    test('playlists by name', () {
      final r = index().search(
        'gym',
        playlists: const [
          SearchPlaylist(id: 1, name: 'Gym Bangers', count: 30),
          SearchPlaylist(id: 2, name: 'Sleep', count: 12),
        ],
      );
      expect(r.playlists.map((p) => p.id), [1]);
    });
  });

  group('by the words', () {
    final songs = [
      _t(
        'l1',
        'Check On It',
        'Beyoncé',
        lyrics:
            "[00:10.00] I'll let you have it\n"
            "[00:12.00] If you don't go bragging, I'ma let you have it\n"
            '[00:15.00] Swing it',
      ),
      _t(
        'l2',
        'Momma',
        'Kendrick Lamar',
        lyrics: 'I know what I know\nThe day I came\nhome was the day',
      ),
      _t('l3', 'Halo', 'Beyoncé', lyrics: 'Remember those walls I built'),
    ];
    Future<SearchIndex> ready() async {
      final i = SearchIndex(
        tracks: songs,
        releases: const [],
        artists: const [],
      );
      await i.warmLyrics();
      return i;
    }

    test('a line as remembered, apostrophe or not, finds the song', () async {
      final r = (await ready()).search('if you dont go braggin');
      expect(r.lyrics.map((h) => h.track.sha), ['l1']);
      // The line it was found by, as written, timestamps off.
      expect(r.lyrics.single.line, startsWith("If you don't go bragging"));
    });

    test('across a line break, quoting where it starts', () async {
      final r = (await ready()).search('the day i came home');
      expect(r.lyrics.single.track.sha, 'l2');
      expect(r.lyrics.single.line, 'The day I came');
    });

    test('the words of one line in any order', () async {
      final r = (await ready()).search('walls remember');
      expect(r.lyrics.single.track.sha, 'l3');
    });

    test('one short word does not search lyrics', () async {
      expect((await ready()).search('swing').lyrics, isEmpty);
    });

    test('a song found by its name is not repeated under lyrics', () async {
      final r = (await ready()).search('check on it');
      expect(r.songs.map((t) => t.sha), ['l1']);
      expect(r.lyrics, isEmpty);
    });
  });
}
