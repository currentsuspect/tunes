import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/lyrics/lrc_parser.dart';

void main() {
  group('LrcParser', () {
    test('parses metadata headers', () {
      final lrc = LrcParser.parse(
        '[ar:Travis Scott]\n[ti:ESCAPE PLAN]\n[00:00.00]',
      );
      expect(lrc.metadata['ar'], 'Travis Scott');
      expect(lrc.metadata['ti'], 'ESCAPE PLAN');
    });

    test('parses a single line with mm:ss.ms', () {
      final lrc = LrcParser.parse('[00:12.34]First line');
      expect(lrc.lines, hasLength(1));
      expect(
        lrc.lines.first.timestamp,
        const Duration(seconds: 12, milliseconds: 340),
      );
      expect(lrc.lines.first.text, 'First line');
    });

    test('parses multiple lines sorted by timestamp', () {
      final lrc = LrcParser.parse(
        '[00:10.00]Third\n[00:05.00]First\n[00:15.00]Second',
      );
      expect(lrc.lines.map((l) => l.text).toList(), [
        'First',
        'Third',
        'Second',
      ]);
    });

    test('parses lines without milliseconds', () {
      final lrc = LrcParser.parse('[01:30]Halfway');
      expect(
        lrc.lines.first.timestamp,
        const Duration(minutes: 1, seconds: 30),
      );
    });

    test('parses multiple timestamps on a single line', () {
      final lrc = LrcParser.parse('[00:10.00][00:20.00]Chorus');
      expect(lrc.lines, hasLength(2));
      expect(lrc.lines[0].text, 'Chorus');
      expect(lrc.lines[1].text, 'Chorus');
    });

    test('returns empty for empty input', () {
      expect(LrcParser.parse('').lines, isEmpty);
      expect(LrcParser.parse('   \n\n  ').lines, isEmpty);
    });

    test('format round-trips', () {
      const original = '[00:12.34]First\n[00:15.50]Second';
      final parsed = LrcParser.parse(original);
      final out = LrcParser.format(parsed);
      expect(out, original);
    });

    test('activeLine returns the most recent line at the given position', () {
      final lrc = LrcParser.parse(
        '[00:05.00]First\n[00:10.00]Second\n[00:15.00]Third',
      );
      // Position 0 is before the first timestamp; should be null, not
      // the first line.
      expect(LrcParser.activeLine(lrc, const Duration(seconds: 0)), isNull);
      expect(
        LrcParser.activeLine(lrc, const Duration(seconds: 8))?.text,
        'First',
      );
      expect(
        LrcParser.activeLine(lrc, const Duration(seconds: 12))?.text,
        'Second',
      );
      expect(
        LrcParser.activeLine(lrc, const Duration(seconds: 16))?.text,
        'Third',
      );
    });

    test('preserves plain text without timestamps in untimed', () {
      final lrc = LrcParser.parse('just plain lyrics\nmore lyrics\n');
      expect(lrc.lines, isEmpty);
      expect(lrc.untimed, ['just plain lyrics', 'more lyrics']);
      expect(lrc.hasTimedLines, isFalse);
    });

    test('format preserves minutes beyond 60', () {
      // A track at 65:00 should round-trip; remainder(60) would lose the hour.
      final lrc = LrcParser.parse('[65:30.00]Deep cut');
      expect(LrcParser.format(lrc), '[65:30.00]Deep cut');
    });
  });

  group('enhanced LRC (word timing)', () {
    const enhanced =
        '[00:12.40]<00:12.40>I <00:12.72>remember '
        '<00:13.41>the <00:13.72>night';

    test('reads a timestamp per word', () {
      final lrc = LrcParser.parse(enhanced);
      expect(lrc.hasWordTiming, isTrue);
      expect(lrc.lines.single.words.map((w) => w.text).toList(), [
        'I',
        'remember',
        'the',
        'night',
      ]);
      expect(
        lrc.lines.single.words[1].start,
        const Duration(seconds: 12, milliseconds: 720),
      );
    });

    test('rebuilds the display text from the words', () {
      // The line must read identically whether or not it is word-synced.
      expect(
        LrcParser.parse(enhanced).lines.single.text,
        'I remember the night',
      );
    });

    test('a plain line reports no word timing', () {
      final lrc = LrcParser.parse('[00:12.34]First line');
      expect(lrc.hasWordTiming, isFalse);
      expect(lrc.lines.single.words, isEmpty);
    });

    test('a word ends where the next one starts', () {
      final lrc = LrcParser.parse(enhanced);
      expect(
        lrc.wordEndOf(0, 1),
        const Duration(seconds: 13, milliseconds: 410),
      );
    });

    test('the last word of a line ends at the next line', () {
      final lrc = LrcParser.parse(
        '[00:10.00]<00:10.00>one <00:11.00>two\n[00:20.00]<00:20.00>three',
      );
      expect(lrc.wordEndOf(0, 1), const Duration(seconds: 20));
    });

    test('the very last word uses the track end when given', () {
      final lrc = LrcParser.parse(enhanced);
      expect(
        lrc.wordEndOf(0, 3, trackEnd: const Duration(seconds: 20)),
        const Duration(seconds: 20),
      );
      // Without one it still has width, so the highlight is never zero-length.
      expect(lrc.wordEndOf(0, 3), greaterThan(lrc.lines.single.words[3].start));
    });

    test('tracks which word is being sung', () {
      final lrc = LrcParser.parse(enhanced);
      expect(
        LrcParser.activeWordIndex(lrc, 0, const Duration(seconds: 12)),
        isNull,
      );
      expect(
        LrcParser.activeWordIndex(
          lrc,
          0,
          const Duration(seconds: 12, milliseconds: 900),
        ),
        1,
      );
      // Past the line, the last word stays lit rather than resetting.
      expect(LrcParser.activeWordIndex(lrc, 0, const Duration(minutes: 1)), 3);
    });

    test('reports how far through a word the playhead is', () {
      final lrc = LrcParser.parse(enhanced);
      final mid = LrcParser.wordProgress(
        lrc,
        0,
        1,
        const Duration(seconds: 13, milliseconds: 65),
      );
      expect(mid, closeTo(0.5, 0.02));
      expect(
        LrcParser.wordProgress(lrc, 0, 1, const Duration(seconds: 12)),
        0.0,
      );
      expect(
        LrcParser.wordProgress(lrc, 0, 1, const Duration(seconds: 19)),
        1.0,
      );
    });

    test('round-trips through format', () {
      expect(LrcParser.format(LrcParser.parse(enhanced)), enhanced);
    });

    test('exports as ordinary LRC without losing words', () {
      expect(
        LrcParser.toPlainLrc(LrcParser.parse(enhanced)),
        '[00:12.40]I remember the night',
      );
    });

    test('a timing mark with no word does not render its own markup', () {
      // Recording a timestamp before typing the word left the tag itself
      // showing as the lyric.
      final lrc = LrcParser.parse('[00:01.00]<00:01.00>');
      expect(lrc.lines, isEmpty);
    });

    test('word tags outside a timed line do not leak markup', () {
      final lrc = LrcParser.parse('<00:01.00>hello');
      expect(lrc.untimed, ['hello']);
    });
  });
}
