import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/data/database.dart';
import 'package:tunes/core/data/download_store.dart';
import 'package:tunes/core/data/manifest_store.dart';
import 'package:tunes/core/nav/nav_controller.dart';
import 'package:tunes/core/net/tunes_client.dart';
import 'package:tunes/domain/manifest.dart';
import 'package:tunes/features/album/album_page.dart';
import 'package:tunes/features/home/home_view.dart';
import 'package:tunes/features/library/library_view.dart';
import 'package:tunes/features/search/search_view.dart';

import 'widget_test.dart' show FakeTunePlayer;

ManifestTrack _t(String sha, String title, {String? releaseId}) =>
    ManifestTrack(
      sha: sha,
      size: 1,
      codec: 'flac',
      sampleRate: 44100,
      channels: 2,
      bitrate: 1000,
      durationMs: 120000,
      title: title,
      artist: 'Swapa',
      album: 'A',
      year: '2026',
      artSha: null,
      releaseId: releaseId,
      trackNumber: null,
      discNumber: null,
      primaryArtist: 'Swapa',
      featured: const [],
    );

ManifestRelease _r(
  String id,
  String title,
  String? year,
  List<String> shas, {
  int? total,
}) => ManifestRelease(
  id: id,
  title: title,
  artist: 'Swapa',
  year: year,
  artSha: null,
  type: 'album',
  totalTracks: total,
  trackShas: shas,
);

