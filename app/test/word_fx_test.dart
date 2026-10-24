import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/lyrics/word_fx.dart';
import 'package:tunes/core/lyrics/word_fx_motion.dart';

Duration ms(int n) => Duration(milliseconds: n);

void main() {
  test('one picture word per line, the first, from its own choices', () {
    final f = lineWordFx(
      "Bitch, I been so high, I don't even touch the ground".split(' '),
      7,
    )!;
    expect(f.index, 4);
    expect(kWordFx['high'], contains(f.fx));
    expect(
      lineWordFx('I got love for my time'.split(' '), 1),
      isNull,
      reason: 'common words mean nothing on their own',
    );
  });

  test('the same line picks the same effect every play, and lines vary', () {
    final words = 'All this ice on me'.split(' ');
    expect(
      lineWordFx(words, fxSeed('abc', 3))!.fx,
      lineWordFx(words, fxSeed('abc', 3))!.fx,
    );
    final seen = {
      for (var line = 0; line < 20; line++)
        lineWordFx(words, fxSeed('abc', line))!.fx,
    };
    expect(seen.length, greaterThan(1), reason: "a word's presets alternate");
  });

  test("punctuation and apostrophes don't hide a word", () {
    expect(lineWordFx(["Smokin'", 'gas,'], 1)!.index, 0);
    expect(lineWordFx(['ICE!'], 1), isNotNull);
  });

  test('an effect builds while the word is sung and is gone soon after', () {
    WordFxLook at(WordFx fx, int pos) =>
        wordFxLook(fx, start: ms(1000), end: ms(1600), position: ms(pos));
    expect(at(WordFx.frost, 900).tintAmount, 0);
    expect(at(WordFx.frost, 1300).tintAmount, greaterThan(0.8));
    expect(at(WordFx.float, 1550).dy, lessThan(-8));
    expect(at(WordFx.float, 2000).dy, 0);
    expect(at(WordFx.flash, 1050).flash, greaterThan(0.6));
    expect(at(WordFx.bleed, 1500).drop, greaterThan(0.7));
  });
}
