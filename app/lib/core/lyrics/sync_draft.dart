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
      ];

  /// Source lyrics, one entry per line, already split into words for timing.
  final List<String> lines;
  final List<Duration?> lineStarts;
  final List<List<Duration?>> wordStarts;

  static List<String> _wordsOf(String line) =>
      line.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

  List<String> wordsOf(int lineIndex) => _wordsOf(lines[lineIndex]);

  /// The first line with no timestamp, or null when every line is timed.
  int? get nextUntimedLine {
    for (var i = 0; i < lineStarts.length; i++) {
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

  bool get anyTimed => timedLineCount > 0;

  /// Serialise to Enhanced LRC.
  ///
  /// Timing runs top-down, so untimed lines are always a suffix. They are
  /// written as plain text after the timed ones rather than dropped: a save
  /// must never lose words the user typed, even if the sync is unfinished.
  String toLrc() {
    final timed = <LrcLine>[];
    final leftover = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final start = lineStarts[i];
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
                    LrcWord(text: words[w], start: stamps[w]!),
                ]
              : const [],
        ),
      );
    }
    final body = LrcParser.format(Lrc(lines: timed));
    if (leftover.isEmpty) return body;
    return body.isEmpty ? leftover.join('\n') : '$body\n${leftover.join('\n')}';
  }
}
