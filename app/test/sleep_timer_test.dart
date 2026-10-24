import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/audio/sleep_timer.dart';
import 'package:tunes/domain/manifest.dart';

import 'widget_test.dart' show FakeTunePlayer;

ManifestTrack _t(String sha, String release) => ManifestTrack(
  sha: sha,
  size: 1,
  codec: 'flac',
  sampleRate: 44100,
  channels: 2,
  bitrate: 900,
  durationMs: 200000,
  title: sha,
  artist: 'A',
  album: release,
  year: null,
  artSha: null,
  releaseId: release,
  trackNumber: null,
  discNumber: null,
);

class _Player extends FakeTunePlayer {
  final levels = <double>[];
  @override
  void setVolume(double level) => levels.add(level);
}

void main() {
  test('stops after the time, fading over the last minute, then puts the '
      'level back', () {
    fakeAsync((clock) {
      final p = _Player();
      final start = DateTime(2026, 10, 24, 23);
      final s = SleepTimer(player: p, now: () => start.add(clock.elapsed));
      p.playQueue([_t('a', 'r1')], 0);
      s.start(const Duration(minutes: 2));
      clock.elapse(const Duration(seconds: 59));
      expect(p.levels, isEmpty);
      clock.elapse(const Duration(seconds: 31));
      expect(p.levels.last, closeTo(0.5, 0.05));
      expect(p.playing, isTrue);
      clock.elapse(const Duration(seconds: 31));
      expect(p.playing, isFalse);
      expect(p.levels.last, 1);
      expect(s.active, isFalse);
      s.dispose();
    });
  });

  test('+10 min moves the end and lifts a fade already under way', () {
    fakeAsync((clock) {
      final p = _Player();
      final start = DateTime(2026, 10, 24, 23);
      final s = SleepTimer(player: p, now: () => start.add(clock.elapsed));
      p.playQueue([_t('a', 'r1')], 0);
      s.start(const Duration(seconds: 30));
      clock.elapse(const Duration(seconds: 5));
      expect(p.levels.last, lessThan(1));
      s.extend();
      expect(p.levels.last, 1);
      expect(s.remaining!.inMinutes, 10);
      s.dispose();
    });
  });

  test('end of song pauses when the next one starts, back at its start', () {
    final p = _Player();
    final s = SleepTimer(player: p);
    p.playQueue([_t('a', 'r1'), _t('b', 'r1')], 0);
    s.endOfSong();
    p.next();
    expect(p.playing, isFalse);
    expect(p.seekCalls, greaterThan(0));
    expect(s.active, isFalse);
    s.dispose();
  });

  test('end of album lets the album play on, then stops at the next one', () {
    final p = _Player();
    final s = SleepTimer(player: p);
    p.playQueue([_t('a', 'r1'), _t('b', 'r1'), _t('c', 'r2')], 0);
    s.endOfAlbum();
    p.next();
    expect(p.playing, isTrue);
    p.next();
    expect(p.playing, isFalse);
    s.dispose();
  });

  test('clock', () {
    expect(sleepClock(const Duration(minutes: 28, seconds: 41)), '28:41');
    expect(sleepClock(const Duration(hours: 1, seconds: 5)), '1:00:05');
  });
}
