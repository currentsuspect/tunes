/// What kind of ad-lib a bracketed group is, read from its words.
///
/// Underground records live on their ad-libs: growls, the "brr"s and
/// "baow"s, whispers, an echo of the last word. Each kind is shown its own
/// way (adlib_motion.dart). This only reads the text: nothing is changed or
/// stored, and an unknown ad-lib is just an ad-lib.
library;

import 'dart:math' as math;

enum AdlibKind { plain, growl, effect, boom, whisper, echo, hype, stutter, tag }

String _norm(String s) => s
    .toLowerCase()
    // "Ooh-yeah" is two sounds; "lil'" is one word.
    .replaceAll(RegExp(r'[-–—]'), ' ')
    .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// The ones that land like a hit: buh, boom, bang, baow, blaow, pow.
final RegExp _boom = RegExp(
  r'^(bu+h+|bo+m+|ba+n+g+|ba+o+w+|bl+a+o+w+|po+w+|pa+o+w+|bo+w+)$',
);

/// Sound effects, the "B sounds": brr, skrrt, baow, pew, bop, boom.
final RegExp _effect = RegExp(
  r'^(b+r+t*|bu+h+|sk+r+t*|ba+o+w+|bl+a+o+w+|bo+w+|pe+w+|bo+p+|bo+m+|ba+n+g+|pa+o+w*|pow+|bla+h+|grra+h+|do+t+|vr+o+m+|ding+|chi+n+g+|clack|bah+|tsk+|bru+h+)$',
);

/// Growls and grunts: grr, rrr, ugh, argh, huh, hmm.
final RegExp _growl = RegExp(
  r'^(g+r+|r{3,}|u+g+h+|a+r+g+h+|hu+h+|hm+|mh+|m{3,}|e+h+|gr+a+h+|nyeh+)$',
);

/// Hype: yeah, what, ayy, let's go, woah, okay, go.
final RegExp _hype = RegExp(
  r'^(ye+a+h*|ye+h+|yuh+|wha+t+|a+y+|ay+e+|lets go+|woa+h+|wo+|o+h+|o+ka+y+|go+|gang|uh+|ha+|haha+|hahaha+|what what|yeah yeah)$',
);

/// Whispered, said so or written so: "(whisper)", "shh", a trailing "…".
bool _whisper(String raw, String n) =>
    RegExp(r'whisper', caseSensitive: false).hasMatch(raw) ||
    RegExp(r'^(s+h+|ps+t+)$').hasMatch(n) ||
    raw.contains('…') ||
    raw.contains('...');

/// A vocal chop: "I-I-I-I—", "it-it-it", a word cut off with a dash.
bool _stutter(String raw) {
  final parts = raw
      .replaceAll(RegExp(r'[()\[\],.!?]'), '')
      .split(RegExp(r'[-–]'));
  if (parts.length >= 3) {
    final first = parts.first.toLowerCase().trim();
    if (first.isNotEmpty &&
        parts.take(3).every((p) => p.toLowerCase().trim() == first)) {
      return true;
    }
  }
  return RegExp(r'[-–]?—\)?$').hasMatch(raw.trim()) && raw.contains('-');
}

/// A producer's tag said over the beat: a lone name in capitals ("BNYX"), or
/// one of the tags known by heart.
final RegExp _knownTag = RegExp(
  r'^(bnyx|wheezy|metro boomin|metro|pierre|f1lthy|cardo|cashmoneyap|nick mira|taz taylor|southside|808 mafia|murda|tay keith|sonic|lukrative|synthetic)$',
);

bool _tag(String raw, String n) {
  final inner = raw.replaceAll(RegExp(r'[()\[\]]'), '').trim();
  if (_knownTag.hasMatch(n.replaceAll("'", ''))) return true;
  return RegExp(r'^[A-Z0-9]{3,8}$').hasMatch(inner) &&
      !RegExp(r'^(YEAH|WOAH|WHAT|AYY|WOO|SKRRT|BRR|GRR)$').hasMatch(inner);
}

