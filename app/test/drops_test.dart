import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/lyrics/drops.dart';
import 'package:tunes/core/lyrics/lrc_parser.dart';

Duration ms(int n) => Duration(milliseconds: n);

// Yeat & Don Toliver, "Griddlë": the box's reading of it (24 Oct) and the
// lyric around its moments.
const griddle = '''
[tunesbeat:drop=1360,60550,67660,74700,124550;break=56710-60550,63080-67660;pulse=1360,3580,60500,67610,68950,71170;quiet=154230-157330]
[00:01.46] (I-I-I)
[00:01.73] Uh, uh
[00:57.01] She move it, move it, move it (move it, move it)
[00:59.65] Hide my blick in the bush (ah)
[01:00.12] I let her do it, do it (do it)
[01:02.17] I mix OJ with the kush
[01:03.71] Well, you're a rock student
[01:05.16] Bitch, don't get hit with the b- (ah)
[01:07.28] Oh, yeah, you're goin' stupid
[01:08.93] Oh, it's as good as it look
[01:14.36] I'm in love with the bitch, she a freak, geek show
[02:32.49] I'm in love with the bitch, she a freak, freak''';

void main() {
  final lrc = LrcParser.parse(griddle);
  final beats = BeatMap.parse(lrc.metadata[BeatMap.key]);
  final moments = resolveMoments(lrc.lines, beats);

  test('reads the box\'s beat line', () {
    expect(beats.drops.first, ms(1360));
    expect(beats.breaks, [(ms(56710), ms(60550)), (ms(63080), ms(67660))]);
    expect(beats.pulse.length, 6);
    expect(beats.quiet, [(ms(154230), ms(157330))]);
    expect(BeatMap.parse('drop=x,5;break=9-3;nonsense').drops, [ms(5)]);
    expect(BeatMap.parse(null).isEmpty, isTrue);
  });

  test('the opening (I-I-I) blooms onto the first hit', () {
    final m = moments.first;
    expect(m.kind, DropKind.grow);
    expect(m.text, 'I-I-I');
    expect(m.hit, ms(1360));
    expect(m.from, lessThan(m.hit));
  });

  test(
    "the (ah) after \"don't get hit with the b-\" grows through the break",
    () {
      final m = moments.firstWhere((m) => m.hit == ms(67660));
      expect(m.kind, DropKind.grow);
      expect(m.text, 'ah');
      expect(lrc.lines[m.line].text, contains("don't get hit"));
      // Heard at the line's end, while the 808 is still out.
      expect(m.from, greaterThan(ms(65160)));
      expect(m.from, lessThan(ms(67660)));
      // Shrinks back on the 808's hits after it returns.
      expect(m.steps, [ms(67610), ms(68950), ms(71170)]);
    },
  );

  test('grows until it crowds the others out, then shrinks hit by hit', () {
    final m = moments.firstWhere((m) => m.hit == ms(67660));
    expect(dropFrame(moments, m.from - ms(10)).isNone, isTrue);
    final mid = dropFrame(moments, m.from + (m.hit - m.from) ~/ 2);
    expect(mid.grow, inInclusiveRange(0.3, 0.7));
    final full = dropFrame(moments, m.hit - ms(5));
    expect(full.grow, greaterThan(0.95));
    expect(full.dim, greaterThan(0.8));
    // Each hit takes it down a step, with a squash as it lands.
    final s1 = dropFrame(moments, ms(67610 + 300));
    final s2 = dropFrame(moments, ms(68950 + 300));
    expect(s1.grow, closeTo(2 / 3, 0.01));
    expect(s2.grow, closeTo(1 / 3, 0.01));
    expect(dropFrame(moments, ms(68950 + 10)).punch, greaterThan(0.8));
    // The line being sung is back before the ones around it.
    final back = dropFrame(moments, ms(67700));
    expect(back.dimFor(0, ms(67660 + 300)), 0);
    expect(back.dimFor(3, ms(67660 + 300)), greaterThan(0));
    // And then it is over.
    expect(dropFrame(moments, ms(71170 + 400)).isNone, isTrue);
  });

  test('a drop with no ad-lib on it is left alone', () {
    expect(moments.any((m) => m.hit == ms(74700)), isFalse);
  });

  test('the words go quiet with the outro', () {
    final m = moments.last;
    expect(m.kind, DropKind.hush);
    expect(dropFrame(moments, ms(155500)).dim, greaterThan(0.8));
  });

  test('a break with no ad-lib in it is an impact', () {
    final lines = LrcParser.parse('[00:10.00] one\n[00:14.00] two').lines;
    final m = resolveMoments(
      lines,
      BeatMap(breaks: [(ms(9000), ms(14000))], drops: [ms(14000)]),
    );
    expect(m.single.kind, DropKind.impact);
    expect(dropFrame(m, ms(14150)).dim, 1);
    final f = dropFrame(m, ms(14150));
    expect(f.dimFor(0, ms(14200 + 300)), 0);
    expect(f.dimFor(2, ms(14200 + 100)), greaterThan(0.5));
  });

  test('a Lyric Center fix moves the ad-lib', () {
    final moved = resolveMoments(
      lrc.lines,
      beats,
      shiftOf: (line, word) =>
          lrc.lines[line].text.contains("don't get hit") ? ms(-1000) : ms(0),
    );
    final a = moments.firstWhere((m) => m.hit == ms(67660));
    final b = moved.firstWhere((m) => m.hit == ms(67660));
    expect(b.from, a.from - ms(1000));
  });
}
