/// How a word moves while it is sung: everything derived from its start, its
/// end and the playhead, so a frame can be drawn from the time alone and a
/// seek lands in the right state with nothing to catch up.
///
/// With word ends in the lyric (NetEase's timing, the editor's End marks), a
/// held note and the breath after it read differently: the word swells and
/// glows for as long as it is held, and settles the moment it stops. Without
/// an end, a word runs until the next one starts, as before.
library;

class WordMotion {
  const WordMotion({
    required this.fill,
    required this.lift,
    required this.glow,
  });

  /// How much of the word is lit, 0 to 1, swept left to right.
  final double fill;

  /// How far the word is raised, 0 to 1: up as it starts, down as it ends.
  final double lift;

  /// A held note's glow, 0 to 1: builds over the hold, fades as it ends.
  final double glow;

  static const ahead = WordMotion(fill: 0, lift: 0, glow: 0);
  static const done = WordMotion(fill: 1, lift: 0, glow: 0);
}

/// A note held at least this long glows.
const Duration kHeldNote = Duration(milliseconds: 600);

/// How long a word takes to rise as it starts, and to settle as it ends.
const Duration kRise = Duration(milliseconds: 120);
const Duration kSettle = Duration(milliseconds: 180);

WordMotion wordMotion({
  required Duration start,
  required Duration end,
  required Duration position,
}) {
  if (position < start) return WordMotion.ahead;
  final span = (end - start).inMilliseconds;
  final into = (position - start).inMilliseconds;
  if (span <= 0) return WordMotion.done;
  if (into < span) {
    final held = end - start >= kHeldNote;
    // The glow waits out the first stretch of the note, so a word only glows
    // once it is clearly being held, then builds to the end.
    final glowFrom = kHeldNote.inMilliseconds ~/ 2;
    return WordMotion(
      fill: into / span,
      lift: _ease((into / kRise.inMilliseconds).clamp(0.0, 1.0)),
      glow: held ? ((into - glowFrom) / (span - glowFrom)).clamp(0.0, 1.0) : 0,
    );
  }
  final after = into - span;
  if (after >= kSettle.inMilliseconds) return WordMotion.done;
  final left = 1 - _ease(after / kSettle.inMilliseconds);
  return WordMotion(
    fill: 1,
    lift: left,
    glow: end - start >= kHeldNote ? left : 0,
  );
}

double _ease(double t) => 1 - (1 - t) * (1 - t);
