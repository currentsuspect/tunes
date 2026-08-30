/// Parses LRC (Lyrics) format into timed lines.
///
/// LRC example:
///   [ar:Artist]
///   [ti:Title]
///   [00:12.34]First line of lyrics
///   [00:15.50]Second line
///   [00:20.00]Third line
///
/// Output: ordered list of [LrcLine] sorted by timestamp.
class LrcLine {
  const LrcLine({required this.timestamp, required this.text});
  final Duration timestamp;
  final String text;
}

class Lrc {
  const Lrc({
    this.metadata = const {},
    this.lines = const [],
    this.untimed = const [],
  });
  final Map<String, String> metadata;
  final List<LrcLine> lines;
  // Plain text without [mm:ss] timestamps. Rendered as a single block
  // when present (in lieu of timed lines).
  final List<String> untimed;

  bool get hasTimedLines => lines.isNotEmpty;
}

class LrcParser {
  /// Parse a string in LRC format. Returns an empty Lrc on empty /
  /// unparseable input; never throws.
  static Lrc parse(String input) {
    if (input.trim().isEmpty) return const Lrc();
    final metadata = <String, String>{};
    final lines = <LrcLine>[];
    final untimed = <String>[];
    for (final raw in input.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      // Metadata header: [key:value]
      final metaMatch = RegExp(r'^\[([a-zA-Z]+):(.*)\]$').firstMatch(line);
      if (metaMatch != null) {
        metadata[metaMatch.group(1)!.toLowerCase()] = metaMatch
            .group(2)!
            .trim();
        continue;
      }
      // Timed line: [mm:ss(.ss)?]text
      // Allow multiple timestamps per line (some lyrics repeat headers).
      // mm is unbounded: a 100+ minute track still round-trips.
      final tagIter = RegExp(r'\[(\d+):(\d{1,2})(?:[.:](\d{1,3}))?\]')
          .allMatches(line);
      final tags = [...tagIter];
      if (tags.isEmpty) {
        // Plain text without a timestamp — keep for non-timed display.
        if (line.isNotEmpty) untimed.add(line);
        continue;
      }
      final text = line.substring(tags.last.end).trim();
      if (text.isEmpty) continue;
      for (final t in tags) {
        final mm = int.parse(t.group(1)!);
        final ss = int.parse(t.group(2)!);
        final frac = t.group(3);
        var ms = 0;
        if (frac != null) {
          // Normalise fractional: ".5" = 500ms; ".50" = 500ms; ".123" = 123ms.
          final padded =
              '$frac'
                      '000'
                  .substring(0, 3);
          ms = int.parse(padded);
        }
        lines.add(
          LrcLine(
            timestamp: Duration(minutes: mm, seconds: ss, milliseconds: ms),
            text: text,
          ),
        );
      }
    }
    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return Lrc(metadata: metadata, lines: lines, untimed: untimed);
  }

  /// Find the active line for a given playback position. Returns null
  /// if the position is before the first line, or if there are no
  /// timed lines. If between two lines, returns the earlier one.
  static LrcLine? activeLine(Lrc lrc, Duration position) {
    if (lrc.lines.isEmpty) return null;
    if (position < lrc.lines.first.timestamp) return null;
    LrcLine result = lrc.lines.first;
    for (final l in lrc.lines) {
      if (l.timestamp > position) break;
      result = l;
    }
    return result;
  }

  /// Format the parsed lyrics back into LRC. Used by the in-app
  /// editor to save user-edited lines.
  static String format(Lrc lrc) {
    final buf = StringBuffer();
    for (final entry in lrc.metadata.entries) {
      buf.writeln('[${entry.key}:${entry.value}]');
    }
    for (final l in lrc.lines) {
      buf.writeln('[${_stamp(l.timestamp)}]${l.text}');
    }
    var s = buf.toString();
    if (s.endsWith('\n')) s = s.substring(0, s.length - 1);
    return s;
  }

  static String _stamp(Duration d) {
    // LRC's "mm" is total minutes, not modulo 60. A 1h05m track has
    // lines starting [65:00.00], not [05:00.00].
    final totalSeconds = d.inSeconds;
    final mm = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final ss = (totalSeconds % 60).toString().padLeft(2, '0');
    // Match the LRC convention of 2 fractional digits ("12.34"), not 3.
    final cs = (d.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(
      2,
      '0',
    );
    return '$mm:$ss.$cs';
  }
}
