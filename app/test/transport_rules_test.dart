import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/audio/transport_rules.dart';

void main() {
  group('previous', () {
    test('mid-track it restarts the track you are on', () {
      // The complaint that started this: on track 3 of an album, previous
      // took you to track 2 instead of back to the top of track 3.
      expect(
        previousActionFor(
          position: const Duration(seconds: 40),
          index: 2,
          queueLength: 10,
          repeatAll: false,
        ),
        PreviousAction.restart,
      );
    });

    test('just after a track starts it steps back', () {
      // Without this there is no way to reach the previous track at all.
      expect(
        previousActionFor(
          position: const Duration(milliseconds: 900),
          index: 2,
          queueLength: 10,
          repeatAll: false,
        ),
        PreviousAction.previousTrack,
      );
    });

    test('the boundary belongs to stepping back', () {
      // Exactly on the window is still "I just pressed play on the wrong one".
      expect(
        previousActionFor(
          position: kRestartWindow,
          index: 2,
          queueLength: 10,
          repeatAll: false,
        ),
        PreviousAction.previousTrack,
      );
      expect(
        previousActionFor(
          position: kRestartWindow + const Duration(milliseconds: 1),
          index: 2,
          queueLength: 10,
          repeatAll: false,
        ),
        PreviousAction.restart,
      );
    });

    test('the first track restarts rather than doing nothing', () {
      expect(
        previousActionFor(
          position: const Duration(milliseconds: 500),
          index: 0,
          queueLength: 10,
          repeatAll: false,
        ),
        PreviousAction.restart,
      );
    });

    test('repeat-all wraps from the first track, but only at the top', () {
      expect(
        previousActionFor(
          position: const Duration(milliseconds: 500),
          index: 0,
          queueLength: 10,
          repeatAll: true,
        ),
        PreviousAction.wrapToLast,
      );
      // Deep into the opening track, previous still means this track. Wrapping
      // to the end of the album from thirty seconds in would be a shock.
      expect(
        previousActionFor(
          position: const Duration(seconds: 30),
          index: 0,
          queueLength: 10,
          repeatAll: true,
        ),
        PreviousAction.restart,
      );
    });

    test('pressing twice goes back, however slowly the second press comes', () {
      // The first press restarted track 3 and playback has run on past the
      // restart window. The second press must still reach track 2, or "double
      // previous" would depend on reaction time.
      expect(
        previousActionFor(
          position: const Duration(seconds: 5),
          index: 2,
          queueLength: 10,
          repeatAll: false,
          sinceRestart: const Duration(seconds: 6),
        ),
        PreviousAction.previousTrack,
      );
    });

    test('a much later press is a first press again', () {
      expect(
        previousActionFor(
          position: const Duration(seconds: 30),
          index: 2,
          queueLength: 10,
          repeatAll: false,
          sinceRestart: kDoublePressWindow + const Duration(seconds: 1),
        ),
        PreviousAction.restart,
      );
    });

    test('a double press on the first track still wraps under repeat-all', () {
      expect(
        previousActionFor(
          position: const Duration(seconds: 20),
          index: 0,
          queueLength: 10,
          repeatAll: true,
          sinceRestart: const Duration(seconds: 2),
        ),
        PreviousAction.wrapToLast,
      );
    });

    test('a single-track queue never wraps to itself', () {
      expect(
        previousActionFor(
          position: Duration.zero,
          index: 0,
          queueLength: 1,
          repeatAll: true,
        ),
        PreviousAction.restart,
      );
    });
  });
}
