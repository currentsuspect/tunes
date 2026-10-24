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
      // Peaks as the 808 returns, back to its size well before the next
      // hit: the word's moment, not the 808's.
      expect(m.steps, [ms(67660), ms(67895), ms(68130)]);
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
    // Each step takes it down a third, with a squash as it lands.
    final s1 = dropFrame(moments, ms(67660 + 200));
    final s2 = dropFrame(moments, ms(67895 + 200));
    expect(s1.grow, closeTo(2 / 3, 0.01));
    expect(s2.grow, closeTo(1 / 3, 0.01));
    expect(dropFrame(moments, ms(67895 + 10)).punch, greaterThan(0.8));
    // The line being sung is back before the ones around it.
    final back = dropFrame(moments, ms(67700));
    expect(back.dimFor(0, ms(67660 + 300)), 0);
    expect(back.dimFor(3, ms(67660 + 300)), greaterThan(0));
    // And then it is over: a second and a half at most.
    expect(dropFrame(moments, m.from + ms(1500)).isNone, isTrue);
  });

  test('no grow lasts more than 1.5 s, whatever the 808 does', () {
    for (final m in moments.where((m) => m.kind == DropKind.grow)) {
      expect(m.to - m.from, lessThanOrEqualTo(ms(1500)), reason: m.text);
      expect(m.to - m.from, greaterThanOrEqualTo(ms(900)), reason: m.text);
    }
    // Hits that fall in time are the steps.
    final beat = resolveMoments(
      lrc.lines,
      BeatMap.parse('drop=1360;pulse=1360,1700,2000,2300'),
    );
    expect(beat.first.steps, [ms(1360), ms(1700), ms(2000)]);
  });

  test('a section label left in a line never grows', () {
    final lines = LrcParser.parse(
      '[00:10.00] (Chorus: Fimiguerrero)\n[00:14.00] words (Segue)\n'
      '[00:18.00] more',
    ).lines;
    final m = resolveMoments(lines, BeatMap(drops: [ms(10100), ms(17800)]));
    expect(m.where((m) => m.kind == DropKind.grow), isEmpty);
  });

  test('impacts only where breaks are rare: the three longest, or none', () {
    final lines = LrcParser.parse('[00:01.00] one').lines;
    List<(Duration, Duration)> breaks(int n) => [
      for (var i = 0; i < n; i++)
        (ms(10000 * (i + 1)), ms(10000 * (i + 1) + 2000 + i * 100)),
    ];
    int impacts(int n) => resolveMoments(
      lines,
      BeatMap(breaks: breaks(n)),
    ).where((m) => m.kind == DropKind.grow).length;
    expect(impacts(2), 2);
    expect(impacts(5), 3);
    expect(impacts(16), 0);
  });

  test('a drop with no ad-lib on it is left alone', () {
    expect(moments.any((m) => m.hit == ms(74700)), isFalse);
  });

  test('the words go quiet with the outro', () {
    final m = moments.last;
    expect(m.kind, DropKind.hush);
    expect(dropFrame(moments, ms(155500)).dim, greaterThan(0.8));
  });

  test('a break with no ad-lib grows a word of the lyric, never a blank', () {
    // A line landing on the 808: its first word takes the moment.
    final lands = LrcParser.parse('[00:10.00] one\n[00:14.00] Money talks')
        .lines;
    final m = resolveMoments(
      lands,
      BeatMap(breaks: [(ms(9000), ms(14000))], drops: [ms(14000)]),
    );
    expect(m.single.kind, DropKind.grow);
    expect(m.single.text, 'Money');
    // The sheet is never wiped: lines stay faintly there under the word.
    for (var t = m.single.from; t < m.single.to; t += ms(50)) {
      expect(dropFrame(m, t).dim, lessThan(1), reason: '$t');
    }
    // Else the last real word sung before it, short and filler words passed.
    final before = LrcParser.parse(
      "[01:05.16] Bitch, don't get hit with the b-\n[01:09.00] next",
    ).lines;
    final w = resolveMoments(
      before,
      BeatMap(breaks: [(ms(63080), ms(67660))], drops: [ms(67660)]),
    );
    expect(w.single.text, 'hit');
    // A curly apostrophe is still a contraction.
    final curly = LrcParser.parse(
      '[00:10.00] you’re irreplaceable\n[00:14.00] next',
    ).lines;
    expect(
      resolveMoments(
        curly,
        BeatMap(breaks: [(ms(11000), ms(13000))], drops: [ms(13000)]),
      ).single.text,
      'irreplaceable',
    );
  });

  test('a Lyric Center fix moves the ad-lib', () {
    final moved = resolveMoments(
      lrc.lines,
      beats,
      shiftOf: (line, word) =>
          lrc.lines[line].text.contains("don't get hit") ? ms(-1000) : ms(0),
    );
    bool ah(DropMoment m) => m.text == 'ah' && m.from > ms(63000);
    final a = moments.firstWhere(ah);
    final b = moved.firstWhere(ah);
    expect(b.from, a.from - ms(1000));
    // Too early for the 808 to be its peak now, so it peaks on its own.
    expect(b.hit, b.from + ms(400));
  });
}
