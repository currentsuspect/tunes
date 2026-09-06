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

  group('section headers', () {
    test('recognises headers without swallowing sung parentheticals', () {
      for (final h in [
        '[Verse]',
        '[Chorus 2]',
        '[Pre-Chorus]',
        '(Bridge)',
        '  [Outro] ',
        '(Hook)',
      ]) {
        expect(SyncDraft.isSectionHeader(h), isTrue, reason: h);
      }
      // These get sung, so timing must still ask for them.
      for (final l in ['(yeah yeah)', '(ooh)', 'I remember the night']) {
        expect(SyncDraft.isSectionHeader(l), isFalse, reason: l);
      }
    });

    test('the cursor never lands on a header', () {
      // The regression: [Verse] took the tap meant for the first sung line,
      // so every timestamp sat one line too high and playback showed the
      // previous line throughout.
      final d = SyncDraft([
        '[Verse]',
        'first sung line',
        'second sung line',
        '[Chorus]',
        'third',
      ]);
      expect(d.nextUntimedLine, 1);
      d.lineStarts[1] = at(3);
      expect(d.nextUntimedLine, 2);
      d.lineStarts[2] = at(6);
      expect(d.nextUntimedLine, 4, reason: 'must skip [Chorus]');
      d.lineStarts[4] = at(9);
      expect(d.nextUntimedLine, isNull);
    });

    test('does not count headers as outstanding work', () {
      final d = SyncDraft(['[Verse]', 'only line']);
      expect(d.untimedLineCount, 1);
      d.lineStarts[1] = at(3);
      expect(d.untimedLineCount, 0);
    });

    test('a header keeps its place, sharing the start of its verse', () {
      final d = SyncDraft(['[Verse]', 'first sung line', '[Chorus]', 'third']);
      d.lineStarts[1] = at(3);
      d.lineStarts[3] = at(9);
      expect(
        d.toLrc(),
        '[00:03.00][Verse]\n'
        '[00:03.00]first sung line\n'
        '[00:09.00][Chorus]\n'
        '[00:09.00]third',
      );
    });

    test('a trailing header with nothing after it is kept as plain text', () {
      final d = SyncDraft(['line', '[Outro]']);
      d.lineStarts[0] = at(3);
      expect(d.toLrc(), contains('[Outro]'));
      expect(d.toLrc(), contains('[00:03.00]line'));
    });
  });

  group('shiftAll', () {
    test('moves every line and word together', () {
      final d = SyncDraft(['a', 'b']);
      d.lineStarts[0] = at(3);
      d.lineStarts[1] = at(6);
      d.wordStarts[0][0] = at(3);
      d.shiftAll(const Duration(milliseconds: -400));
      expect(d.lineStarts[0], const Duration(milliseconds: 2600));
      expect(d.lineStarts[1], const Duration(milliseconds: 5600));
      expect(d.wordStarts[0][0], const Duration(milliseconds: 2600));
    });

    test('clamps at zero rather than going negative', () {
      final d = SyncDraft(['a']);
      d.lineStarts[0] = at(1);
      d.shiftAll(const Duration(seconds: -60));
      expect(d.lineStarts[0], Duration.zero);
    });

    test('leaves untimed lines untimed', () {
      final d = SyncDraft(['a', 'b']);
      d.lineStarts[0] = at(3);
      d.shiftAll(const Duration(milliseconds: 100));
      expect(d.lineStarts[1], isNull);
    });
  });
}
