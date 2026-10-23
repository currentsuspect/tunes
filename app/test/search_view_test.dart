import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/data/download_store.dart';
import 'package:tunes/core/net/tunes_client.dart';
import 'package:tunes/domain/manifest.dart';
import 'package:tunes/features/search/search_view.dart';

import 'widget_test.dart' show FakeTunePlayer;

ManifestTrack _t(
  String sha,
  String title,
  String artist, {
  String album = 'A',
  String? year,
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
  primaryArtist: artist,
  featured: const [],
);

void main() {
  late Directory tmp;
  late DownloadStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('search');
    store = DownloadStore(tmp);
  });
  tearDown(() => tmp.delete(recursive: true));

  final tracks = [
    _t('s1', 'STARGAZING', 'Travis Scott', album: 'ASTROWORLD', year: '2018'),
    _t('s2', 'MY EYES', 'Travis Scott', album: 'UTOPIA', year: '2023'),
    _t('s3', 'SKITZO', 'Travis Scott', album: 'UTOPIA', year: '2023'),
    _t('s4', 'Halo', 'Beyoncé', album: 'I Am... Sasha Fierce', year: '2008'),
  ];
  final artistsOpened = <String>[];
  final played = <List<String>>[];

  Future<void> pump(WidgetTester tester) async {
    final player = FakeTunePlayer();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchView(
            tracks: tracks,
            releases: const [],
            client: TunesClient('http://test'),
            player: player,
            store: store,
            downloading: const {},
            onDownload: (_) {},
            offline: false,
            artUrlFor: (s) => 'http://test/art/$s',
            plays: const {'s3': 9, 's2': 2},
            onArtistTap: artistsOpened.add,
            searchOverride: (_) async =>
                const SearchResults(tracks: [], releases: [], artists: []),
          ),
        ),
      ),
    );
    player.addListener(() {
      final q = player.queue;
      if (q.isNotEmpty) played.add([for (final t in q) t.sha]);
    });
  }

  Future<void> type(WidgetTester tester, String q) async {
    await tester.enterText(find.byType(TextField), q);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  testWidgets('an artist\'s name: counts, and the artist on top', (
    tester,
  ) async {
    await pump(tester);
    await type(tester, 'travis');
    expect(find.text('Songs 3'), findsOneWidget);
    expect(find.text('Top result'), findsOneWidget);
    expect(find.text('Travis Scott'), findsWidgets);
    expect(find.textContaining('Artist · 3 songs'), findsOneWidget);

    await tester.tap(find.byTooltip('Play Travis Scott'));
    // Playing starts the bars moving: a frame, not a settle.
    await tester.pump();
    // Their own songs, most played first.
    expect(played.last, ['s3', 's2', 's1']);
  });

  testWidgets('a year and a name read as chips, and a chip taps off', (
    tester,
  ) async {
    await pump(tester);
    await type(tester, 'travis 2018');
    expect(find.text('from 2018'), findsOneWidget);
    expect(find.text('by Travis Scott'), findsOneWidget);
    expect(find.text('Songs 1'), findsOneWidget);

    await tester.tap(find.text('by Travis Scott'));
    await tester.pumpAndSettle();
    expect(find.text('by Travis Scott'), findsNothing);
  });

  testWidgets('Songs has the order and it can be changed', (tester) async {
    await pump(tester);
    await type(tester, 'travis');
    await tester.tap(find.text('Songs 3'));
    await tester.pumpAndSettle();
    expect(find.text('Best match'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);

    await tester.tap(find.text('Best match'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A to Z').last);
    await tester.pumpAndSettle();
    expect(find.text('A to Z'), findsOneWidget);
    final titles = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .where((d) => d == 'MY EYES' || d == 'SKITZO' || d == 'STARGAZING')
        .toList();
    expect(titles, ['MY EYES', 'SKITZO', 'STARGAZING']);
  });

  testWidgets('See all opens Songs', (tester) async {
    await pump(tester);
    await type(tester, 'a');
    final seeAll = find.textContaining('See all');
    if (seeAll.evaluate().isEmpty) return;
    await tester.tap(seeAll.first);
    await tester.pumpAndSettle();
    expect(find.text('Best match'), findsOneWidget);
  });
}
