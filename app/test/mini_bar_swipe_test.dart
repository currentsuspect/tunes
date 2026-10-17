import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/audio/tune_player.dart';
import 'package:tunes/domain/manifest.dart';
import 'package:tunes/features/player/mini_player_bar.dart';

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

class _P extends TunePlayer {
  _P(this.queue, this.index);
  final calls = <String>[];
  @override
  final List<ManifestTrack> queue;
  @override
  int index;
  @override
  bool get playing => false;
  @override
  Duration get position => const Duration(seconds: 30);
  @override
  Duration get duration => const Duration(minutes: 3);
  @override
  ManifestTrack? get current => queue[index];
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
  void toggle() => calls.add('toggle');
  @override
  void next() => calls.add('next');
  @override
  void previous() => calls.add('previous');
  @override
  void playAt(int i) {
    calls.add('playAt$i');
    index = i;
    notifyListeners();
  }

  @override
  void seek(Duration t) {}
  @override
  void stop() {}
  @override
  void setRepeat(PlaybackRepeat m) {}
  @override
  void setShuffle(bool on) {}
}

Future<_P> _pump(WidgetTester tester, {int index = 1}) async {
  final p = _P([_t('a', 'One'), _t('b', 'Two'), _t('c', 'Three')], index);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 400,
            child: MiniPlayerBar(player: p, onTap: () {}),
          ),
        ),
      ),
    ),
  );
  return p;
}

void main() {
  testWidgets('a short drag springs back and changes nothing', (tester) async {
    final p = await _pump(tester);
    await tester.drag(find.text('Two'), const Offset(-60, 0));
    await tester.pumpAndSettle();
    expect(p.calls, isEmpty);
    expect(find.text('Two'), findsOneWidget);
  });

  testWidgets('the next song slides in under the finger', (tester) async {
    final p = await _pump(tester);
    final g = await tester.startGesture(tester.getCenter(find.text('Two')));
    await g.moveBy(const Offset(-30, 0));
    await g.moveBy(const Offset(-70, 0));
    await tester.pump();
    // Peeking, not playing: nothing changes until the finger lets go.
    expect(find.text('Three'), findsOneWidget);
    expect(p.calls, isEmpty);
    await g.moveBy(const Offset(-80, 0));
    await g.up();
    await tester.pumpAndSettle();
    expect(p.calls, ['playAt2']);
    expect(find.text('Three'), findsOneWidget);
  });

  testWidgets('swiping right goes to the song before, not a restart', (
    tester,
  ) async {
    final p = await _pump(tester);
    await tester.drag(find.text('Two'), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(p.calls, ['playAt0']);
  });

  testWidgets('a quick flick commits even if it is short', (tester) async {
    final p = await _pump(tester);
    await tester.fling(find.text('Two'), const Offset(-70, 0), 1500);
    await tester.pumpAndSettle();
    expect(p.calls, ['playAt2']);
  });

  testWidgets('nothing before the first song: the bar gives and comes back', (
    tester,
  ) async {
    final p = await _pump(tester, index: 0);
    await tester.drag(find.text('One'), const Offset(250, 0));
    await tester.pumpAndSettle();
    expect(p.calls, isEmpty);
    expect(find.text('One'), findsOneWidget);
  });
}
