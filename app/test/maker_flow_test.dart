import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/audio/playhead_clock.dart';
import 'package:tunes/core/audio/tune_player.dart';
import 'package:tunes/domain/manifest.dart';
import 'package:tunes/features/lyrics/lyrics_sync_page.dart';

class _P extends TunePlayer {
  Duration pos = const Duration(milliseconds: 2000);
  bool _playing = false;
  double _rate = 1;
  @override
  List<ManifestTrack> get queue => const [];
  @override
  int get index => 0;
  @override
  bool get playing => _playing;
  @override
  Duration get position => pos;
  @override
  Duration get duration => const Duration(minutes: 3);
  @override
  ManifestTrack? get current => null;
  @override
  PlaybackRepeat get repeat => PlaybackRepeat.off;
  @override
  bool get shuffle => false;
  @override
  double get rate => _rate;
  @override
  void setRate(double r) => _rate = r;
  @override
  void playQueue(List<ManifestTrack> tracks, int startIndex) {}
  @override
  void play() => _playing = true;
  @override
  void pause() => _playing = false;
  @override
  void toggle() => _playing = !_playing;
  @override
  void next() {}
  @override
  void previous() {}
  @override
  void playAt(int index) {}
  @override
  void seek(Duration t) {
    pos = t;
    notifyListeners();
  }

  @override
  void stop() {}
  @override
  void noSuchMethod(Invocation i) {}
}

ManifestTrack _t() => ManifestTrack(
  sha: 'a' * 64,
  size: 1,
  codec: 'flac',
  sampleRate: 1,
  channels: 2,
  bitrate: 1,
  durationMs: 180000,
  title: 'Maze',
  artist: 'Juice WRLD',
  album: 'X',
  year: null,
  artSha: null,
  releaseId: null,
  trackNumber: null,
  discNumber: null,
);

void main() {
  setUp(() => PlayheadClock.ticking = false);
  tearDown(() => PlayheadClock.ticking = true);

  testWidgets(
    'a word is timed in two steps, each from where the last left off',
    (tester) async {
      final p = _P();
      String? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: LyricsSyncPage(
            track: _t(),
            player: p,
            initialLyrics: '[00:02.00]stuck in\n[00:06.00]next',
            onSave: (s) async => saved = s,
          ),
        ),
      );
      await tester.tap(find.text('Words'));
      await tester.pumpAndSettle();
      expect(find.text('Mark the start of “stuck”'), findsOneWidget);

      p.seek(const Duration(milliseconds: 2040));
      await tester.tap(find.text('Mark the start of “stuck”'));
      await tester.pumpAndSettle();
      // The end step opens just after the start, paused there.
      expect(find.text('Mark the end of “stuck”'), findsOneWidget);
      expect(p.pos, const Duration(milliseconds: 2060));

      p.seek(const Duration(milliseconds: 2520));
      await tester.tap(find.text('Mark the end of “stuck”'));
      await tester.pumpAndSettle();
      // On to the next word, its start window opening at that end.
      expect(find.text('Mark the start of “in”'), findsOneWidget);
      expect(p.pos, const Duration(milliseconds: 2520));

      // Half speed, and back to normal on leaving.
      await tester.tap(find.text('1×'));
      await tester.pumpAndSettle();
      expect(p.rate, 0.75);

      p.seek(const Duration(milliseconds: 2700));
      await tester.tap(find.text('Mark the start of “in”'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No end, next word'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved, contains('<00:02.04>stuck<00:02.52> <00:02.70>in'));
    },
  );
}
