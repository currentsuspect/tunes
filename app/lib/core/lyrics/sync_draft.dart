/// The in-progress state of a hand-made lyric sync.
///
/// Deliberately free of any Flutter import: this is where the decisions live
/// -- what counts as timed, what happens to lines that never got a mark, how
/// the result is serialised -- so they can be exercised directly rather than
/// only through a widget.
library;

import 'lrc_parser.dart';

/// Timings under construction, kept apart from the LRC text so a half-finished
/// sync is always representable.
///
/// A null entry means "not timed yet", which is a state the LRC format has no
/// way to express -- so the editor holds its own model and only serialises on
/// save.
class SyncDraft {
  SyncDraft(this.lines)
    : lineStarts = List<Duration?>.filled(lines.length, null),
      wordStarts = [
        for (final l in lines) List<Duration?>.filled(_wordsOf(l).length, null),
      ],
      wordEnds = [
        for (final l in lines) List<Duration?>.filled(_wordsOf(l).length, null),
      ];

  /// Source lyrics, one entry per line, already split into words for timing.
  final List<String> lines;
  final List<Duration?> lineStarts;
  final List<List<Duration?>> wordStarts;

  /// Where each word stops being sung, when it was marked. Optional: null
  /// reads as "until the next word", as before. A held note, a breath before
  /// the next word, a word cut short: only an end says which, and the timing
  /// model needs to know.
  final List<List<Duration?>> wordEnds;

  static List<String> _wordsOf(String line) =>
      line.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

  /// Section headers: `[Verse]`, `[Chorus 2]`, `(Bridge)` and friends.
  ///
  /// These are annotations, not words anybody sings, and timing them shifts
  /// the whole lyric by one line: the tap meant for the first sung line lands
  /// on the header, the next tap lands on the first line, and from then on
  /// every line displays the one before it.
  ///
  /// Square brackets always count -- LRC already reserves them for tags, so a
  /// whole line inside them is never lyric. Parentheses only count when the
  /// content names a section, because a parenthesised line is usually a
  /// backing vocal and very much sung.
  static final RegExp _squareHeader = RegExp(r'^\s*\[[^\]]*\]\s*$');
  static final RegExp _roundHeader = RegExp(
    r'^\s*\(\s*(pre[- ]?chorus|post[- ]?chorus|chorus|verse|hook|bridge|'
    r'intro|outro|refrain|interlude|break|drop|solo|coda|instrumental)'
    r'[^)]*\)\s*$',
    caseSensitive: false,
  );

  static bool isSectionHeader(String line) =>
      _squareHeader.hasMatch(line) || _roundHeader.hasMatch(line);

  bool isHeaderAt(int index) => isSectionHeader(lines[index]);

  List<String> wordsOf(int lineIndex) => _wordsOf(lines[lineIndex]);

  /// The first line still needing a mark, or null when the timing is done.
  ///
  /// Skips section headers: they are never tapped, so leaving them in the
  /// cursor's path is what put every timestamp one line too high.
  int? get nextUntimedLine {
    for (var i = 0; i < lineStarts.length; i++) {
      if (isHeaderAt(i)) continue;
      if (lineStarts[i] == null) return i;
    }
    return null;
  }

  int? nextUntimedWord(int lineIndex) {
    final w = wordStarts[lineIndex];
    for (var i = 0; i < w.length; i++) {
      if (w[i] == null) return i;
    }
    return null;
  }

  int get timedLineCount => lineStarts.where((d) => d != null).length;

  /// Lines that still need a mark, headers excluded -- otherwise the editor
  /// reports work outstanding that it will never ask anyone to do.
  int get untimedLineCount {
    var n = 0;
    for (var i = 0; i < lines.length; i++) {
      if (!isHeaderAt(i) && lineStarts[i] == null) n++;
    }
    return n;
  }

