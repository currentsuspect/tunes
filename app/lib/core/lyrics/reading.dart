/// Lyrics laid out for reading: one long line becomes two short ones.
///
/// A line wider than a phone was either shrunk until it fit (the player's
/// preview) or wrapped to three and four rows (the lyrics sheet), and both
/// are hard to follow at a glance. Splitting it into two lines of their own
/// keeps every line at a readable size, and on word-timed lyrics the second
/// half lights up when its own first word is sung.
///
/// Display only: what is stored, shared and edited is the original text.
/// [ReadingLrc.origin] maps every shown line back to the line it came from,
/// for anything that writes (a voice label, a share).
library;

import 'lrc_parser.dart';
import 'voices.dart';

/// A line longer than this many characters is split. Fits a phone's width at
/// the player's lyric size with room to spare.
const int kReadingLineChars = 42;

class ReadingLrc {
  const ReadingLrc(this.lrc, this.origin);

  /// The lines as shown.
  final Lrc lrc;

  /// For each shown line, the index of the stored line it came from.
  final List<int> origin;
}

ReadingLrc splitForReading(Lrc lrc, {int maxChars = kReadingLineChars}) {
  final lines = <LrcLine>[];
  final origin = <int>[];
  for (var i = 0; i < lrc.lines.length; i++) {
    final line = lrc.lines[i];
    final next = i + 1 < lrc.lines.length ? lrc.lines[i + 1].timestamp : null;
    final halves = _split(line, next, maxChars);
    for (final h in halves) {
      lines.add(h);
      origin.add(i);
    }
  }
  return ReadingLrc(
    Lrc(metadata: lrc.metadata, lines: lines, untimed: lrc.untimed),
    origin,
  );
}

List<LrcLine> _split(LrcLine line, Duration? nextStart, int maxChars) {
  final shown = LyricVoices.plain(line.text);
  if (shown.length <= maxChars) return [line];
  final tokens = line.hasWordTiming
      ? [for (final w in line.words) w.text]
      : line.text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  if (tokens.length < 4) return [line];
  // A voice label ("v2:") belongs with the words after it.
  final first = LyricVoices.labelOf(line.text) != null ? 2 : 1;
  final at = _bestBreak(tokens, first, maxChars);
  if (at == null) return [line];

  final leftText = tokens.sublist(0, at).join(' ');
  final rightText = tokens.sublist(at).join(' ');
  if (line.hasWordTiming) {
    final rightWords = line.words.sublist(at);
    return [
      LrcLine(
        timestamp: line.timestamp,
        text: leftText,
        words: line.words.sublist(0, at),
      ),
      LrcLine(
        timestamp: rightWords.first.start,
        text: rightText,
        words: rightWords,
      ),
    ];
  }
  // Line-timed: the second half starts about as far into the line's time as
  // it is into its words. Close enough to move the highlight on at the right
  // moment; it is never written anywhere.
  final span = nextStart != null && nextStart > line.timestamp
      ? nextStart - line.timestamp
      : const Duration(seconds: 4);
  final share = leftText.length / (leftText.length + rightText.length);
  final secondAt =
      line.timestamp +
      Duration(milliseconds: (span.inMilliseconds * share * 0.92).round());
  return [
    LrcLine(timestamp: line.timestamp, text: leftText),
    LrcLine(timestamp: secondAt, text: rightText),
  ];
}

/// Where to break [tokens]. A break where the words breathe (after a
/// sentence end, then after a comma) wins whenever it leaves both halves
/// short enough to read; otherwise the gap nearest the middle. Never inside
/// brackets, and never leaving a single word on either side.
int? _bestBreak(List<String> tokens, int first, int maxChars) {
  final total = tokens.join(' ').length;
  int? best;
  var bestScore = double.infinity;
  var depth = 0;
  var left = -1;
  for (var i = 0; i < tokens.length - 1; i++) {
    final t = tokens[i];
    depth += '('.allMatches(t).length + '['.allMatches(t).length;
    depth -= ')'.allMatches(t).length + ']'.allMatches(t).length;
    if (depth < 0) depth = 0;
    left += t.length + 1;
    final at = i + 1;
    if (at < first + 1 || tokens.length - at < 2) continue;
    if (depth > 0) continue;
    final right = total - left - 1;
    final fits = left <= maxChars && right <= maxChars;
    final pause = RegExp(r'[?!.]$').hasMatch(t)
        ? 2
        : RegExp(r'[,;:]$').hasMatch(t) || tokens[at].startsWith('(')
        ? 1
        : 0;
    // Breathing places that fit come first, sentence ends before commas;
    // balance decides within each tier.
    final tier = fits && pause > 0 ? 2 - pause : 2;
    final score = tier * 1000.0 + (left - right).abs();
    if (score < bestScore) {
      bestScore = score;
      best = at;
    }
  }
  return best;
}
