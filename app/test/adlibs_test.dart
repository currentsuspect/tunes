import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/lyrics/adlibs.dart';

void main() {
  test('bracketed words come out as the ad-libs', () {
    final s = splitAdlibText(
      "Oh, famous at school like I'm Hannah (Woah, let's go)",
    )!;
    expect(s.main, "Oh, famous at school like I'm Hannah");
    expect(s.adlibs, "(Woah, let's go)");
  });

  test('ad-libs in the middle are lifted out too', () {
    final s = splitAdlibText(
      'Number two (Hahahaha), only speak in glory (Yeah)',
    )!;
    expect(s.main, 'Number two only speak in glory');
    expect(s.adlibs, '(Hahahaha) (Yeah)');
  });

  test('a line with none, or wholly in brackets, has no ad-libs', () {
    expect(splitAdlibText('Plain words here'), isNull);
    expect(splitAdlibText('(Yeah, yeah)'), isNull);
  });

  test('the mask follows words across a multi-word bracket', () {
    expect(adlibMask(['go', '(Woah,', "let's", 'go)', 'now']), [
      false,
      true,
      true,
      true,
      false,
    ]);
  });
}
