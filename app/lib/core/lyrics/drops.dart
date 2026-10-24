/// Drop moments: where the song breaks out of its lyrics.
///
/// The box reads where each song hits (tunesd beats.ts) and sends it in the
/// lyric as [tunesbeat:drop=…;break=…;pulse=…;quiet=…] (ms). From that:
///
///   grow    an ad-lib on a drop, or sung while the 808 is out (a break),
///           grows until it crowds every other line out; when the 808 lands
///           it shrinks back in steps, one per hit, and the lines come back,
///           the one being sung first.
///   impact  a break with no ad-lib: as the 808 returns the whole sheet
///           dissolves, the line being sung lands alone, the rest pop back.
///   hush    the music goes quiet, so the words do too.
///
/// Pure timing, like word_motion.dart: what is shown is worked out from the
/// playhead alone, so a seek lands in the right state.
library;

import 'dart:math' as math;

import 'adlib_kinds.dart';
import 'adlibs.dart';
import 'lrc_parser.dart';

/// The box's reading of one song.
class BeatMap {
  const BeatMap({
    this.drops = const [],
    this.breaks = const [],
    this.pulse = const [],
    this.quiet = const [],
  });

  /// The metadata key, as the parser stores it.
  static const key = 'tunesbeat';

  final List<Duration> drops;
  final List<(Duration, Duration)> breaks;
  final List<Duration> pulse;
  final List<(Duration, Duration)> quiet;

  bool get isEmpty => drops.isEmpty && breaks.isEmpty && quiet.isEmpty;

  /// Reads the metadata value; anything malformed is skipped.
  static BeatMap parse(String? value) {
    if (value == null || value.trim().isEmpty) return const BeatMap();
    final parts = <String, String>{};
    for (final p in value.split(';')) {
      final eq = p.indexOf('=');
      if (eq > 0) parts[p.substring(0, eq).trim()] = p.substring(eq + 1);
    }
    List<Duration> times(String? v) => [
      for (final t in (v ?? '').split(','))
        if (int.tryParse(t.trim()) case final ms? when ms >= 0)
          Duration(milliseconds: ms),
    ];
    List<(Duration, Duration)> spans(String? v) => [
      for (final t in (v ?? '').split(','))
        if (RegExp(r'^\s*(\d+)-(\d+)\s*$').firstMatch(t) case final m?)
          if (int.parse(m.group(2)!) > int.parse(m.group(1)!))
            (
              Duration(milliseconds: int.parse(m.group(1)!)),
              Duration(milliseconds: int.parse(m.group(2)!)),
            ),
    ];
    return BeatMap(
      drops: times(parts['drop'])..sort(),
      breaks: spans(parts['break']),
      pulse: times(parts['pulse'])..sort(),
      quiet: spans(parts['quiet']),
    );
  }
}

enum DropKind { grow, impact, hush }

class DropMoment {
  const DropMoment({
    required this.kind,
    required this.from,
    required this.hit,
    required this.to,
    this.line = -1,
    this.text = '',
    this.adlib = AdlibKind.plain,
    this.steps = const [],
  });

  final DropKind kind;

  /// [from] the moment starts (the ad-lib, for a grow); [hit] the 808
  /// lands; [to] everything is back as it was.
  final Duration from;
  final Duration hit;
  final Duration to;

  /// The shown line the ad-lib is on (grow), or -1.
  final int line;

  /// The ad-lib's words, brackets off, and its kind (grow).
  final String text;
  final AdlibKind adlib;

  /// The 808 hits it shrinks back on, the first being [hit] (grow).
  final List<Duration> steps;
}

const _bloom = Duration(milliseconds: 250);
const _reveal = Duration(milliseconds: 180);
const _stagger = Duration(milliseconds: 50);
const _ramp = Duration(milliseconds: 400);

