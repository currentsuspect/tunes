import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/lyrics/lrc_parser.dart';
import 'package:tunes/core/lyrics/reading.dart';

void main() {
  group('long lines are split for reading', () {
    test('a short line is left alone', () {
      final r = splitForReading(LrcParser.parse('[00:01.00]Short and sweet'));
      expect(r.lrc.lines.map((l) => l.text), ['Short and sweet']);
      expect(r.origin, [0]);
    });

    test('a long line breaks after its comma, not inside an ad-lib', () {
      final r = splitForReading(
        LrcParser.parse(
          '[00:00.00]Number two (Hahahaha), only speak in glory (Yeah)\n'
          '[00:10.00]Next',
        ),
      );
      expect(r.lrc.lines.map((l) => l.text).toList(), [
        'Number two (Hahahaha),',
        'only speak in glory (Yeah)',
        'Next',
      ]);
      expect(r.origin, [0, 0, 1]);
      // Line-timed: the second half starts partway into the line's time.
      final second = r.lrc.lines[1].timestamp;
      expect(second, greaterThan(Duration.zero));
      expect(second, lessThan(const Duration(seconds: 10)));
    });

    test('where ad-libs have their own row, they do not make a line long', () {
      final lrc = LrcParser.parse(
        '[00:00.00]Number two (Hahahaha), only speak in glory (Yeah)',
      );
      expect(splitForReading(lrc, adlibsApart: true).lrc.lines, hasLength(1));
      expect(splitForReading(lrc).lrc.lines, hasLength(2));
    });

    test('a word-timed half starts when its first word is sung', () {
      final r = splitForReading(
        LrcParser.parse(
          '[00:01.000]<00:01.000>Ugh,<00:01.200> <00:01.200>bitch,<00:01.500> '
          '<00:01.500>like,<00:01.800> <00:01.800>where<00:02.000> '
          '<00:02.000>are<00:02.100> <00:02.100>your<00:02.300> '
          '<00:02.300>manners?<00:02.900> <00:03.000>Got<00:03.200> '
          '<00:03.200>me<00:03.300> <00:03.300>thinking<00:03.700>',
        ),
      );
      expect(r.lrc.lines, hasLength(2));
      expect(r.lrc.lines[0].text, endsWith('manners?'));
      expect(r.lrc.lines[1].timestamp, const Duration(seconds: 3));
      expect(r.lrc.lines[1].words.first.text, 'Got');
    });
  });

  group('word ends', () {
    test('a tag straight after a word is its end, kept to the millisecond', () {
      final lrc = LrcParser.parse(
        '[00:01.170]<00:01.170>to<00:01.440> <00:01.440>the<00:01.530> '
        '<00:01.530>left<00:01.925>',
      );
      final words = lrc.lines.single.words;
      expect(words.map((w) => w.text), ['to', 'the', 'left']);
      expect(words.last.end, const Duration(milliseconds: 1925));
      expect(lrc.wordEndOf(0, 2), const Duration(milliseconds: 1925));
    });

    test(
      'a word held into a gap ends where the lyric says, not at the next word',
      () {
        final lrc = LrcParser.parse(
          '[00:01.00]<00:01.00>hold<00:01.50> <00:03.00>on',
        );
        expect(lrc.wordEndOf(0, 0), const Duration(milliseconds: 1500));
      },
    );

    test('ends and milliseconds survive a round trip', () {
      const text = '[00:01.17]<00:01.17>to<00:01.445> <00:01.445>the<00:01.53>';
      expect(LrcParser.format(LrcParser.parse(text)), text);
    });

    test('lyrics without ends read as before', () {
      final lrc = LrcParser.parse('[00:01.00]<00:01.00>a <00:02.00>b');
      expect(lrc.lines.single.words.map((w) => w.end), [null, null]);
      expect(lrc.wordEndOf(0, 0), const Duration(seconds: 2));
    });
  });
}
