import 'lrc_parser.dart';

/// Which side of the screen a lyric line sits on, by who is singing it.
///
/// Lyrics from LRCLIB carry no singer, so this reads what there is:
///
///   * a label at the start of the line: `v1:` / `v2:`, `M:` / `F:`, `D:` or
///     `Both:` (the enhanced-LRC convention), or the name of one of the
///     track's own artists (`Kendrick:`);
///   * a line wholly in brackets, `(like this)`, which is a backing vocal.
///
/// The first voice heard sits on the left, the second on the right, a line
/// for both is centred, and a backing vocal sits on the right and quieter. A
/// line with no label carries on with whoever sang the one before it, so a
/// verse is labelled once, not on every line.
///
/// Pure and view-side on purpose: the stored lyric text is never rewritten to
/// make this work, so any other LRC reader still sees ordinary lines.
enum LyricSide { left, right, center }

class LyricVoice {
  const LyricVoice(this.side, this.text, {this.backing = false});

  final LyricSide side;

  /// The line as it should be shown, with any label removed.
  final String text;

  /// A backing vocal: set smaller and dimmer than the lead.
  final bool backing;
}

class LyricVoices {
  /// Labels that mean "the next voice" without naming anyone.
  static final RegExp _label = RegExp(
    r'^\s*([A-Za-z][A-Za-z0-9 .&'
    "'"
    r'-]{0,30}?)\s*:\s+(\S.*)$',
  );
  static final RegExp _voiceN = RegExp(r'^v(\d)$', caseSensitive: false);

  static const _both = {'d', 'both', 'duet', 'all', 'together'};
  static const _male = {'m', 'male'};
  static const _female = {'f', 'female'};

  /// Resolves every line of [lines] in order. [artists] are the track's own
  /// artists (lead and featured), the only names accepted as a label.
  static List<LyricVoice> resolve(
    List<String> lines, {
    List<String> artists = const [],
  }) {
    final names = [for (final a in artists) _norm(a)]
      ..removeWhere((a) => a.isEmpty);
    // Voices in the order they first sing: index 0 is left, 1 is right.
    final heard = <String>[];
    var current = 0; // 0 left, 1 right
    final out = <LyricVoice>[];
    for (final raw in lines) {
      var text = raw.trim();
      var both = false;
      final m = _label.firstMatch(text);
      if (m != null) {
        final key = _keyFor(m.group(1)!, names);
        if (key != null) {
          text = m.group(2)!.trim();
          if (key == '*') {
            both = true;
          } else if (_voiceN.hasMatch(key)) {
            // Explicit numbers are absolute: v1 is always the left-hand voice,
            // so one line can be labelled without having to label the first.
            current = key == 'v1' ? 0 : 1;
          } else {
            var at = heard.indexOf(key);
            if (at < 0) {
              heard.add(key);
              at = heard.length - 1;
            }
            current = at;
          }
        }
      }
      if (_isBacking(text)) {
        out.add(LyricVoice(LyricSide.right, text, backing: true));
        continue;
      }
      out.add(
        LyricVoice(
          both
              ? LyricSide.center
              : current == 0
              ? LyricSide.left
              : LyricSide.right,
          text,
        ),
      );
    }
    return out;
  }

  /// The label a line starts with, or null when it has none that counts.
  /// Returned in the form [withVoice] writes, for the editor to show.
  static String? labelOf(String line) {
    final m = _label.firstMatch(line.trim());
    if (m == null) return null;
    final key = m.group(1)!.trim();
    return _voiceN.hasMatch(key) ? key.toLowerCase() : null;
  }

  /// [line] as it reads without a `v1:` / `v2:` label, for screens that show
  /// a line but do not place it.
  static String plain(String line) =>
      labelOf(line) == null ? line : withVoice(line, null);

  /// [line] with its leading `v1:` / `v2:` label replaced by [voice] (1 or 2),
  /// or removed when [voice] is null. Names and other labels are left alone.
  static String withVoice(String line, int? voice) {
    final trimmed = line.trim();
    final existing = labelOf(trimmed);
    final body = existing == null
        ? trimmed
        : _label.firstMatch(trimmed)!.group(2)!;
    return voice == null ? body : 'v$voice: $body';
  }

  /// [raw] with line [index] of [lrc] set to [voice] (1 left, 2 right, null
  /// for no label). Null when that line cannot be found in [raw] or carries
  /// word timing, which a label would corrupt.
  ///
  /// Because an unlabelled line follows the one before it, relabelling one
  /// line would drag every line after it to the same side. So the next line is
  /// pinned to the side it had, unless it already says where it sits.
  static String? relabel(
    String raw,
    Lrc lrc,
    int index,
    int? voice, {
    List<String> artists = const [],
  }) {
    if (index < 0 || index >= lrc.lines.length) return null;
    final target = lrc.lines[index];
    if (target.hasWordTiming) return null;
    final before = resolve([
      for (final l in lrc.lines) l.text,
    ], artists: artists);
    final rows = raw.split('\n');
    final tagged = RegExp(r'^(\s*(?:\[\d+:\d+(?:[.:]\d+)?\])+)(.*)$');

    bool rewrite(LrcLine line, int? to) {
      for (var k = 0; k < rows.length; k++) {
        final m = tagged.firstMatch(rows[k]);
        if (m == null) continue;
        final parsed = LrcParser.parse(rows[k]).lines;
        if (parsed.length != 1 || parsed.first.hasWordTiming) continue;
        if (parsed.first.timestamp != line.timestamp ||
            parsed.first.text != line.text) {
          continue;
        }
        rows[k] = '${m.group(1)}${withVoice(m.group(2)!, to)}';
        return true;
      }
      return false;
    }

    if (!rewrite(target, voice)) return null;
    final following = index + 1;
    if (following < lrc.lines.length &&
        !before[following].backing &&
        labelOf(lrc.lines[following].text) == null) {
      final after = resolve([
        for (var i = 0; i < lrc.lines.length; i++)
          i == index ? withVoice(lrc.lines[i].text, voice) : lrc.lines[i].text,
      ], artists: artists);
      if (after[following].side != before[following].side &&
          before[following].side != LyricSide.center) {
        rewrite(
          lrc.lines[following],
          before[following].side == LyricSide.right ? 2 : 1,
        );
      }
    }
    return rows.join('\n');
  }

  static bool _isBacking(String text) =>
      text.length > 2 && text.startsWith('(') && text.endsWith(')');

  static String? _keyFor(String label, List<String> names) {
    final l = label.trim().toLowerCase();
    if (_both.contains(l)) return '*';
    if (_voiceN.hasMatch(l)) return l;
    if (_male.contains(l)) return 'm';
    if (_female.contains(l)) return 'f';
    final n = _norm(label);
    if (n.length < 3) return null;
    for (final a in names) {
      if (a == n || a.startsWith('$n ') || a.contains(' $n')) return a;
    }
    return null;
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
