import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/lyrics/word_motion.dart';

Duration ms(int n) => Duration(milliseconds: n);

void main() {
  WordMotion at(int pos, {int start = 1000, int end = 1300}) =>
      wordMotion(start: ms(start), end: ms(end), position: ms(pos));

  test('ahead of its start a word is dark and still', () {
    final m = at(900);
    expect([m.fill, m.lift, m.glow], [0, 0, 0]);
  });

  test('while sung it fills by time and rises', () {
    final m = at(1150);
    expect(m.fill, closeTo(0.5, 0.001));
    expect(m.lift, 1);
    expect(m.glow, 0, reason: 'a short word does not glow');
  });

  test('a held note glows as it is held, and settles once it ends', () {
    final early = at(1200, end: 2600);
    final late = at(2500, end: 2600);
    expect(early.glow, 0);
    expect(late.glow, greaterThan(0.8));
    final after = at(2700, end: 2600);
    expect(after.fill, 1);
    expect(after.glow, lessThan(late.glow));
    expect(at(3000, end: 2600).lift, 0);
  });

  test(
    'after its end a word is lit and at rest, even before the next starts',
    () {
      final m = at(1600);
      expect([m.fill, m.lift, m.glow], [1, 0, 0]);
    },
  );
}
