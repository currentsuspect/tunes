import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/data/download_manager.dart';
import 'package:tunes/core/data/download_store.dart';
import 'package:tunes/core/net/tunes_client.dart';
import 'package:tunes/core/ui/download_button.dart';
import 'package:tunes/core/ui/downloads_bar.dart';
import 'package:tunes/core/ui/playing_bars.dart';
import 'package:tunes/domain/manifest.dart';
import 'package:tunes/features/downloads/downloads_sheet.dart';

class _GatedClient extends TunesClient {
  _GatedClient() : super('http://test');

  final Map<String, Completer<void>> gate = {};
  final Map<String, void Function(int, int)> progressOf = {};

  @override
  Future<void> downloadTrack(
    String sha,
    String path, {
    void Function(int received, int total)? onProgress,
    CancelSignal? cancel,
  }) async {
    if (onProgress != null) progressOf[sha] = onProgress;
    final c = Completer<void>();
    gate[sha] = c;
    await c.future;
    if (cancel != null && cancel.isCancelled) throw const DownloadCancelled();
    await File(path).parent.create(recursive: true);
    await File(path).writeAsBytes(const [1, 2, 3]);
  }
}

ManifestTrack _t(String sha, String title) => ManifestTrack(
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
  releaseId: null,
  trackNumber: null,
  discNumber: null,
  primaryArtist: 'Swapa',
  featured: const [],
);

