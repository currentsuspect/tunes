import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/audio/position_saver.dart';

void main() {
  const a = 'a';
  Duration s(int n) => Duration(seconds: n);

  test('writes every few seconds of playing, not every report', () {
    final p = PositionSaver();
    p.tick(sha: a, position: Duration.zero, playing: true);
    expect(p.tick(sha: a, position: s(1), playing: true), isNull);
    expect(p.tick(sha: a, position: s(4), playing: true), isNull);
    expect(p.tick(sha: a, position: s(5), playing: true), s(5));
    expect(p.tick(sha: a, position: s(7), playing: true), isNull);
    expect(p.tick(sha: a, position: s(10), playing: true), s(10));
  });

  test('stopping the player does not overwrite where the listener was', () {
    // The bug: back out of the app, the player is halted, the engine reports
    // 0:00, and that was written over the real place.
    final p = PositionSaver();
    p.tick(sha: a, position: Duration.zero, playing: true);
    expect(p.tick(sha: a, position: s(150), playing: true), s(150));
    expect(p.tick(sha: a, position: Duration.zero, playing: false), isNull);
    expect(p.tick(sha: a, position: Duration.zero, playing: false), isNull);
  });

  test('a song that is playing and really restarted from zero is kept', () {
    final p = PositionSaver();
    p.tick(sha: a, position: Duration.zero, playing: true);
    p.tick(sha: a, position: s(150), playing: true);
    expect(
      p.tick(sha: a, position: Duration.zero, playing: true),
      Duration.zero,
    );
  });

  test('a paused place that is not zero is still written when it moves', () {
    final p = PositionSaver();
    p.tick(sha: a, position: Duration.zero, playing: true);
    p.tick(sha: a, position: s(100), playing: true);
    // The listener scrubs while paused.
    expect(p.tick(sha: a, position: s(30), playing: false), s(30));
  });

  test('a new song replaces the old place straight away', () {
    final p = PositionSaver();
    p.tick(sha: a, position: Duration.zero, playing: true);
    p.tick(sha: a, position: s(190), playing: true);
    expect(
      p.tick(sha: 'b', position: Duration.zero, playing: true),
      Duration.zero,
    );
    // Not five seconds later: a kill in the first moments must not restore the
    // new song to the old song's spot.
    expect(p.tick(sha: 'b', position: s(2), playing: true), isNull);
  });

  test('a restore writes the restored spot, which is where it already was', () {
    final p = PositionSaver();
    expect(p.tick(sha: a, position: s(41), playing: false), s(41));
    expect(p.tick(sha: a, position: s(41), playing: false), isNull);
  });

  test('no song, nothing to write', () {
    final p = PositionSaver();
    expect(p.tick(sha: null, position: Duration.zero, playing: false), isNull);
  });
}
