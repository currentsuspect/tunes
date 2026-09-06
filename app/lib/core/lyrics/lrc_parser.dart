/// Parses LRC (Lyrics) format into timed lines, including per-word timing.
///
/// LRC example:
///   [ar:Artist]
///   [ti:Title]
///   [00:12.34]First line of lyrics
///   [00:15.50]Second line
///
/// Enhanced LRC ("A2") adds a timestamp before each word:
///   [00:12.40]<00:12.40>I <00:12.72>remember <00:13.41>the <00:13.72>night
///
/// The enhanced form is what this app stores once a line has been word-synced.
/// It is a real, existing convention rather than a private format, which buys
/// three things: it round-trips through the same `lyrics` text column with no
/// schema change, any other player that reads LRC still sees correct lines,
/// and [toPlainLrc] downgrades it losslessly for export.
///
/// Output: ordered list of [LrcLine] sorted by timestamp.
class LrcWord {
  const LrcWord({required this.text, required this.start});

  final String text;
  final Duration start;

  /// Words carry only a start. The end is whatever comes next -- the following
  /// word, or the following line -- so a correction to one timestamp cannot
  /// leave a stale end behind it. [Lrc.wordEndOf] resolves it.
  @override
  bool operator ==(Object other) =>
      other is LrcWord && other.text == text && other.start == start;

  @override
  int get hashCode => Object.hash(text, start);
}

class LrcLine {
  const LrcLine({
    required this.timestamp,
    required this.text,
    this.words = const [],
  });

  final Duration timestamp;
  final String text;

  /// Per-word timings, empty when the line is only line-synced. [text] stays
  /// authoritative for display, so a line renders identically either way.
  final List<LrcWord> words;

  bool get hasWordTiming => words.isNotEmpty;

  LrcLine copyWith({Duration? timestamp, String? text, List<LrcWord>? words}) {
    return LrcLine(
      timestamp: timestamp ?? this.timestamp,
      text: text ?? this.text,
      words: words ?? this.words,
    );
  }
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

  /// True when at least one line carries word timings, which is what decides
  /// whether the view can highlight within a line rather than per line.
  bool get hasWordTiming => lines.any((l) => l.hasWordTiming);

  /// When the word at [wordIndex] of [lineIndex] stops being the active one.
  ///
  /// Derived rather than stored: the next word's start, else the next line's
  /// start, else [trackEnd]. The final fallback keeps the last word of the
  /// last line from having zero width when the duration is unknown.
  Duration wordEndOf(int lineIndex, int wordIndex, {Duration? trackEnd}) {
    final line = lines[lineIndex];
    if (wordIndex + 1 < line.words.length) {
      return line.words[wordIndex + 1].start;
    }
    if (lineIndex + 1 < lines.length) return lines[lineIndex + 1].timestamp;
    if (trackEnd != null && trackEnd > line.words[wordIndex].start) {
      return trackEnd;
    }
    return line.words[wordIndex].start + const Duration(milliseconds: 800);
  }
}

class LrcParser {
  /// Matches a line-level `[mm:ss(.ff)]` tag. mm is unbounded: a 100+ minute
  /// track still round-trips.
  static final RegExp _lineTag = RegExp(
    r'\[(\d+):(\d{1,2})(?:[.:](\d{1,3}))?\]',
  );

