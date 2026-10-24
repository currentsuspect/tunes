import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/lyrics/sync_draft.dart';
import 'package:tunes/core/lyrics/word_window.dart';

Duration ms(int n) => Duration(milliseconds: n);

void main() {
  SyncDraft draft() {
    final d = SyncDraft(['stuck in a maze']);
    d.lineStarts[0] = ms(2000);
    return d;
  }

  test("the first word's start is looked for from just before the line", () {
    final w = wordWindow(
      draft(),
      0,
      0,
      WordPhase.start,
      endRange: ms(800),
      lineEnd: ms(6000),
    );
    expect(w.from, ms(1600));
    expect(w.to, ms(6000));
  });

  test(
    'a later start is looked for from the last mark to the end of the line',
    () {
      final d = draft()
        ..wordStarts[0][0] = ms(2040)
        ..wordEnds[0][0] = ms(2520);
      final w = wordWindow(
        d,
        0,
        1,
        WordPhase.start,
        endRange: ms(800),
        lineEnd: ms(6000),
      );
      expect(w.from, ms(2520), reason: 'from where the last word ended');
      expect(w.to, ms(6000));
      // With no end on the last word, from its start.
      d.wordEnds[0][0] = null;
      expect(
        wordWindow(
          d,
          0,
          1,
          WordPhase.start,
          endRange: ms(800),
          lineEnd: ms(6000),
        ).from,
        ms(2040),
      );
    },
  );

  test('an end is looked for just after the start, for the range picked', () {
    final d = draft()..wordStarts[0][3] = ms(2760);
    final w = wordWindow(d, 0, 3, WordPhase.end, endRange: ms(1200));
    expect(w.from, ms(2780));
    expect(w.to, ms(3980));
  });

  test('a window is never a sliver and never the rest of the song', () {
    final d = draft()..wordStarts[0][0] = ms(5900);
    expect(
      wordWindow(
        d,
        0,
        1,
        WordPhase.start,
        endRange: ms(800),
        lineEnd: ms(6000),
      ).to,
      ms(6700),
    );
    expect(
      wordWindow(
        draft(),
        0,
        0,
        WordPhase.start,
        endRange: ms(800),
        lineEnd: ms(90000),
      ).to,
      ms(13600),
    );
  });
}
