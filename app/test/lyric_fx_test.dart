import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/lyrics/adlib_kinds.dart';
import 'package:tunes/core/lyrics/lrc_parser.dart';
import 'package:tunes/core/lyrics/lyric_fx.dart';
import 'package:tunes/core/lyrics/word_fx.dart';

void main() {
  test('fixes read, write and travel in the lyric as metadata', () {
    final t = LyricFxTable()
      ..set(12, 3, const FxFix('boom', 250))
      ..set(3, 5, const FxFix('frost', -120));
    const lyrics = '[00:01.00]one\n[00:02.00]two';
    final saved = t.applyTo(lyrics);
    expect(saved.split('\n').first, '[tunesfx:3.5=frost@-120;12.3=boom@+250]');
    final lrc = LrcParser.parse(saved);
    expect(lrc.lines.map((l) => l.text), ['one', 'two'], reason: 'never shown');
    final back = LyricFxTable.parse(lrc.metadata[LyricFxTable.key]);
    expect(back.at(12, 3)!.adlibKind, AdlibKind.boom);
    expect(back.at(3, 5)!.wordFx, WordFx.frost);
    expect(back.at(3, 5)!.shift, const Duration(milliseconds: -120));
  });

  test('saving again replaces the line, and an empty table removes it', () {
    final t = LyricFxTable()..set(0, 0, const FxFix('none', 0));
    final once = t.applyTo('[00:01.00]a');
    final twice = (LyricFxTable()..set(0, 1, const FxFix('hype', 0))).applyTo(
      once,
    );
    expect(RegExp('tunesfx').allMatches(twice).length, 1);
    expect(LyricFxTable().applyTo(twice), '[00:01.00]a');
  });

  test('nonsense in the line is skipped, not fatal', () {
    final t = LyricFxTable.parse('1.2=boom@+5;garbage;3=x@1');
    expect(t.fixes.length, 1);
  });

  group('fixes applied to a line', () {
    final words = "Put money on this whip (Woo), this Urus go 200 (Skrrt)"
        .split(' ');

    test('untouched, the line reads as it would anyway', () {
      final l = resolveLineFx(words, seed: 3);
      expect(l.picture!.index, 1);
      expect(l.kinds[5], AdlibKind.hype);
      expect(l.kinds[10], AdlibKind.effect);
      expect(l.shifts, isEmpty);
    });

    test('an ad-lib given a kind and moved earlier', () {
      final fixes = {10: const FxFix('boom', -400)};
      final l = resolveLineFx(words, seed: 3, fixAt: (i) => fixes[i]);
      expect(l.kinds[10], AdlibKind.boom);
      expect(l.shiftOf(10), const Duration(milliseconds: -400));
    });

    test('a picture word switched off, or another chosen by hand', () {
      final off = resolveLineFx(
        words,
        seed: 3,
        fixAt: (i) => i == 1 ? const FxFix('none', 0) : null,
      );
      expect(off.picture, isNull);
      final chosen = resolveLineFx(
        words,
        seed: 3,
        fixAt: (i) => i == 8 ? const FxFix('flame', 120) : null,
      );
      expect(chosen.picture, (index: 8, fx: WordFx.flame));
      expect(chosen.shiftOf(8), const Duration(milliseconds: 120));
    });

    test('with picture words off, ad-lib fixes still apply', () {
      final l = resolveLineFx(
        words,
        fixAt: (i) => i == 5 ? const FxFix('growl', 0) : null,
      );
      expect(l.picture, isNull);
      expect(l.kinds[5], AdlibKind.growl);
    });
  });
}
