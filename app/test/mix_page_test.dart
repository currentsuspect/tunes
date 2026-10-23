import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/data/database.dart';
import 'package:tunes/core/data/playlist_store.dart';
import 'package:tunes/core/nav/nav_controller.dart';
import 'package:tunes/domain/manifest.dart';
import 'package:tunes/domain/mixes.dart';
import 'package:tunes/features/home/home_view.dart';
import 'package:tunes/features/mixes/mix_page.dart';

import 'widget_test.dart' show FakeTunePlayer;

ManifestTrack _t(String sha, String title) => ManifestTrack(
  sha: sha,
  size: 1,
  codec: 'flac',
  sampleRate: 44100,
  channels: 2,
  bitrate: 1000,
  durationMs: 180000,
  title: title,
  artist: 'Swapa',
  album: 'A',
  year: '2026',
  artSha: null,
  releaseId: null,
  trackNumber: null,
  discNumber: null,
  primaryArtist: 'Swapa',
  featured: const [],
);

void main() {
  final tracks = [for (var i = 0; i < 20; i++) _t('sha$i', 'Song $i')];
  final mix = Mix(
    id: 'weekday-5',
    title: 'Feel Good Friday',
    note: 'What you play on Fridays, and the songs you love.',
    kind: MixKind.weekday,
    tracks: tracks,
  );

  group('the mix page', () {
    late TunesDatabase db;
    late PlaylistStore store;
    late FakeTunePlayer player;

    setUp(() {
      db = TunesDatabase.forTesting(NativeDatabase.memory());
      store = PlaylistStore(db);
      player = FakeTunePlayer();
    });

    tearDown(() async {
      store.dispose();
      await db.close();
    });

    Future<void> pump(WidgetTester tester, {PlaylistStore? playlists}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NavScope(
            controller: NavController(),
            child: MixPage(
              mix: mix,
              player: player,
              artUrlFor: (s) => 'http://test/art/$s',
              playlists: playlists,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a song swiped away leaves, and Undo brings it back', (
      tester,
    ) async {
      final calls = <(String, bool, bool)>[];
      Mix without(String sha) => Mix(
        id: mix.id,
        title: mix.title,
        note: mix.note,
        kind: mix.kind,
        tracks: [
          for (final t in tracks)
            if (t.sha != sha) t,
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NavScope(
              controller: NavController(),
              child: MixPage(
                mix: mix,
                player: player,
                artUrlFor: (s) => 'http://test/art/$s',
                onRemove: (sha, {required everywhere, required removed}) async {
                  calls.add((sha, everywhere, removed));
                  return removed ? without(sha) : mix;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.text('Song 1'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('Song 1'), findsNothing);
      expect(calls, [('sha1', false, true)]);
      expect(find.textContaining('out of Feel Good Friday'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(calls.last, ('sha1', false, false));
      expect(find.text('Song 1'), findsOneWidget);
    });

    testWidgets('held, a song can be kept out of every mix', (tester) async {
      final calls = <(String, bool, bool)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NavScope(
              controller: NavController(),
              child: MixPage(
                mix: mix,
                player: player,
                artUrlFor: (s) => 'http://test/art/$s',
                onRemove: (sha, {required everywhere, required removed}) async {
                  calls.add((sha, everywhere, removed));
                  return null;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Song 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep out of all my mixes'));
      await tester.pumpAndSettle();
      expect(calls, [('sha2', true, true)]);
      expect(find.text('Song 2'), findsNothing);
    });

    testWidgets('says what it is, why, and how big', (tester) async {
      await pump(tester, playlists: store);
      expect(find.text('Feel Good Friday'), findsOneWidget);
      expect(find.text('MADE FOR YOU'), findsOneWidget);
      expect(find.textContaining('What you play on Fridays'), findsOneWidget);
      expect(find.textContaining('20 songs'), findsOneWidget);
      expect(find.text('Song 0'), findsOneWidget);
    });

    testWidgets('play starts it from the top, in order', (tester) async {
      await pump(tester, playlists: store);
      await tester.tap(find.text('Play'));
      await tester.pump();
      expect(player.queue.map((t) => t.sha), [for (final t in tracks) t.sha]);
    });

    testWidgets('shuffle turns the mode on', (tester) async {
      await pump(tester, playlists: store);
      await tester.tap(find.text('Shuffle'));
      await tester.pump();
      expect(player.shuffle, isTrue);
      expect(player.queue.length, 20);
    });

    testWidgets('tapping a song plays the mix from that song', (tester) async {
      await pump(tester, playlists: store);
      await tester.tap(find.text('Song 3'));
      await tester.pump();
      expect(player.current?.sha, 'sha3');
      expect(player.queue.length, 20);
    });

    testWidgets('save as playlist keeps it, once', (tester) async {
      await pump(tester, playlists: store);
      await tester.tap(find.text('Save as playlist'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();

      final lists = await tester.runAsync(() => store.summaries());
      expect(lists!.single.name, 'Feel Good Friday');
      final items = await tester.runAsync(() => store.itemsOf(lists.single.id));
      expect(items, [for (final t in tracks) t.sha]);

      // Now it says so, and cannot be saved twice.
      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Save as playlist'), findsNothing);
    });

    testWidgets('with nowhere to save to, there is no save button', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('Save as playlist'), findsNothing);
    });
  });

  group('Home', () {
    final manifest = TunesManifest(tracks: tracks, releases: const []);

    Future<void> pump(
      WidgetTester tester, {
      List<Mix> mixes = const [],
      List<UnheardAlbum> unheard = const [],
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeView(
              manifest: manifest,
              missingAlbums: const [],
              onRepeat: const [],
              listenAgain: const [],
              mixes: mixes,
              unheard: unheard,
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
    }

    testWidgets('shows Made for you when there is a mix', (tester) async {
      await pump(tester, mixes: [mix]);
      expect(find.text('Made for you'), findsOneWidget);
      expect(find.text('Feel Good Friday'), findsOneWidget);
      expect(find.text('20 songs'), findsOneWidget);
    });

    testWidgets('and says nothing at all when there is not', (tester) async {
      await pump(tester);
      expect(find.text('Made for you'), findsNothing);
      expect(find.text('Unheard in your library'), findsNothing);
    });

    testWidgets('shows records you never opened, with why', (tester) async {
      final r = ManifestRelease(
        id: 'r1',
        title: 'Hidden Album',
        artist: 'Swapa',
        year: '2026',
        artSha: null,
        type: 'album',
        totalTracks: 8,
        trackShas: const ['a', 'b', 'c'],
      );
      await pump(
        tester,
        unheard: [
          UnheardAlbum(
            release: r,
            songs: 8,
            why: 'Added 3 days ago, not played',
          ),
        ],
      );
      expect(find.text('Unheard in your library'), findsOneWidget);
      expect(find.text('Hidden Album'), findsOneWidget);
      expect(find.text('Added 3 days ago, not played'), findsOneWidget);
    });

    testWidgets('tapping a mix opens it', (tester) async {
      Mix? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeView(
              manifest: manifest,
              missingAlbums: const [],
              onRepeat: const [],
              listenAgain: const [],
              mixes: [mix],
              onMixTap: (m) => opened = m,
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
      await tester.tap(find.text('Feel Good Friday'));
      expect(opened?.id, 'weekday-5');
    });
  });
}
