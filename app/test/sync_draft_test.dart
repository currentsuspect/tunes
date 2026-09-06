import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/lyrics/sync_draft.dart';

Duration at(num seconds) => Duration(milliseconds: (seconds * 1000).round());

void main() {
  group('line timing', () {
    test('walks the cursor down the lines', () {
      final d = SyncDraft(['I remember the night', 'when everything changed']);
      expect(d.nextUntimedLine, 0);
      expect(d.anyTimed, isFalse);
      d.lineStarts[0] = at(84.37);
      expect(d.nextUntimedLine, 1);
      d.lineStarts[1] = at(87.82);
      expect(d.nextUntimedLine, isNull);
      expect(d.timedLineCount, 2);
    });

    test('writes ordinary LRC when only lines are timed', () {
      final d = SyncDraft(['I remember the night', 'when everything changed']);
      d.lineStarts[0] = at(84.37);
      d.lineStarts[1] = at(87.82);
      expect(
        d.toLrc(),
        '[01:24.37]I remember the night\n'
        '[01:27.82]when everything changed',
      );
    });
  });

  group('word timing', () {
    test('splits a line into one slot per word', () {
      final d = SyncDraft(['I remember the night']);
      expect(d.wordsOf(0), ['I', 'remember', 'the', 'night']);
      expect(d.wordStarts[0].length, 4);
      expect(d.nextUntimedWord(0), 0);
    });

    test('a half-timed line stays line-only', () {
      // Emitting word tags for two of four words would sweep the highlight
      // partway and then stop, which reads as a bug rather than as work in
      // progress.
      final d = SyncDraft(['I remember the night']);
      d.lineStarts[0] = at(84.37);
      d.wordStarts[0][0] = at(84.37);
      d.wordStarts[0][1] = at(84.72);
      expect(d.nextUntimedWord(0), 2);
      expect(d.toLrc(), '[01:24.37]I remember the night');
    });

    test('a fully timed line emits enhanced LRC', () {
      final d = SyncDraft(['I remember the night']);
      d.lineStarts[0] = at(84.37);
      d.wordStarts[0][0] = at(84.37);
      d.wordStarts[0][1] = at(84.72);
      d.wordStarts[0][2] = at(85.41);
      d.wordStarts[0][3] = at(85.72);
      expect(
        d.toLrc(),
        '[01:24.37]<01:24.37>I <01:24.72>remember '
        '<01:25.41>the <01:25.72>night',
      );
    });
  });

  group('unfinished work', () {
    test('keeps untimed lines instead of dropping them', () {
      // Saving a partial sync must not lose words the user typed.
      final d = SyncDraft(['first', 'second', 'third']);
      d.lineStarts[0] = at(10);
      final out = d.toLrc();
      expect(out, contains('[00:10.00]first'));
      expect(out, contains('second'));
      expect(out, contains('third'));
    });

    test('never invents a timestamp for an untimed line', () {
      final d = SyncDraft(['first', 'second']);
      d.lineStarts[0] = at(10);
      expect(d.toLrc(), isNot(contains('[00:10.00]second')));
      expect(d.toLrc(), isNot(contains('[00:00.00]second')));
    });

    test('a draft with nothing timed still round-trips its words', () {
      final d = SyncDraft(['alpha', 'beta']);
      expect(d.anyTimed, isFalse);
      expect(d.toLrc(), contains('alpha'));
      expect(d.toLrc(), contains('beta'));
    });

    test('drops blank source lines rather than timing whitespace', () {
      final d = SyncDraft(['real line', '   ']);
      d.lineStarts[0] = at(5);
      expect(d.toLrc(), '[00:05.00]real line');
    });
  });
}