/// The kind of the ad-lib [raw] (with its brackets), sung after [main], the
/// words of the line it belongs to. [alone] is a line that is nothing but
/// this ad-lib, where a producer's tag is said.
AdlibKind classifyAdlib(String raw, {String main = '', bool alone = false}) {
  final n = _norm(raw);
  if (n.isEmpty) return AdlibKind.plain;
  if (alone && _tag(raw, n)) return AdlibKind.tag;
  if (_whisper(raw, n)) return AdlibKind.whisper;
  if (_stutter(raw)) return AdlibKind.stutter;
  // Words from the end of the line said again: "lil' bitty bitch (Lil'
  // bitty)", "stuck in a maze (maze)".
  final mainWords = _norm(main).split(' ').where((w) => w.isNotEmpty).toList();
  if (mainWords.isNotEmpty) {
    final tail = mainWords.skip(math.max(0, mainWords.length - 5)).toSet();
    final said = n.split(' ');
    if (said.every(tail.contains)) return AdlibKind.echo;
  }
  final words = n.split(' ');
  if (words.every(_boom.hasMatch)) return AdlibKind.boom;
  if (words.every(_effect.hasMatch)) return AdlibKind.effect;
  if (words.every(_growl.hasMatch)) return AdlibKind.growl;
  if (_hype.hasMatch(n) || words.every(_hype.hasMatch)) return AdlibKind.hype;
  return AdlibKind.plain;
}

/// Ad-lib groups in a line: each run of bracketed words, by word index, and
/// its kind. [mask] is adlibMask's answer for [tokens].
///
/// [mainText] is the line's main words, when [tokens] holds only ad-libs.
List<({List<int> words, AdlibKind kind})> adlibGroups(
  List<String> tokens,
  List<bool> mask, {
  String? mainText,
}) {
  final main =
      mainText ??
      [
        for (var i = 0; i < tokens.length; i++)
          if (!mask[i]) tokens[i],
      ].join(' ');
  final out = <({List<int> words, AdlibKind kind})>[];
  var cur = <int>[];
  void close() {
    if (cur.isEmpty) return;
    final raw = [for (final i in cur) tokens[i]].join(' ');
    out.add((words: cur, kind: classifyAdlib(raw, main: main)));
    cur = <int>[];
  }

  var depth = 0;
  for (var i = 0; i < tokens.length; i++) {
    if (!mask[i]) {
      close();
      depth = 0;
      continue;
    }
    final t = tokens[i];
    if (depth == 0 && cur.isNotEmpty && RegExp(r'^[(\[]').hasMatch(t)) close();
    cur.add(i);
    depth += RegExp(r'[(\[]').allMatches(t).length;
    depth -= RegExp(r'[)\]]').allMatches(t).length;
    if (depth <= 0) {
      depth = 0;
      close();
    }
  }
  close();
  return out;
}

/// A line that is nothing but ad-libs ("(Woo)", "(Yank on it)"), as one
/// group, or null when the line has words of its own.
({List<int> words, AdlibKind kind})? wholeLineAdlib(List<String> tokens) {
  if (tokens.isEmpty) return null;
  final raw = tokens.join(' ').trim();
  if (!RegExp(r'^[(\[].*[)\]]$').hasMatch(raw)) return null;
  return (
    words: [for (var i = 0; i < tokens.length; i++) i],
    kind: classifyAdlib(raw, alone: true),
  );
}

/// When ad-libs are heard on a line with no word timing.
///
/// Almost always at its end, in the last few hundred milliseconds before the
/// next line: so that is where they are put, the last ending as the next
/// line starts and any before it staggered back from there. One written
/// before the line's first word is heard as the line starts. [starts] says,
/// per group, whether it opens the line.
List<({Duration start, Duration end})> estimatedAdlibTimes(
  Duration lineStart,
  Duration? nextStart,
  List<bool> starts,
) {
  final next = nextStart != null && nextStart > lineStart
      ? nextStart
      : lineStart + const Duration(seconds: 4);
  const each = Duration(milliseconds: 350);
  const gap = Duration(milliseconds: 120);
  final tailCount = starts.where((s) => !s).length;
  var k = 0;
  return [
    for (final opens in starts)
      if (opens)
        (start: lineStart, end: lineStart + each)
      else
        () {
          final fromEnd = tailCount - k++;
          var start = next - (each + gap) * fromEnd + gap;
          // Never before the line itself.
          if (start < lineStart) start = lineStart;
          return (start: start, end: start + each);
        }(),
  ];
}

/// Placeholders a lyric site leaves for words nobody could make out.
bool isPlaceholder(String token) =>
    RegExp(r'^[\[(]\?+[\])][,.]?$').hasMatch(token);
