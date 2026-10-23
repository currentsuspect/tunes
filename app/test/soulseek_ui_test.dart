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
import 'package:tunes/domain/manifest.dart';
import 'package:tunes/domain/soulseek.dart';
import 'package:tunes/features/album/album_page.dart';
import 'package:tunes/features/search/search_view.dart';

import 'widget_test.dart' show FakeTunePlayer;

class _Box extends TunesClient {
  _Box() : super('http://test');

  List<TracklistEntry>? list;
  List<FoundSong> found = const [];
  final gets = <(String, String, String?)>[];
  final completes = <String>[];
  int searches = 0;

  @override
  Future<SearchResults> search(String q) async =>
      const SearchResults(tracks: [], releases: [], artists: []);

  @override
  Future<List<TracklistEntry>?> tracklist(String releaseId) async => list;

  @override
  Future<List<FoundSong>> soulseekSearch(String q) async {
    searches++;
    return found;
  }

  @override
  Future<GetJob> soulseekGet({
    required String title,
    required String artist,
    String? album,
    int? durationMs,
    String? release,
    FoundSong? copy,
  }) async {
    gets.add((title, artist, copy?.username));
    return GetJob(
      id: 'j$title',
      title: title,
      artist: artist,
      release: release,
      state: GetState.downloading,
      progress: 0.4,
    );
  }

  @override
  Future<List<GetJob>> soulseekComplete(String releaseId) async {
    completes.add(releaseId);
    return [
      for (final e in list ?? const <TracklistEntry>[])
        if (e.have == null)
          GetJob(
            id: 'c${e.title}',
            title: e.title,
            artist: e.artist,
            release: releaseId,
            state: GetState.queued,
          ),
    ];
  }

  @override
  Future<List<GetJob>> soulseekJobs() async => const [];
}

ManifestTrack _t(String sha, String title, int n) => ManifestTrack(
  sha: sha,
  size: 1,
  codec: 'flac',
  sampleRate: 44100,
  channels: 2,
  bitrate: 1000,
  durationMs: 120000,
  title: title,
  artist: 'Travis Scott',
  album: 'ASTROWORLD',
  year: '2018',
  artSha: null,
  releaseId: 'r1',
  trackNumber: n,
  discNumber: 1,
  primaryArtist: 'Travis Scott',
  featured: const [],
);