  /// Matches a word-level `<mm:ss(.ff)>` tag.
  static final RegExp _wordTag = RegExp(r'<(\d+):(\d{1,2})(?:[.:](\d{1,3}))?>');

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
      final tags = [..._lineTag.allMatches(line)];
      if (tags.isEmpty) {
        // Plain text without a timestamp — keep for non-timed display.
        // Strip any word tags so a half-written enhanced line does not show
        // its markup as lyrics.
        final bare = line.replaceAll(_wordTag, '').trim();
        if (bare.isNotEmpty) untimed.add(bare);
        continue;
      }
      final body = line.substring(tags.last.end);
      final words = _parseWords(body);
      // Strip word tags from the fallback too. Without it a line whose tags
      // carried no words -- a timing mark recorded before the word was typed
      // -- rendered its own markup as the lyric.
      final text = words.isEmpty
          ? body.replaceAll(_wordTag, '').trim()
          : words.map((w) => w.text).join(' ');
      if (text.isEmpty) continue;
      for (final t in tags) {
        lines.add(LrcLine(timestamp: _durationOf(t), text: text, words: words));
      }
    }
    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return Lrc(metadata: metadata, lines: lines, untimed: untimed);
  }

  /// Pulls `<mm:ss.ff>word` pairs out of a line body. Returns empty when the
  /// line carries no word tags, which is the ordinary line-synced case.
  static List<LrcWord> _parseWords(String body) {
    final tags = [..._wordTag.allMatches(body)];
    if (tags.isEmpty) return const [];
    final words = <LrcWord>[];
    for (var i = 0; i < tags.length; i++) {
      final from = tags[i].end;
      final to = i + 1 < tags.length ? tags[i + 1].start : body.length;
      final text = body.substring(from, to).trim();
      // A tag with nothing after it is a timing mark with no word -- drop it
      // rather than rendering an empty highlight.
      if (text.isEmpty) continue;
      words.add(LrcWord(text: text, start: _durationOf(tags[i])));
    }
    return words;
  }

  static Duration _durationOf(RegExpMatch m) {
    final mm = int.parse(m.group(1)!);
    final ss = int.parse(m.group(2)!);
    final frac = m.group(3);
    var ms = 0;
    if (frac != null) {
      // Normalise fractional: ".5" = 500ms; ".50" = 500ms; ".123" = 123ms.
      final padded =
          '$frac'
                  '000'
              .substring(0, 3);
      ms = int.parse(padded);
    }
    return Duration(minutes: mm, seconds: ss, milliseconds: ms);
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

  /// Index of the word being sung on [lineIndex], or null before the first
  /// word. Returns the last word once the line is past, so a line that has
  /// finished stays fully highlighted rather than resetting.
  static int? activeWordIndex(Lrc lrc, int lineIndex, Duration position) {
    final words = lrc.lines[lineIndex].words;
    if (words.isEmpty) return null;
    if (position < words.first.start) return null;
    var result = 0;
    for (var i = 0; i < words.length; i++) {
      if (words[i].start > position) break;
      result = i;
    }
    return result;
  }

  /// How far through a word the playhead is, 0..1.
  ///
  /// This is what drives the sweep across a word: the view clips the
  /// highlight to this fraction of the word's width.
  static double wordProgress(
    Lrc lrc,
    int lineIndex,
    int wordIndex,
    Duration position, {
    Duration? trackEnd,
  }) {
    final word = lrc.lines[lineIndex].words[wordIndex];
    final end = lrc.wordEndOf(lineIndex, wordIndex, trackEnd: trackEnd);
    final span = end.inMilliseconds - word.start.inMilliseconds;
    if (span <= 0) return position >= word.start ? 1 : 0;
    final p = (position.inMilliseconds - word.start.inMilliseconds) / span;
    if (p.isNaN) return 0;
    return p.clamp(0.0, 1.0);
  }

  /// Format the parsed lyrics back into LRC, keeping word timings where a
  /// line has them. This is the canonical stored form.
  static String format(Lrc lrc) {
    final buf = StringBuffer();
    for (final entry in lrc.metadata.entries) {
      buf.writeln('[${entry.key}:${entry.value}]');
    }
    for (final l in lrc.lines) {
      buf.write('[${_stamp(l.timestamp)}]');
      if (l.words.isEmpty) {
        buf.writeln(l.text);
      } else {
        buf.writeln(
          l.words.map((w) => '<${_stamp(w.start)}>${w.text}').join(' '),
        );
      }
    }
    var s = buf.toString();
    if (s.endsWith('\n')) s = s.substring(0, s.length - 1);
    return s;
  }

  /// The same lyrics as ordinary line-synced LRC, for export to anything that
  /// does not read the enhanced form. Word timings are dropped, never the
  /// words themselves.
  static String toPlainLrc(Lrc lrc) {
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