/// The moments in a song, from its [lines] (as shown) and [beats].
/// [shiftOf] moves an ad-lib by a Lyric Center fix (line, first word).
List<DropMoment> resolveMoments(
  List<LrcLine> lines,
  BeatMap beats, {
  Duration Function(int line, int word)? shiftOf,
}) {
  if (beats.isEmpty || lines.isEmpty) return const [];
  // Every ad-lib, with when it is heard.
  final adlibs = <({int line, Duration at, String text, AdlibKind kind})>[];
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    final tokens = l.text
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    final whole = wholeLineAdlib(tokens);
    final groups = whole != null
        ? [whole]
        : adlibGroups(tokens, adlibMask(tokens));
    if (groups.isEmpty) continue;
    final next = i + 1 < lines.length ? lines[i + 1].timestamp : null;
    final est = estimatedAdlibTimes(l.timestamp, next, [
      for (final g in groups) whole != null || g.words.first == 0,
    ]);
    for (var k = 0; k < groups.length; k++) {
      final g = groups[k];
      if (g.words.every((w) => isPlaceholder(tokens[w]))) continue;
      final timed = l.words.length == tokens.length
          ? l.words[g.words.first].start
          : est[k].start;
      final text = [for (final w in g.words) tokens[w]]
          .join(' ')
          .replaceAll(RegExp(r'[()\[\]]'), '')
          .replaceAll(RegExp(r'[,.;:!?]+$'), '')
          .trim();
      if (text.isEmpty) continue;
      adlibs.add((
        line: i,
        at: timed + (shiftOf?.call(i, g.words.first) ?? Duration.zero),
        text: text,
        kind: g.kind,
      ));
    }
  }

  List<Duration> stepsFrom(Duration hit) {
    final s = [
      for (final p in beats.pulse)
        if (p >= hit - const Duration(milliseconds: 80) &&
            p <= hit + const Duration(seconds: 4))
          p,
    ];
    if (s.isEmpty || (s.first - hit).abs() > const Duration(milliseconds: 80)) {
      s.insert(0, hit);
    }
    // At least three steps, so it reads as shrinking rather than snapping.
    while (s.length < 3) {
      s.add(s.last + const Duration(milliseconds: 500));
    }
    return s.take(4).toList();
  }

  final out = <DropMoment>[];
  final used = <Duration>{};
  // A break: the last ad-lib sung while the 808 is out grows from there.
  for (final (start, hit) in beats.breaks) {
    used.add(hit);
    final inside = adlibs.where(
      (a) => a.at >= start && a.at <= hit - const Duration(milliseconds: 150),
    );
    if (inside.isNotEmpty) {
      final a = inside.last;
      final steps = stepsFrom(hit);
      out.add(
        DropMoment(
          kind: DropKind.grow,
          from: a.at,
          hit: hit,
          to: steps.last + _reveal,
          line: a.line,
          text: a.text,
          adlib: a.kind,
          steps: steps,
        ),
      );
    } else {
      out.add(
        DropMoment(
          kind: DropKind.impact,
          from: hit,
          hit: hit,
          to: hit + const Duration(milliseconds: 1400),
        ),
      );
    }
  }
  // A drop on its own: an ad-lib right on it blooms and shrinks back.
  for (final d in beats.drops) {
    if (used.contains(d)) continue;
    final near = adlibs.where(
      (a) =>
          a.at >= d - const Duration(milliseconds: 400) &&
          a.at <= d + const Duration(milliseconds: 250),
    );
    if (near.isEmpty) continue;
    final a = near.first;
    final steps = stepsFrom(d);
    out.add(
      DropMoment(
        kind: DropKind.grow,
        from: d - _bloom,
        hit: d,
        to: steps.last + _reveal,
        line: a.line,
        text: a.text,
        adlib: a.kind,
        steps: steps,
      ),
    );
  }
  for (final (a, b) in beats.quiet) {
    out.add(DropMoment(kind: DropKind.hush, from: a, hit: a, to: b));
  }
  out.sort((x, y) => x.from.compareTo(y.from));
  // One at a time: a moment overlapping the one before is dropped.
  final kept = <DropMoment>[];
  for (final m in out) {
    if (kept.isNotEmpty && m.from < kept.last.to) continue;
    kept.add(m);
  }
  return kept;
}