void main() {
  late Directory tmp;
  late DownloadStore store;
  late TunesDatabase db;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('slsk-ui');
    store = DownloadStore(tmp);
    db = TunesDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  final owned = [_t('a', 'STARGAZING', 1), _t('c', 'SICKO MODE', 3)];
  final release = ManifestRelease(
    id: 'r1',
    title: 'ASTROWORLD',
    artist: 'Travis Scott',
    year: '2018',
    artSha: null,
    type: 'album',
    totalTracks: 4,
    trackShas: const ['a', 'c'],
  );

  Future<GetsController> pump(
    WidgetTester tester,
    _Box box,
    Widget child,
  ) async {
    final gets = GetsController(client: box, onLanded: () {});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NavScope(
            controller: NavController(),
            child: GetsScope(gets: gets, child: child),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return gets;
  }

  Future<void> done(WidgetTester tester, GetsController gets) async {
    await tester.pumpWidget(const SizedBox());
    gets.dispose();
  }

  testWidgets('an album shows its missing songs in place, greyed, to get', (
    tester,
  ) async {
    // Tall enough for the whole tracklist: no scrolling under the top bar.
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final box = _Box()
      ..list = const [
        TracklistEntry(
          title: 'STARGAZING',
          artist: 'Travis Scott',
          trackNumber: 1,
          have: 'a',
        ),
        TracklistEntry(
          title: 'CAROUSEL',
          artist: 'Travis Scott',
          trackNumber: 2,
          durationMs: 180000,
        ),
        TracklistEntry(
          title: 'SICKO MODE',
          artist: 'Travis Scott',
          trackNumber: 3,
          have: 'c',
        ),
        TracklistEntry(
          title: 'R.I.P. SCREW',
          artist: 'Travis Scott',
          trackNumber: 4,
        ),
      ];
    final gets = await pump(
      tester,
      box,
      AlbumPage(
        release: release,
        manifest: TunesManifest(tracks: owned, releases: [release]),
        player: FakeTunePlayer(),
        store: store,
        downloading: const {},
        onDownload: (_) {},
        offline: false,
        artUrlFor: (s) => 'http://test/art/$s',
        manifestStore: ManifestStore(db),
      ),
    );

    expect(find.text('CAROUSEL'), findsOneWidget);
    expect(find.text('R.I.P. SCREW'), findsOneWidget);
    expect(find.text('not in your library'), findsNWidgets(2));
    expect(find.text('2 songs not in your library yet'), findsOneWidget);
    // In order: the missing second song sits between the first and third.
    double y(String t) => tester.getTopLeft(find.text(t)).dy;
    expect(y('STARGAZING') < y('CAROUSEL'), isTrue);
    expect(y('CAROUSEL') < y('SICKO MODE'), isTrue);

    await tester.tap(find.text('Get').first);
    await tester.pump();
    expect(box.gets.single.$1, 'CAROUSEL');
    expect(find.text('Get'), findsOneWidget);

    // One coming; the rest can still be asked for together.
    expect(find.text('Getting 1 of the 2 missing'), findsOneWidget);
    await tester.tap(find.text('Get the rest'));
    await tester.pump();
    expect(box.completes, ['r1']);
    await done(tester, gets);
  });

  testWidgets('offline, the album is the songs it has, as before', (
    tester,
  ) async {
    final box = _Box()..list = const [];
    final gets = await pump(
      tester,
      box,
      AlbumPage(
        release: release,
        manifest: TunesManifest(tracks: owned, releases: [release]),
        player: FakeTunePlayer(),
        store: store,
        downloading: const {},
        onDownload: (_) {},
        offline: true,
        artUrlFor: (s) => 'http://test/art/$s',
        manifestStore: ManifestStore(db),
      ),
    );
    expect(find.text('not in your library'), findsNothing);
    expect(find.text('STARGAZING'), findsOneWidget);
    await done(tester, gets);
  });

  testWidgets('nothing here by that name: Soulseek is asked, and Get works', (
    tester,
  ) async {
    final box = _Box()
      ..found = const [
        FoundSong(
          key: 'k',
          title: 'SICKO MODE',
          artist: 'Travis Scott',
          album: 'ASTROWORLD',
          format: 'FLAC',
          lossless: true,
          peers: 46,
          username: 'peer1',
          filename: 'x/SICKO MODE.flac',
          sizeBytes: 30000000,
          durationMs: 312000,
        ),
      ];
    final gets = await pump(
      tester,
      box,
      SearchView(
        tracks: owned,
        releases: [release],
        client: box,
        player: FakeTunePlayer(),
        store: store,
        downloading: const {},
        onDownload: (_) {},
        offline: false,
        artUrlFor: (s) => 'http://test/art/$s',
      ),
    );
    await tester.enterText(find.byType(TextField), 'goosebumps');
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    expect(box.searches, 1);
    expect(find.text('From Soulseek'), findsOneWidget);
    expect(find.text('FLAC'), findsOneWidget);
    expect(find.text('46 people have it'), findsOneWidget);

    await tester.tap(find.text('Get'));
    await tester.pump();
    expect(box.gets.single, ('SICKO MODE', 'Travis Scott', 'peer1'));
    expect(find.textContaining('40%'), findsOneWidget);
    await done(tester, gets);
  });

  testWidgets('with library results, Soulseek waits to be asked', (
    tester,
  ) async {
    final box = _Box();
    final gets = await pump(
      tester,
      box,
      SearchView(
        tracks: owned,
        releases: [release],
        client: box,
        player: FakeTunePlayer(),
        store: store,
        downloading: const {},
        onDownload: (_) {},
        offline: false,
        artUrlFor: (s) => 'http://test/art/$s',
      ),
    );
    await tester.enterText(find.byType(TextField), 'stargazing');
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    expect(box.searches, 0);
    expect(find.textContaining('on Soulseek'), findsOneWidget);
    await done(tester, gets);
  });
}