void main() {
  late Directory tmp;
  late DownloadStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('offline');
    store = DownloadStore(tmp);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<void> hold(WidgetTester tester, String sha) async {
    await tester.runAsync(() => store.add(sha, '${tmp.path}/$sha'));
  }

  group('the library without a connection', () {
    final tracks = [_t('a', 'One'), _t('b', 'Two'), _t('c', 'Three')];
    final manifest = TunesManifest(
      tracks: tracks,
      releases: [
        _r('r1', 'Both', '2024', ['a', 'b'], total: 12),
        _r('r2', 'Neither', '2024', ['c'], total: 1),
      ],
    );

    test('is only the songs held, and the records with any of them left', () {
      final off = manifest.onlyHeld((s) => s == 'a');
      expect(off.tracks.map((t) => t.sha), ['a']);
      expect(off.releases.map((r) => r.id), ['r1']);
      expect(off.releases.single.trackShas, ['a']);
    });

    test('says nothing about what is missing, only what is here', () {
      final off = manifest.onlyHeld((s) => s == 'a');
      // "1 of 12, 11 missing" is true of the library, not of the phone.
      expect(off.releases.single.totalTracks, isNull);
    });

    test('is empty when nothing is held, and whole when everything is', () {
      expect(manifest.onlyHeld((_) => false).tracks, isEmpty);
      expect(manifest.onlyHeld((_) => false).releases, isEmpty);
      expect(manifest.onlyHeld((_) => true).tracks.length, 3);
    });

    test('does not change the library it was cut from', () {
      manifest.onlyHeld((s) => s == 'a');
      expect(manifest.tracks.length, 3);
      expect(manifest.releases.first.trackShas, ['a', 'b']);
    });
  });

  group('Released this year', () {
    Future<void> pump(
      WidgetTester tester,
      List<ManifestRelease> releases,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeView(
              manifest: TunesManifest(
                tracks: [_t('a', 'One')],
                releases: releases,
              ),
              missingAlbums: const [],
              onRepeat: const [],
              listenAgain: const [],
              onMixTap: (_) {},
              onArtistTap: (_) {},
              onAlbumTap: (_) {},
              onPlay: (_, _) {},
              artUrlFor: (s) => 'http://test/art/$s',
              onRefresh: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The page is a long list that builds what it has reached, so scroll to
      // the section before looking for it.
      final section = find.text('Released this year');
      for (var i = 0; i < 20 && section.evaluate().isEmpty; i++) {
        await tester.dragFrom(const Offset(400, 400), const Offset(0, -300));
        await tester.pumpAndSettle();
      }
    }

    final year = DateTime.now().year;

    // Only inside the section: the same records are also in the Albums rail.
    Finder inSection(String text) => find.descendant(
      of: find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_ReleasedThisYear',
      ),
      matching: find.text(text),
    );

    testWidgets('counts a record by the year in its full date', (tester) async {
      // The box sends a full date for almost everything. Comparing the whole
      // string to the year matched only the few stored as a bare year.
      await pump(tester, [
        _r('a', 'Spring Record', '$year-03-14', ['x']),
        _r('b', 'Bare Year Record', '$year', ['y']),
        _r('c', 'Old Record', '${year - 1}-12-01', ['z']),
      ]);
      expect(find.text('Released this year'), findsOneWidget);
      expect(inSection('Spring Record'), findsOneWidget);
      expect(inSection('Bare Year Record'), findsOneWidget);
      expect(inSection('Old Record'), findsNothing);
    });

    testWidgets('newest first, with the day it came out', (tester) async {
      await pump(tester, [
        _r('a', 'March One', '$year-03-14', ['x']),
        _r('b', 'September One', '$year-09-08', ['y']),
      ]);
      expect(find.text('Sep 8'), findsOneWidget);
      expect(find.text('Mar 14'), findsOneWidget);
      final newer = tester.getTopLeft(inSection('September One')).dx;
      final older = tester.getTopLeft(inSection('March One')).dx;
      expect(newer, lessThan(older));
    });

    testWidgets('says how many, not a fixed few', (tester) async {
      await pump(tester, [
        for (var i = 0; i < 9; i++)
          _r('r$i', 'Record $i', '$year-0${(i % 9) + 1}-10', ['s$i']),
      ]);
      expect(find.textContaining('9 new'), findsOneWidget);
    });

    testWidgets('is absent when nothing came out this year', (tester) async {
      await pump(tester, [
        _r('a', 'Old', '${year - 2}-01-01', ['x']),
      ]);
      expect(find.text('Released this year'), findsNothing);
    });
  });

  group('Library, on this phone', () {
    final tracks = [_t('a', 'Downloaded Song'), _t('b', 'Streamed Song')];

    Future<void> pump(WidgetTester tester, {bool offline = false}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryView(
              tracks: tracks,
              releases: const [],
              filter: '',
              player: FakeTunePlayer(),
              store: store,
              downloading: const {},
              onDownload: (_) {},
              offline: offline,
              artUrlFor: (s) => 'http://test/art/$s',
              onArtistTap: (_) {},
              onAlbumTap: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows everything, then only what is held', (tester) async {
      await hold(tester, 'a');
      await pump(tester);
      expect(find.text('Downloaded Song'), findsOneWidget);
      expect(find.text('Streamed Song'), findsOneWidget);

      await tester.tap(find.text('On this phone'));
      await tester.pumpAndSettle();
      expect(find.text('Downloaded Song'), findsOneWidget);
      expect(find.text('Streamed Song'), findsNothing);
      expect(find.text('1 song'), findsOneWidget);
    });

    testWidgets('counts what is held on the chip', (tester) async {
      await hold(tester, 'a');
      await hold(tester, 'b');
      await pump(tester);
      expect(find.text('2'), findsWidgets);
    });

    testWidgets('says what to do when nothing is held', (tester) async {
      await pump(tester);
      await tester.tap(find.text('On this phone'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing on this phone yet'), findsOneWidget);
    });

    testWidgets('offline there is no choice to make', (tester) async {
      await pump(tester, offline: true);
      expect(find.text('On this phone'), findsNothing);
    });
  });

  group('Search, offline', () {
    testWidgets('says what it is searching, and what a miss means', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchView(
              tracks: [_t('a', 'Downloaded Song')],
              releases: const [],
              client: TunesClient('http://test'),
              player: FakeTunePlayer(),
              store: store,
              downloading: const {},
              onDownload: (_) {},
              offline: true,
              artUrlFor: (s) => 'http://test/art/$s',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Searching what is on this phone'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Nothing downloaded to this phone'),
        findsOneWidget,
      );
    });
  });

  group('the album facts', () {
    late TunesDatabase db;

    setUp(() => db = TunesDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> pump(
      WidgetTester tester,
      ManifestRelease release,
      List<ManifestTrack> tracks,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NavScope(
            controller: NavController(),
            child: AlbumPage(
              release: release,
              manifest: TunesManifest(tracks: tracks, releases: [release]),
              player: FakeTunePlayer(),
              store: store,
              downloading: const {},
              onDownload: (_) {},
              offline: false,
              artUrlFor: (s) => 'http://test/art/$s',
              manifestStore: ManifestStore(db),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a complete record says so with a mark, and how long', (
      tester,
    ) async {
      final tracks = [for (var i = 0; i < 4; i++) _t('t$i', 'Song $i')];
      await pump(
        tester,
        _r('r', 'Whole', '2016-05-01', [
          for (final t in tracks) t.sha,
        ], total: 4),
        tracks,
      );
      expect(find.text('ALBUM  ·  2016'), findsOneWidget);
      expect(find.text('4 songs'), findsOneWidget);
      expect(find.text('8 min'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsWidgets);
      expect(find.textContaining('missing'), findsNothing);
    });

    testWidgets(
      'a partial record says how many of how many, and what is missing',
      (tester) async {
        final tracks = [for (var i = 0; i < 3; i++) _t('t$i', 'Song $i')];
        await pump(
          tester,
          _r('r', 'Part', '2016', [for (final t in tracks) t.sha], total: 10),
          tracks,
        );
        expect(find.text('3 of 10 songs'), findsOneWidget);
        expect(find.text('7 missing'), findsOneWidget);
      },
    );

    testWidgets(
      'a record holding more than its total claims nothing about it',
      (tester) async {
        final tracks = [for (var i = 0; i < 3; i++) _t('t$i', 'Song $i')];
        await pump(
          tester,
          _r('r', 'Over', '2016', [for (final t in tracks) t.sha], total: 2),
          tracks,
        );
        expect(find.text('3 songs'), findsOneWidget);
        expect(find.textContaining('missing'), findsNothing);
      },
    );
  });
}
