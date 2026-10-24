/// Where to look for a word's start or end while timing words by hand.
///
/// Nobody taps fast enough to mark word after word as the song plays, so
/// words are timed one at a time, paused: scrub to the start, mark it, scrub
/// to the end, mark it. The window is the stretch of song the scrubber
/// covers for that one step -- small, so a drag is precise, and placed where
/// the sound has to be:
///
///   start: from the previous mark (where the last word ended, or began) to
///          the end of the line -- the next word cannot start before the
///          last one did.
///   end:   from just after the word's start, for a range the listener
///          picks, because how long a word lasts varies song to song and
///          tempo to tempo.
library;

import 'sync_draft.dart';

enum WordPhase { start, end }

/// The window for [phase] of word [word] on line [line].
///
/// [lineEnd] is where the next line starts, when known. [endRange] is the
/// listener's chosen length for end windows.
({Duration from, Duration to}) wordWindow(
  SyncDraft d,
  int line,
  int word,
  WordPhase phase, {
  required Duration endRange,
  Duration? lineEnd,
}) {
  if (phase == WordPhase.end) {
    final start =
        d.wordStarts[line][word] ?? d.lineStarts[line] ?? Duration.zero;
    // A few milliseconds in: the end is never on the start.
    final from = start + const Duration(milliseconds: 20);
    return (from: from, to: from + endRange);
  }
  // The previous mark on this line, latest first: an end, else a start.
  Duration? anchor;
  for (var w = word - 1; w >= 0 && anchor == null; w--) {
    anchor = d.wordEnds[line][w] ?? d.wordStarts[line][w];
  }
  final Duration from;
  if (anchor != null) {
    from = anchor;
  } else {
    // The first word: a little before the line's mark, which was tapped live
    // and may be late.
    final ls = d.lineStarts[line] ?? Duration.zero;
    final lead = ls - const Duration(milliseconds: 400);
    from = lead.isNegative ? Duration.zero : lead;
  }
  var to = lineEnd ?? from + const Duration(seconds: 6);
  // Never a sliver, never the rest of the song.
  if (to < from + const Duration(milliseconds: 800)) {
    to = from + const Duration(milliseconds: 800);
  }
  if (to > from + const Duration(seconds: 12)) {
    to = from + const Duration(seconds: 12);
  }
  return (from: from, to: to);
}

/// The choices offered for an end window's length.
const List<Duration> kEndRanges = [
  Duration(milliseconds: 300),
  Duration(milliseconds: 500),
  Duration(milliseconds: 800),
  Duration(milliseconds: 1200),
  Duration(seconds: 2),
];
