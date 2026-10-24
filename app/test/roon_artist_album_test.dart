import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/data/database.dart';
import 'package:tunes/core/data/download_store.dart';
import 'package:tunes/core/data/gets.dart';
import 'package:tunes/core/data/manifest_store.dart';
import 'package:tunes/core/nav/nav_controller.dart';
import 'package:tunes/core/net/tunes_client.dart';
import 'package:tunes/domain/about.dart';
import 'package:tunes/domain/discography.dart';
import 'package:tunes/domain/manifest.dart';
import 'package:tunes/domain/soulseek.dart';
import 'package:tunes/features/album/album_page.dart';
import 'package:tunes/features/artist/artist_page.dart';
import 'package:tunes/features/song/about_nav.dart';

import 'widget_test.dart' show FakeTunePlayer;

/// The box, answering as it does for Yeat and ADL (24 Oct, cut down).
class _Box extends TunesClient {
  _Box() : super('http://test');

  @override
  Future<List<TracklistEntry>?> tracklist(String releaseId) async => null;

  // The catalogue check is not what these tests are about.
  @override
  Future<ArtistDiscography> discography(String artist) async =>
      throw const SocketException('not here');

  @override
  Future<AlbumAbout?> aboutAlbum(String releaseId) async => AlbumAbout.fromJson(
    {
      'url': 'https://genius.com/albums/Yeat/Adl',
      'description': 'ADL is the sixth studio album from American rapper Yeat.',
      'releaseDate': '2026-03-27',
      'credits': [
        {
          'role': 'Producers',
          'names': ['BNYX®', 'Bangs (Producer)'],
        },
        {
          'role': 'Label',
          'names': ['Field Trip Recordings'],
        },
        {
          'role': 'Distributor',
          'names': ['Universal Music Group'],
        },
      ],
    },
  );

  @override
  Future<({ArtistAbout? artist, List<Collaborator> people})?> aboutArtist(
    String name,
  ) async => (
    artist: ArtistAbout.fromJson({
      'url': 'https://genius.com/artists/Yeat',
      'description':
          'Noah Olivier Smith, better known as Yeat, is an American rapper.',
      'alternateNames': ['Kranky Kranky', 'Lil Yeat'],
    }),
    people: [
      Collaborator.fromJson({
        'name': 'BNYX®',
        'songs': 2,
        'roles': ['produced'],
      }),
    ],
  );
}

ManifestTrack _t(String c, String title, String album, String release) =>
    ManifestTrack(
      sha: c * 64,
      size: 1,
      codec: 'flac',
      sampleRate: 44100,
      channels: 2,
      bitrate: 1000,
      durationMs: 157000,
      title: title,
      artist: 'Yeat',
      album: album,
      year: '2026',
      artSha: null,
      releaseId: release,
      trackNumber: 4,
      discNumber: 1,
      primaryArtist: 'Yeat',
      featured: const [],
    );

ManifestRelease _r(String id, String title, List<String> shas, int total) =>
    ManifestRelease(
      id: id,
      title: title,
      artist: 'Yeat',
      year: '2026',
      artSha: null,
      type: 'album',
      totalTracks: total,
      trackShas: shas,
      tracks: const [],
    );

void main() {
  late Directory tmp;
  late DownloadStore store;
  late TunesDatabase db;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('roon');
    store = DownloadStore(tmp);
    db = TunesDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  final griddle = _t('a', 'Griddlë', 'ADL (Deluxe)', 'deluxe');
  final other = _t('b', 'Lose Control', 'ADL', 'std');
  final deluxe = _r('deluxe', 'ADL (Deluxe)', [griddle.sha], 22);
  final standard = _r('std', 'ADL', [other.sha], 21);
  final manifest = TunesManifest(
    tracks: [griddle, other],
    releases: [deluxe, standard],
  );
  final opened = <String>[];

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1200, 4800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final gets = GetsController(client: _Box(), onLanded: () {});
    addTearDown(gets.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NavScope(
            controller: NavController(),
            child: GetsScope(
              gets: gets,
              child: AboutNav(
                openSong: (_) {},
                openPerson: opened.add,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an album shows its other edition, its story and its makers', (
    tester,
  ) async {
    await pump(
      tester,
      AlbumPage(
        release: deluxe,
        manifest: manifest,
        player: FakeTunePlayer(),
        store: store,
        downloading: const {},
        onDownload: (_) {},
        offline: false,
        artUrlFor: (s) => s,
        manifestStore: ManifestStore(db),
      ),
    );
    expect(find.text('EDITIONS'), findsOneWidget);
    expect(find.text('21 songs · you have 1'), findsOneWidget);
    expect(find.textContaining('sixth studio album'), findsOneWidget);
    expect(find.text('Produced by'), findsOneWidget);
    // The distributor is paperwork, not a maker.
    expect(find.text('Universal Music Group'), findsNothing);
    await tester.tap(find.text('Bangs'));
    expect(opened.last, 'Bangs');
  });

  testWidgets('an artist shows their bio, other names and the people around', (
    tester,
  ) async {
    await pump(
      tester,
      ArtistPage(
        artist: 'Yeat',
        manifest: manifest,
        client: _Box(),
        player: FakeTunePlayer(),
        store: store,
        downloading: const {},
        onDownload: (_) {},
        offline: false,
        artUrlFor: (s) => s,
        manifestStore: ManifestStore(db),
      ),
    );
    expect(find.textContaining('better known as Yeat'), findsOneWidget);
    expect(find.textContaining('Kranky Kranky'), findsOneWidget);
    // Approved v2 order: top songs, discography, collabs, then the bio.
    double y(String t) => tester.getTopLeft(find.text(t).first).dy;
    expect(find.text('Top songs'), findsOneWidget);
    expect(find.text('Discography'), findsOneWidget);
    expect(find.text('Collabs'), findsOneWidget);
    expect(find.text('About Yeat'), findsOneWidget);
    expect(y('Top songs'), lessThan(y('Discography')));
    expect(y('Discography'), lessThan(y('Collabs')));
    expect(y('Collabs'), lessThan(y('About Yeat')));
    // Both editions held are one album, the other named under it.
    expect(find.text('Albums · 1'), findsOneWidget);
    expect(find.textContaining('also Deluxe'), findsOneWidget);
    // A producer from the credits opens their page.
    await tester.tap(find.text('BNYX®  2'));
    expect(opened.last, 'BNYX®');
  });
}