  /// The last line carrying a mark, headers skipped.
  ///
  /// Undo used to walk back one slot from the cursor, but the cursor already
  /// skips headers -- so the slot behind it could be a header, which never
  /// has a mark. Clearing it changed nothing, the cursor stayed put, and undo
  /// stopped dead after a single step.
  int? get lastMarkedLine {
    for (var i = lines.length - 1; i >= 0; i--) {
      if (isHeaderAt(i)) continue;
      if (lineStarts[i] != null) return i;
    }
    return null;
  }

  /// The last word of [lineIndex] carrying a mark.
  int? lastMarkedWord(int lineIndex) {
    final words = wordStarts[lineIndex];
    for (var i = words.length - 1; i >= 0; i--) {
      if (words[i] != null) return i;
    }
    return null;
  }

  /// Moves every mark by [by], for when the whole take is consistently late.
  /// Nudging one mark at a time is fine for a slip; it is not a way to fix
  /// forty lines recorded a beat behind.
  void shiftAll(Duration by) {
    for (var i = 0; i < lineStarts.length; i++) {
      final t = lineStarts[i];
      if (t != null) lineStarts[i] = _atLeastZero(t + by);
      for (var w = 0; w < wordStarts[i].length; w++) {
        final v = wordStarts[i][w];
        if (v != null) wordStarts[i][w] = _atLeastZero(v + by);
        final e = wordEnds[i][w];
        if (e != null) wordEnds[i][w] = _atLeastZero(e + by);
      }
    }
  }

  static Duration _atLeastZero(Duration d) => d.isNegative ? Duration.zero : d;

  /// The mark on the first timed, non-header line after [from].
  Duration? _startOfNextTimed(int from) {
    for (var i = from + 1; i < lines.length; i++) {
      if (isHeaderAt(i)) continue;
      final t = lineStarts[i];
      if (t != null) return t;
    }
    return null;
  }

  bool get anyTimed => timedLineCount > 0;

  /// Serialise to Enhanced LRC.
  ///
  /// Timing runs top-down, so untimed lines are always a suffix. They are
  /// written as plain text after the timed ones rather than dropped: a save
  /// must never lose words the user typed, even if the sync is unfinished.
  String toLrc({Map<String, String> metadata = const {}}) {
    final timed = <LrcLine>[];
    final leftover = <String>[];
    for (var i = 0; i < lines.length; i++) {
      // A header is never tapped, so it borrows the start of the verse it
      // introduces. That keeps it in place on screen, and because the line
      // after it shares the timestamp the highlight passes straight through
      // rather than resting on a word nobody sings.
      final start = isHeaderAt(i) ? _startOfNextTimed(i) : lineStarts[i];
      if (start == null) {
        if (lines[i].trim().isNotEmpty) leftover.add(lines[i].trim());
        continue;
      }
      final words = wordsOf(i);
      final stamps = wordStarts[i];
      // Word timing is all-or-nothing per line. A line with only some words
      // timed would sweep to a word and then stop, which reads as a bug
      // rather than as unfinished work.
      final complete =
          words.isNotEmpty &&
          stamps.length == words.length &&
          stamps.every((d) => d != null);
      timed.add(
        LrcLine(
          timestamp: start,
          text: lines[i].trim(),
          words: complete
              ? [
                  for (var w = 0; w < words.length; w++)
                    LrcWord(
                      text: words[w],
                      start: stamps[w]!,
                      // An end before its own start is a slip, not a word.
                      end:
                          wordEnds[i][w] != null && wordEnds[i][w]! > stamps[w]!
                          ? wordEnds[i][w]
                          : null,
                    ),
                ]
              : const [],
        ),
      );
    }
    // Metadata rides along: the Lyric Center's fixes live there, and a
    // re-timed save must not drop them.
    final body = LrcParser.format(Lrc(metadata: metadata, lines: timed));
    if (leftover.isEmpty) return body;
    return body.isEmpty ? leftover.join('\n') : '$body\n${leftover.join('\n')}';
  }
}
