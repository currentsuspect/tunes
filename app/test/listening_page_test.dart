import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/audio/tune_player.dart';
import 'package:tunes/core/data/database.dart';
import 'package:tunes/core/data/play_history.dart';
import 'package:tunes/core/theme/theme.dart';
import 'package:tunes/domain/manifest.dart';
import 'package:tunes/features/stats/listening_page.dart';

class _Idle extends TunePlayer {
  @override
  List<ManifestTrack> get queue => const [];
  @override
  int get index => -1;
  @override
  bool get playing => false;
  @override
  Duration get position => Duration.zero;
  @override
  Duration get duration => Duration.zero;
  @override
  ManifestTrack? get current => null;
  @override
  PlaybackRepeat get repeat => PlaybackRepeat.off;
  @override
  bool get shuffle => false;
  @override
  void playQueue(List<ManifestTrack> t, int i) {}
  @override
  void play() {}
  @override
  void pause() {}
  @override
  void toggle() {}
  @override
  void next() {}
  @override
  void previous() {}
  @override
  void playAt(int i) {}
  @override
  void seek(Duration t) {}
  @override
  void stop() {}
  @override
  void setRepeat(PlaybackRepeat m) {}
  @override
  void setShuffle(bool on) {}
}

ManifestTrack _t(String sha, String title, String artist, String album) =>
    ManifestTrack(
      sha: sha,
      size: 1,
      codec: 'flac',
      sampleRate: 44100,
      channels: 2,
      bitrate: 1000,
      durationMs: 200000,
      title: title,
      artist: artist,
      album: album,
      year: '2026',
      artSha: null,
      releaseId: null,
      trackNumber: null,
      discNumber: null,
      primaryArtist: artist,
      featured: const [],
    );

Future<void> _fonts() async {
  for (final (family, files) in [
    ('Newsreader', ['Newsreader.ttf', 'Newsreader-Italic.ttf']),
    ('HankenGrotesk', ['HankenGrotesk.ttf']),
    ('DMMono', ['DMMono-Regular.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(
        Future.value(
          ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync()),
        ),
      );
    }
    await loader.load();
  }
}

void main() {
  final lib = {
    for (final t in [
      _t('a', 'Nugget', 'Swapa', 'Fade'),
      _t('b', 'Mazishi', 'Swapa', 'Fade'),
      _t('c', 'Poppin', 'Yeat', 'Lyfë'),
      _t('d', 'Smooth Operator', 'Sade', 'Diamond Life'),
      _t('e', 'Kanairo', 'Maajins', 'Kanairo'),
    ])
      t.sha: t,
  };

  Future<PlayHistory> seeded() async {
    final db = TunesDatabase.forTesting(NativeDatabase.memory());
    final rng = Random(7);
    final now = DateTime.now();
    final shas = lib.keys.toList();
    for (var d = 0; d < 40; d++) {
      for (var k = 0; k < rng.nextInt(9); k++) {
        final at = DateTime(
          now.year,
          now.month,
          now.day - d,
          8 + rng.nextInt(15),
        );
        await db
            .into(db.playEvents)
            .insert(
              PlayEventsCompanion.insert(
                sha: shas[min(rng.nextInt(7), 4)],
                startedAt: at.millisecondsSinceEpoch,
                listenedMs: 60000 + rng.nextInt(180000),
                durationMs: const Value(200000),
                completed: Value(rng.nextInt(5) != 0),
              ),
            );
      }
    }
    return PlayHistory(db, _Idle());
  }

  testWidgets('draws a full history on a phone without overflowing', (
    tester,
  ) async {
    await tester.runAsync(_fonts);
    tester.view.physicalSize = const Size(1080, 2400 * 2);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final history = (await tester.runAsync(seeded))!;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTunesTheme(const MediaQueryData()),
        home: ListeningPage(history: history, library: lib),
      ),
    );
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    expect(find.text('Your listening'), findsOneWidget);
    expect(find.text('Top artists'), findsOneWidget);
    expect(find.text('Swapa'), findsWidgets);
    if (Platform.environment['TUNES_SHOT'] != null) {
      await expectLater(
        find.byType(ListeningPage),
        matchesGoldenFile('shots/listening_week.png'),
      );
    }
    await tester.tap(find.text('All time'));
    await tester.pump();
    expect(find.text('Minutes a month'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