/// What the sheet shows at one instant.
class DropFrame {
  const DropFrame({
    this.moment,
    this.dim = 0,
    this.grow = 0,
    this.punch = 0,
    this.wordOpacity = 0,
    this.revealFrom,
  });

  static const none = DropFrame();

  final DropMoment? moment;

  /// How far the lines are faded out, 0 not at all to 1 gone.
  final double dim;

  /// The ad-lib's size, 0 its own to 1 filling the sheet (grow).
  final double grow;

  /// A hit's squash on the word, 1 just landed to 0 settled.
  final double punch;
  final double wordOpacity;

  /// From when lines come back, the line being sung first: line [i] is
  /// back by revealFrom + |i - active| × stagger. Null: [dim] for all.
  final Duration? revealFrom;

  bool get isNone => moment == null;

  /// How faded line [distance] lines from the one being sung is, at [pos].
  double dimFor(int distance, Duration pos) {
    final r = revealFrom;
    if (r == null || pos < r) return dim;
    final start = r + _stagger * distance.abs();
    final t = (pos - start).inMilliseconds / _reveal.inMilliseconds;
    return dim * (1 - t.clamp(0.0, 1.0));
  }

  @override
  bool operator ==(Object other) =>
      other is DropFrame &&
      identical(other.moment, moment) &&
      other.dim == dim &&
      other.grow == grow &&
      other.punch == punch &&
      other.wordOpacity == wordOpacity &&
      other.revealFrom == revealFrom;

  @override
  int get hashCode =>
      Object.hash(moment, dim, grow, punch, wordOpacity, revealFrom);
}

double _ease(double t) {
  final x = t.clamp(0.0, 1.0);
  return x < 0.5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3) / 2;
}

double _frac(Duration pos, Duration from, Duration len) =>
    len.inMilliseconds <= 0
    ? 1
    : ((pos - from).inMilliseconds / len.inMilliseconds).clamp(0.0, 1.0);

/// The frame at [pos], from [moments] (sorted, not overlapping).
DropFrame dropFrame(List<DropMoment> moments, Duration pos) {
  DropMoment? m;
  for (final x in moments) {
    if (x.from > pos) break;
    if (pos < x.to) {
      m = x;
      break;
    }
  }
  if (m == null) return DropFrame.none;
  switch (m.kind) {
    case DropKind.hush:
      final into = _frac(pos, m.from, _ramp);
      final outOf = 1 - _frac(pos, m.to - _ramp, _ramp);
      return DropFrame(moment: m, dim: 0.85 * math.min(into, outOf));
    case DropKind.impact:
      // Gone in 120 ms on the hit; back from 200 ms, the sung line first.
      final gone = _frac(pos, m.hit, const Duration(milliseconds: 120));
      return DropFrame(
        moment: m,
        dim: gone,
        revealFrom: m.hit + const Duration(milliseconds: 200),
      );
    case DropKind.grow:
      if (pos < m.hit) {
        final g = _ease(_frac(pos, m.from, m.hit - m.from));
        return DropFrame(
          moment: m,
          grow: g,
          dim: 0.85 * g,
          wordOpacity: math.min(1, g * 4),
        );
      }
      // Shrinking back: one step per 808 hit, a squash on each.
      final steps = m.steps;
      var k = 0;
      while (k + 1 < steps.length && steps[k + 1] <= pos) {
        k++;
      }
      final n = steps.length;
      final before = 1 - k / n;
      final after = 1 - (k + 1) / n;
      final settle = _frac(pos, steps[k], const Duration(milliseconds: 160));
      final g = before + (after - before) * (1 - math.pow(1 - settle, 3));
      final punch = 1 - _frac(pos, steps[k], const Duration(milliseconds: 220));
      final last = steps.last;
      final fade = pos < last ? 1.0 : 1 - _frac(pos, last, _reveal);
      return DropFrame(
        moment: m,
        grow: g.toDouble(),
        punch: punch,
        dim: 0.85,
        wordOpacity: fade,
        revealFrom: m.hit,
      );
  }
}
