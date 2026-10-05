import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/audio/restore_seek.dart';

/// A stand-in for the engine: it only honours a seek once the song has loaded,
/// which is exactly what the real one does.
class _Engine {
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  final seeks = <Duration>[];

  void seek(Duration to) {
    seeks.add(to);
    if (duration > Duration.zero) position = to;
  }
}

void main() {
  const spot = Duration(seconds: 41);

  RestoreSeek make(
    FakeAsync async,
    _Engine e, {
    void Function()? onDone,
    Duration giveUpAfter = const Duration(seconds: 20),
  }) => RestoreSeek(
    target: spot,
    enginePosition: () => e.position,
    engineDuration: () => e.duration,
    seek: e.seek,
    onDone: onDone,
    giveUpAfter: giveUpAfter,
    now: async.getClock(DateTime(2026)).now,
  );

  test('waits for the song to load, then puts it back, then stops', () {
    fakeAsync((async) {
      final e = _Engine();
      var done = false;
      final r = make(async, e, onDone: () => done = true)..start();

      // Still loading: nothing is sent, because it would be thrown away.
      async.elapse(const Duration(seconds: 2));
      expect(e.seeks, isEmpty);
      expect(r.active, isTrue);

      // Loaded: the seek goes in and lands.
      e.duration = const Duration(minutes: 4);
      async.elapse(const Duration(seconds: 1));
      expect(e.seeks, isNotEmpty);
      expect(e.position, spot);
      expect(done, isTrue);
      expect(r.active, isFalse);

      // And it does not keep seeking while the song plays on.
      final count = e.seeks.length;
      e.position += const Duration(seconds: 30);
      async.elapse(const Duration(seconds: 5));
      expect(e.seeks.length, count);
    });
  });

  test('tries again when a seek is dropped', () {
    fakeAsync((async) {
      final e = _Engine()..duration = const Duration(minutes: 4);
      var dropped = 0;
      final r = RestoreSeek(
        target: spot,
        enginePosition: () => e.position,
        engineDuration: () => e.duration,
        // The first two are swallowed, as a loading engine does.
        seek: (to) {
          if (dropped++ < 2) return;
          e.position = to;
        },
        now: async.getClock(DateTime(2026)).now,
      )..start();
      async.elapse(const Duration(seconds: 3));
      expect(e.position, spot);
      expect(r.active, isFalse);
    });
  });

  test('gives up rather than seeking for ever', () {
    fakeAsync((async) {
      final e = _Engine();
      final r = make(async, e, giveUpAfter: const Duration(seconds: 5))
        ..start();
      async.elapse(const Duration(seconds: 6));
      expect(r.active, isFalse);
    });
  });

  test('a listener who has already moved on is left alone', () {
    fakeAsync((async) {
      final e = _Engine()..duration = const Duration(minutes: 4);
      final r = make(async, e)..start();
      r.cancel();
      e.seeks.clear();
      async.elapse(const Duration(seconds: 3));
      expect(e.seeks, isEmpty);
    });
  });

  test('already at the spot: nothing to do', () {
    fakeAsync((async) {
      final e = _Engine()
        ..duration = const Duration(minutes: 4)
        ..position = const Duration(seconds: 40);
      var done = false;
      make(async, e, onDone: () => done = true).start();
      expect(done, isTrue);
      expect(e.seeks, isEmpty);
    });
  });
}
