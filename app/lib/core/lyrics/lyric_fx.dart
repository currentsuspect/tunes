/// Hand-set effects and timings for words and ad-libs: the Lyric Center's
/// fixes (lyric_center.dart). Everything else is estimated -- ad-libs placed
/// at the end of a line, picture words by their share of it, kinds read
/// from spelling -- and estimates are sometimes off. A listener holds the
/// line, picks the word or ad-lib, and says what it should be and when.
///
/// Kept in the lyric itself, as one metadata line other players skip:
///
///     [tunesfx:12.3=boom@+250;14.0=none@0;3.5=frost@-120]
///
/// `line.word` indexes the stored lyric (timed lines in order; words split
/// on spaces), `@` the shift in milliseconds. So a fix travels with the
/// words, is shared like any lyric edit, and is a labelled example for the
/// timing model.
library;

import 'adlib_kinds.dart';
import 'adlibs.dart' show adlibMask;
import 'word_fx.dart';

class FxFix {
  const FxFix(this.effect, this.shiftMs);

  /// An AdlibKind or WordFx name, or "none".
  final String effect;
  final int shiftMs;

  Duration get shift => Duration(milliseconds: shiftMs);

  AdlibKind? get adlibKind {
    for (final k in AdlibKind.values) {
      if (k.name == effect) return k;
    }
    return null;
  }

  WordFx? get wordFx {
    for (final f in WordFx.values) {
      if (f.name == effect) return f;
    }
    return null;
  }

  bool get isNone => effect == 'none';
}

class LyricFxTable {
  LyricFxTable([Map<String, FxFix>? fixes]) : fixes = fixes ?? {};

  /// The metadata key, as the parser stores it.
  static const key = 'tunesfx';

  final Map<String, FxFix> fixes;

  static String _k(int line, int word) => '$line.$word';

  FxFix? at(int line, int word) => fixes[_k(line, word)];

  void set(int line, int word, FxFix? fix) {
    if (fix == null) {
      fixes.remove(_k(line, word));
    } else {
      fixes[_k(line, word)] = fix;
    }
  }

  bool get isEmpty => fixes.isEmpty;

  /// Reads the metadata value; anything malformed is skipped, never fatal.
  static LyricFxTable parse(String? value) {
    final t = LyricFxTable();
    if (value == null) return t;
    for (final part in value.split(';')) {
      final m = RegExp(r'^\s*(\d+)\.(\d+)=([a-z]+)@([+-]?\d+)\s*$')
          .firstMatch(part);
      if (m == null) continue;
      t.fixes['${m.group(1)}.${m.group(2)}'] = FxFix(
        m.group(3)!,
        int.parse(m.group(4)!),
      );
    }
    return t;
  }

  String format() {
    final keys = fixes.keys.toList()
      ..sort((a, b) {
        final pa = a.split('.').map(int.parse).toList();
        final pb = b.split('.').map(int.parse).toList();
        return pa[0] != pb[0] ? pa[0] - pb[0] : pa[1] - pb[1];
      });
    return keys
        .map((k) {
          final f = fixes[k]!;
          final s = f.shiftMs >= 0 ? '+${f.shiftMs}' : '${f.shiftMs}';
          return '$k=${f.effect}@$s';
        })
        .join(';');
  }

  /// [lyrics] with this table as its tunesfx line: replaced if there was
  /// one, added at the top if not, removed when the table is empty. The
  /// rest of the text is left exactly as it was.
  String applyTo(String lyrics) {
    final lines = lyrics
        .split('\n')
        .where(
          (l) => !RegExp(r'^\s*\[tunesfx:', caseSensitive: false).hasMatch(l),
        )
        .toList();
    if (isEmpty) return lines.join('\n');
    return ['[$key:${format()}]', ...lines].join('\n');
  }
}

/// A line's effects with its fixes applied: which word is its picture word
/// and with what, each ad-lib word's kind, and how far each word's timing
/// is moved. One place, so the word-timed and line-timed views agree.
class LineFx {
  const LineFx({
    required this.whole,
    required this.picture,
    required this.kinds,
    required this.shifts,
  });

  /// The line is nothing but an ad-lib.
  final bool whole;

  /// The picture word, by token index, and its effect.
  final ({int index, WordFx fx})? picture;

  /// Ad-lib tokens and their kinds; a main word is absent.
  final Map<int, AdlibKind> kinds;

  /// Tokens whose timing a fix moved.
  final Map<int, Duration> shifts;

  Duration shiftOf(int i) => shifts[i] ?? Duration.zero;
}

/// Resolves [tokens] (a line's words, split on spaces) against its fixes.
/// [seed] null means picture words are off (the setting); fixes to ad-libs
/// still apply, since an ad-lib always has a look.
LineFx resolveLineFx(
  List<String> tokens, {
  int? seed,
  FxFix? Function(int i)? fixAt,
}) {
  FxFix? fix(int i) => fixAt?.call(i);
  final kinds = <int, AdlibKind>{};
  final shifts = <int, Duration>{};
  AdlibKind kindFor(int first, AdlibKind read) {
    final f = fix(first);
    if (f == null) return read;
    return f.adlibKind ?? (f.isNone ? AdlibKind.plain : read);
  }

  final whole = wholeLineAdlib(tokens);
  if (whole != null) {
    final k = kindFor(whole.words.first, whole.kind);
    final s = fix(whole.words.first)?.shift;
    for (final i in whole.words) {
      kinds[i] = k;
      if (s != null) shifts[i] = s;
    }
    return LineFx(whole: true, picture: null, kinds: kinds, shifts: shifts);
  }
  final mask = adlibMask(tokens);
  for (final g in adlibGroups(tokens, mask)) {
    final k = kindFor(g.words.first, g.kind);
    final s = fix(g.words.first)?.shift;
    for (final i in g.words) {
      kinds[i] = k;
      if (s != null) shifts[i] = s;
    }
  }
  ({int index, WordFx fx})? picture;
  if (seed != null) {
    final main = [
      for (var i = 0; i < tokens.length; i++)
        if (!mask[i]) i,
    ];
    // A word given an effect by hand comes first.
    for (final i in main) {
      final fx = fix(i)?.wordFx;
      if (fx != null) {
        picture = (index: i, fx: fx);
        break;
      }
    }
    if (picture == null) {
      final auto = lineWordFx([for (final i in main) tokens[i]], seed);
      if (auto != null && !(fix(main[auto.index])?.isNone ?? false)) {
        picture = (index: main[auto.index], fx: auto.fx);
      }
    }
    if (picture != null) {
      final s = fix(picture.index)?.shift;
      if (s != null) shifts[picture.index] = s;
    }
  }
  return LineFx(whole: false, picture: picture, kinds: kinds, shifts: shifts);
}
