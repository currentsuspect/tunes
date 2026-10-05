import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/data/database.dart';
import 'package:tunes/core/data/playlist_store.dart';
import 'package:tunes/core/nav/nav_controller.dart';
import 'package:tunes/domain/manifest.dart';
import 'package:tunes/features/playlists/add_songs_sheet.dart';
import 'package:tunes/features/playlists/playlist_page.dart';

import 'widget_test.dart' show FakeTunePlayer;

ManifestTrack _t(String sha, String title, {String artist = 'Swapa'}) =>
    ManifestTrack(
      sha: sha,
      size: 1,
      codec: 'flac',
      sampleRate: 44100,
      channels: 2,
      bitrate: 1000,
      durationMs: 120000,
      title: title,
      artist: artist,
      album: 'Album',
      year: '2026',
      artSha: null,
      releaseId: null,
      trackNumber: null,
      discNumber: null,
      primaryArtist: artist,
      featured: const [],
    );

void main() {
  late TunesDatabase db;
  late PlaylistStore store;
  late FakeTunePlayer player;
  late int id;
  late NavController nav;

  final library = [
    for (var i = 0; i < 30; i++) _t('sha$i', 'Song $i'),
    _t('nugget', 'Nugget'),
  ];

  setUp(() async {
    db = TunesDatabase.forTesting(NativeDatabase.memory());
    store = PlaylistStore(db);
    player = FakeTunePlayer();
    id = await store.create('Goosebumps');
  });

  tearDown(() async {
    store.dispose();
    await db.close();
  });

  Future<void> pump(WidgetTester tester) async {
    final summary = (await store.summaries()).single;
    nav = NavController();
    // Opened the way the app opens it, as a panel in the shell's history.
    nav.openPanel(TunesPanels.playlist(id), () => const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        home: NavScope(
          controller: nav,
          child: PlaylistPage(
            summary: summary,
            store: store,
            player: player,
            tracks: library,
            artUrlFor: (s) => 'http://test/art/$s',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists the songs in order with how many and how long', (
    tester,
  ) async {
    await store.addAll(id, ['sha2', 'sha0', 'sha1']);
    await pump(tester);

    expect(find.text('Goosebumps'), findsOneWidget);
    expect(find.textContaining('3 songs'), findsOneWidget);
    expect(find.textContaining('6 min'), findsOneWidget);
    final y = [
      for (final n in ['Song 2', 'Song 0', 'Song 1'])
        tester.getTopLeft(find.text(n)).dy,
    ];
    expect(y, [...y]..sort());
  });

  testWidgets('shuffle plays everything, in a different order', (tester) async {
    await store.addAll(id, [for (var i = 0; i < 30; i++) 'sha$i']);
    await pump(tester);

    await tester.tap(find.text('Shuffle'));
    await tester.pump();

    // Shuffle is a mode the player shows, not just a one-off random order.
    expect(player.shuffle, isTrue);
    expect(player.queue.map((t) => t.sha).toSet().length, 30);
    expect(
      player.queue.map((t) => t.sha).toList(),
      isNot([for (var i = 0; i < 30; i++) 'sha$i']),
    );
  });

  testWidgets('play starts the list from the top, in order', (tester) async {
    await store.addAll(id, ['sha3', 'sha1', 'sha2']);
    await pump(tester);

    await tester.tap(find.text('Play'));
    await tester.pump();

    expect(player.queue.map((t) => t.sha), ['sha3', 'sha1', 'sha2']);
  });

  testWidgets('swiping a row removes it and Undo puts it back in place', (
    tester,
  ) async {
    await store.addAll(id, ['sha0', 'sha1', 'sha2']);
    await pump(tester);

    await tester.drag(find.text('Song 1'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Song 1'), findsNothing);
    expect(await store.itemsOf(id), ['sha0', 'sha2']);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Song 1'), findsOneWidget);
    expect(await store.itemsOf(id), ['sha0', 'sha1', 'sha2']);
  });

  testWidgets('removing twice in a row takes out the right rows', (
    tester,
  ) async {
    // The old page removed by an index captured when the row was built, which
    // could be stale by the time a quick second swipe finished.
    await store.addAll(id, ['sha0', 'sha1', 'sha2', 'sha3']);
    await pump(tester);

    await tester.drag(find.text('Song 1'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Song 2'), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(await store.itemsOf(id), ['sha0', 'sha3']);
    expect(find.text('Song 0'), findsOneWidget);
    expect(find.text('Song 3'), findsOneWidget);
  });

  testWidgets('dragging the handle reorders and saves the new order', (
    tester,
  ) async {
    await store.addAll(id, ['sha0', 'sha1', 'sha2']);
    await pump(tester);

    await tester.drag(
      find.byIcon(Icons.drag_handle_rounded).first,
      const Offset(0, 160),
    );
    await tester.pumpAndSettle();

    final saved = await store.itemsOf(id);
    expect(saved.first, isNot('sha0'));
    expect(saved.toSet(), {'sha0', 'sha1', 'sha2'});
  });

  testWidgets('the same track twice stays two rows', (tester) async {
    await store.addAll(id, ['sha0', 'sha0', 'sha1']);
    await pump(tester);

    expect(find.text('Song 0'), findsNWidgets(2));
    await tester.drag(find.text('Song 0').first, const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Song 0'), findsOneWidget);
    expect(await store.itemsOf(id), ['sha0', 'sha1']);
  });

  testWidgets('a track that left the library is kept and says so', (
    tester,
  ) async {
    await store.addAll(id, ['sha0', 'gone']);
    await pump(tester);

    expect(find.text('Not in your library'), findsOneWidget);
    expect(find.textContaining('1 not in your library'), findsOneWidget);
    await tester.tap(find.text('Play'));
    await tester.pump();
    expect(player.queue.map((t) => t.sha), ['sha0']);
  });

  testWidgets('deleting leaves through the shell history, not the Navigator', (
    tester,
  ) async {
    // Navigator.pop() here closed the whole shell and left a black screen. The
    // page has to stay mounted, and the history has to step back one panel.
    await store.addAll(id, ['sha0']);
    await pump(tester);
    expect(nav.history.length, 2);

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete playlist'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(nav.history.length, 1);
    expect(find.byType(PlaylistPage), findsOneWidget);
    expect(await store.summaries(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty playlist says what to do', (tester) async {
    await pump(tester);
    expect(find.textContaining('Nothing in here yet'), findsOneWidget);
  });

  testWidgets('Add finds a song in the library and puts it in the list', (
    tester,
  ) async {
    await store.addAll(id, ['sha0']);
    await pump(tester);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'swapa nugget');
    await tester.pumpAndSettle();
    expect(find.text('Nugget'), findsOneWidget);

    await tester.tap(find.text('Nugget'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(await store.itemsOf(id), ['sha0', 'nugget']);
    expect(find.text('Nugget'), findsOneWidget);
  });

  group('matchTracks', () {
    test('every word must match, in any order', () {
      expect(matchTracks(library, 'nugget swapa').map((t) => t.sha), [
        'nugget',
      ]);
      expect(matchTracks(library, 'nugget zzz'), isEmpty);
    });

    test('blank searches match nothing rather than everything', () {
      expect(matchTracks(library, '   '), isEmpty);
    });

    test('is case-blind and capped', () {
      expect(matchTracks(library, 'SONG', limit: 5), hasLength(5));
    });
  });
}
