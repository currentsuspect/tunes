import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/lyrics/adlib_kinds.dart';
import 'package:tunes/core/lyrics/adlibs.dart';

void main() {
  test('each kind is read from its words', () {
    expect(classifyAdlib('(Grrr)'), AdlibKind.growl);
    expect(classifyAdlib('(ugh)'), AdlibKind.growl);
    expect(classifyAdlib('(Brr)'), AdlibKind.effect);
    expect(classifyAdlib('(Skrrt, skrrt)'), AdlibKind.effect);
    expect(classifyAdlib('(baow)'), AdlibKind.boom);
    expect(classifyAdlib('(whisper: come here)'), AdlibKind.whisper);
    expect(classifyAdlib('(shh)'), AdlibKind.whisper);
    expect(classifyAdlib('(Yeah, yeah)'), AdlibKind.hype);
    expect(classifyAdlib("(Let's go)"), AdlibKind.hype);
    expect(classifyAdlib('(maze)', main: 'Stuck in a maze'), AdlibKind.echo);
    expect(classifyAdlib('(a maze)', main: 'Stuck in a maze'), AdlibKind.echo);
    expect(classifyAdlib('(Hannah Montana)'), AdlibKind.plain);
  });

  test('groups are each bracket run, with its kind', () {
    final t = 'Stuck in a maze (maze) (brr) [Yeah]'.split(' ');
    final g = adlibGroups(t, adlibMask(t));
    expect(g.map((x) => x.kind), [
      AdlibKind.echo,
      AdlibKind.effect,
      AdlibKind.hype,
    ]);
    expect(g.first.words, [4]);
  });

  test("square brackets inline are ad-libs, and '[?]' is dropped", () {
    final s = splitAdlibText('Took her to the [?] crib [Yeah]')!;
    expect(s.main, 'Took her to the crib');
    expect(s.adlibs, '(Yeah)');
  });

  test('Marching: echoes from inside the line, chops, booms, and a tag', () {
    expect(
      classifyAdlib("(Lil' bitty)", main: "you a lil' bitty bitch"),
      AdlibKind.echo,
    );
    expect(classifyAdlib('(I-I-I-I—)'), AdlibKind.stutter);
    expect(classifyAdlib('(Buh)'), AdlibKind.boom);
    expect(classifyAdlib('(Skrrt)'), AdlibKind.effect);
    expect(classifyAdlib('(Ooh-yeah)'), AdlibKind.hype);
    expect(classifyAdlib('(Mh)'), AdlibKind.growl);
    expect(wholeLineAdlib(['(BNYX)'])!.kind, AdlibKind.tag);
    expect(wholeLineAdlib(['(Woo)'])!.kind, AdlibKind.hype);
    expect(wholeLineAdlib(['Woo', '(Yeah)']), isNull);
  });

  test("with no word timing, ad-libs land in the line's last moments", () {
    final t = estimatedAdlibTimes(
      const Duration(seconds: 28),
      const Duration(milliseconds: 31790),
      [false],
    );
    // The last one ends as the next line starts.
    expect(t.single.end, const Duration(milliseconds: 31790));
    expect(t.single.start, const Duration(milliseconds: 31440));
  });

  test('several are staggered back, and one written first opens the line', () {
    final t = estimatedAdlibTimes(
      const Duration(seconds: 55),
      const Duration(seconds: 59),
      [true, false, false],
    );
    expect(t[0].start, const Duration(seconds: 55));
    expect(t[2].end, const Duration(seconds: 59));
    expect(t[1].end, lessThan(t[2].start));
  });
}
