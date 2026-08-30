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
}
