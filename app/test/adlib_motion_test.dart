import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/lyrics/adlib_kinds.dart';
import 'package:tunes/core/lyrics/adlib_motion.dart';

Duration ms(int n) => Duration(milliseconds: n);

void main() {
  AdlibLook at(AdlibKind k, int pos, {int start = 1000, int end = 1800}) =>
      adlibLook(k, start: ms(start), end: ms(end), position: ms(pos));

  test('an effect pops past full size, then settles', () {
    expect(at(AdlibKind.effect, 900).opacity, lessThan(1));
    expect(at(AdlibKind.effect, 1120).scale, closeTo(1.3, 0.01));
    expect(at(AdlibKind.effect, 1400).scale, 1);
  });

  test('a growl shakes on impact and stretches while held', () {
    expect(at(AdlibKind.growl, 1050).dx, isNot(0));
    expect(at(AdlibKind.growl, 1700).dx, 0);
    expect(at(AdlibKind.growl, 1700).stretch, greaterThan(1.1));
    expect(at(AdlibKind.growl, 2200).stretch, closeTo(1, 0.001));
  });

  test('an echo gains copies, which fade once the word is done', () {
    expect(at(AdlibKind.echo, 1050).ghosts, 0);
    expect(at(AdlibKind.echo, 1300).ghosts, 2);
    expect(at(AdlibKind.echo, 2600).ghostOpacity, 0);
  });

  test('a whisper fades in, never full', () {
    expect(at(AdlibKind.whisper, 1000).opacity, closeTo(0.3, 0.01));
    expect(at(AdlibKind.whisper, 2000).opacity, lessThan(0.8));
  });

  test('hype bounces on its beat and is still after', () {
    expect(at(AdlibKind.hype, 1120).dy, lessThan(-5));
    expect(at(AdlibKind.hype, 1500).dy, 0);
  });

  test('a boom blows up past the effects, bursts, and settles', () {
    expect(at(AdlibKind.boom, 1090).scale, closeTo(1.7, 0.01));
    expect(at(AdlibKind.boom, 1100).burst, greaterThan(0));
    expect(at(AdlibKind.boom, 1500).burst, 0);
    expect(at(AdlibKind.boom, 1500).scale, 1);
  });
}