void main() {
  late Directory tmp;
  late DownloadStore store;
  late _GatedClient client;
  late DownloadManager manager;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('dlbtn');
    store = DownloadStore(tmp);
    client = _GatedClient();
    manager = DownloadManager(client: client, store: store, maxConcurrent: 2);
  });

  tearDown(() async {
    manager.dispose();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// Real time for the file writes a download makes, then the fake clock for
  /// the animation that follows, a few times so each hand-off completes.
  Future<void> turn(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  // The parent is built once and never again: it hands the button nothing that
  // changes. The album page did exactly this with a snapshot flag, and nothing
  // moved while a song downloaded.
  Widget harness(Widget child) => MaterialApp(
    home: Scaffold(
      body: DownloadScope(
        manager: manager,
        child: Center(child: child),
      ),
    ),
  );

  testWidgets('shows every stage under a parent that never rebuilds', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        DownloadButton(
          sha: 'a',
          title: 'Song',
          store: store,
          onDownload: () => manager.enqueue('a'),
        ),
      ),
    );
    // Idle: an arrow.
    expect(find.byIcon(Icons.arrow_circle_down_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_circle_down_outlined));
    await tester.pump();
    await turn(tester);
    // Running with no size yet: a turning ring.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .value,
      isNull,
    );

    client.progressOf['a']!(50, 100);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 400));
    final ring = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(ring.value, closeTo(0.5, 0.05));

    client.gate['a']!.complete();
    await turn(tester);
    await turn(tester);
    // On the phone: a tick.
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a second song waits its turn and says so', (tester) async {
    final m = DownloadManager(client: client, store: store, maxConcurrent: 1);
    addTearDown(m.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DownloadScope(
            manager: m,
            child: Column(
              children: [
                DownloadButton(
                  sha: 'one',
                  title: 'One',
                  store: store,
                  onDownload: () => m.enqueue('one'),
                ),
                DownloadButton(
                  sha: 'two',
                  title: 'Two',
                  store: store,
                  onDownload: () => m.enqueue('two'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    m.enqueue('one');
    m.enqueue('two');
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 400));

    // One running ring; the other is the waiting arrow, not a second ring.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.arrow_circle_down_outlined), findsOneWidget);
    client.gate['one']!.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('a failure offers a retry in the warning colour', (tester) async {
    await tester.pumpWidget(
      harness(
        DownloadButton(
          sha: 'a',
          title: 'Song',
          store: store,
          onDownload: () => manager.enqueue('a'),
        ),
      ),
    );
    manager.enqueue('a');
    await tester.pump();
    await turn(tester);
    client.gate['a']!.completeError(Exception('boom'));
    await turn(tester);

    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(manager.failedCount, 1);
  });

  testWidgets('the removed note goes away by itself', (tester) async {
    await tester.pumpWidget(
      harness(
        DownloadButton(
          sha: 'a',
          title: 'Song',
          store: store,
          onDownload: () {},
        ),
      ),
    );
    manager.enqueue('a');
    await turn(tester);
    client.gate['a']!.complete();
    await turn(tester);
    await turn(tester);
    expect(store.pathFor('a'), isNotNull);

    await tester.tap(find.byIcon(Icons.check_rounded));
    await turn(tester);
    await turn(tester);
    expect(find.text('Removed "Song" from this phone'), findsOneWidget);

    // A snackbar with an action stays until dismissed unless told not to.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Removed "Song" from this phone'), findsNothing);
  });

  testWidgets('offline, an idle song cannot be downloaded', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      harness(
        DownloadButton(
          sha: 'a',
          title: 'Song',
          store: store,
          offline: true,
          onDownload: () => taps += 1,
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.arrow_circle_down_outlined));
    expect(taps, 0);
  });

  group('the downloads bar', () {
    testWidgets('is absent when nothing is downloading', (tester) async {
      await tester.pumpWidget(
        harness(DownloadsBar(manager: manager, onTap: () {})),
      );
      expect(find.textContaining('Saving'), findsNothing);
    });

    testWidgets('says how many and how far while songs come down', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(DownloadsBar(manager: manager, onTap: () {})),
      );
      manager.enqueue('a');
      manager.enqueue('b');
      manager.enqueue('c');
      await tester.pump();
      await turn(tester);

      expect(find.text('Saving 1 of 3'), findsOneWidget);

      client.progressOf['a']!(100, 100);
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.textContaining('%'), findsOneWidget);
      for (final s in ['a', 'b', 'c']) {
        client.gate[s]?.complete();
      }
      await turn(tester);
      await turn(tester);
    });

    testWidgets('keeps a failure on screen until it is dealt with', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(DownloadsBar(manager: manager, onTap: () {})),
      );
      manager.enqueue('a');
      await tester.pump();
      await turn(tester);
      client.gate['a']!.completeError(Exception('boom'));
      await turn(tester);
      await turn(tester);

      expect(find.text('1 download failed'), findsOneWidget);
    });

    testWidgets('opens the list, which can cancel and retry', (tester) async {
      final tracks = {'a': _t('a', 'Nugget'), 'b': _t('b', 'Collect')};
      await tester.pumpWidget(
        harness(
          Builder(
            builder: (context) => DownloadsBar(
              manager: manager,
              onTap: () => DownloadsSheet.show(
                context,
                manager: manager,
                trackFor: (sha) => tracks[sha],
              ),
            ),
          ),
        ),
      );
      manager.enqueue('a');
      manager.enqueue('b');
      await tester.pump();
      await turn(tester);

      await tester.tap(find.textContaining('Saving'));
      // Not pumpAndSettle: songs still coming down show a turning bar, which
      // never settles and is not meant to.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Downloads'), findsOneWidget);
      expect(find.text('Nugget'), findsOneWidget);
      expect(find.text('Collect'), findsOneWidget);

      await tester.tap(find.text('Cancel all'));
      await tester.pump();
      // A running song stops at its next chunk; the fake only looks when told.
      client.gate['a']?.complete();
      client.gate['b']?.complete();
      await turn(tester);
      expect(manager.activeCount, 0);
    });
  });

  group('the playing bars', () {
    List<double> heights(WidgetTester tester) => [
      for (final e
          in find
              .descendant(
                of: find.byType(PlayingBars),
                matching: find.byType(Container),
              )
              .evaluate())
        tester.getSize(find.byWidget(e.widget)).height,
    ];

    testWidgets('move while it plays', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: PlayingBars(playing: true))),
        ),
      );
      final a = heights(tester);
      await tester.pump(const Duration(milliseconds: 280));
      final b = heights(tester);
      expect(a.length, 4);
      expect(b, isNot(a));
    });

    testWidgets('stand still, as the same bars, when paused', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: PlayingBars(playing: false))),
        ),
      );
      final a = heights(tester);
      await tester.pump(const Duration(milliseconds: 280));
      final b = heights(tester);
      expect(b, a);
      expect(a.length, 4);
      // At rest they are not all the same height: it reads as bars, not a bar.
      expect(a.toSet().length, greaterThan(1));
    });

    testWidgets('start moving again when play resumes', (tester) async {
      Widget app(bool playing) => MaterialApp(
        home: Scaffold(
          body: Center(child: PlayingBars(playing: playing)),
        ),
      );
      await tester.pumpWidget(app(false));
      final paused = heights(tester);
      await tester.pumpWidget(app(true));
      await tester.pump(const Duration(milliseconds: 350));
      expect(heights(tester), isNot(paused));
    });

    testWidgets('hold still under reduced motion, and settle', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(body: Center(child: PlayingBars(playing: true))),
          ),
        ),
      );
      final a = heights(tester);
      await tester.pump(const Duration(milliseconds: 280));
      expect(heights(tester), a);
      // Nothing is asking for frames, so waiting for the screen to settle ends.
      await tester.pumpAndSettle();
    });
  });
}
