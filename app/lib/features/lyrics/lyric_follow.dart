import 'package:flutter/foundation.dart';

import '../../core/audio/tune_player.dart';
import '../../core/lyrics/lrc_parser.dart';

/// Shared lyric-playhead logic for the Now Playing preview and the full
/// lyrics view. Both surfaces resolve the active line through
/// [lyricActiveIndex], so there is exactly one copy of the sync rule and
/// both stay consistent with `LrcParser.activeLine`.
///
/// Word-level timing is read defensively: [lyricWordParts] and
/// [lyricActiveWordIndex] return null when the parser exposes no word data
/// (plain line-synced LRC) and never throw, so this file works with or
/// without Enhanced LRC support in the parser.

/// The index into [lrc.lines] of the line playing at [position], or null
/// before the first line / when there are no timed lines. Thin wrapper over
/// [LrcParser.activeLine] — the single sync rule shared by every surface.
int? lyricActiveIndex(Lrc lrc, Duration position) {
  final active = LrcParser.activeLine(lrc, position);
  if (active == null) return null;
  return lrc.lines.indexOf(active);
}

/// One word's display text and start time, mirroring the parser's word
/// model (`LrcWord`) without naming it, so this file still compiles when
/// the parser only knows line-level LRC.
typedef LyricWordPart = ({String text, Duration start});

/// Per-word timings for line [lineIndex], or null when the parser exposes
/// no word data for it. Never throws: a line-level parser simply yields
/// null and callers fall back to line-level display.
///
/// The parser's word field has been called both `start` and `timestamp`
/// across revisions; both shapes are accepted.
List<LyricWordPart>? lyricWordParts(Lrc lrc, int lineIndex) {
  if (lineIndex < 0 || lineIndex >= lrc.lines.length) return null;
  final List<dynamic> raw;
  try {
    final dynamic words = (lrc.lines[lineIndex] as dynamic).words;
    if (words is! List) return null;
    raw = words;
  } on NoSuchMethodError {
    // Parser predates word timing: no `words` on the line.
    return null;
  }
  final out = <LyricWordPart>[];
  for (final w in raw) {
    final text = _wordText(w);
    final start = _wordStart(w);
    if (text != null && start != null) {
      out.add((text: text, start: start));
    }
  }
  return out.isEmpty ? null : out;
}

/// Index of the word being sung on [lineIndex] at [position], mirroring
/// `LrcParser.activeWordIndex` semantics: null before the first word (or
/// when there is no word timing), the last word once the line is past, so
/// a finished line stays fully highlighted. Never throws.
int? lyricActiveWordIndex(Lrc lrc, int lineIndex, Duration position) {
  final parts = lyricWordParts(lrc, lineIndex);
  if (parts == null || parts.isEmpty) return null;
  if (position < parts.first.start) return null;
  var result = 0;
  for (var i = 0; i < parts.length; i++) {
    if (parts[i].start > position) break;
    result = i;
  }
  return result;
}

String? _wordText(dynamic word) {
  try {
    final dynamic text = word.text;
    if (text is String) return text;
  } on NoSuchMethodError {
    // Word model without `text` — not renderable, skip the entry.
  }
  return null;
}

Duration? _wordStart(dynamic word) {
  try {
    final dynamic start = word.start;
    if (start is Duration) return start;
  } on NoSuchMethodError {
    // Fall through to the `timestamp` shape below.
  }
  try {
    final dynamic timestamp = word.timestamp;
    if (timestamp is Duration) return timestamp;
  } on NoSuchMethodError {
    // Word model without a known start field — skip the entry.
  }
  return null;
}

/// Tracks the lyric playhead for one lyric blob. Listens to [player] and
/// notifies only when the active *line* changes (or follow state / lyrics
/// change) — never on every ~250ms position tick — so scroll motion stays
/// continuous instead of jumping. Within-line (word) progression is read
/// per-build via [lyricActiveWordIndex], not via notifications.
///
/// Follow protocol: a new active line always resumes following (playback
/// advancing pulls the view along); [userScrolled] pauses it so a manual
/// browse is never yanked away; [resumeFollowing] re-engages it.
class LyricFollowController extends ChangeNotifier {
  /// [clock], when given, is the position source instead of the player.
  ///
  /// This matters: the player reports at most four times a second, so a line
  /// resolved from `player.position` can land up to ~250ms late — the exact
  /// lateness `PlayheadClock` exists to remove, and which the full lyric view
  /// already corrected for its word sweep. Passing the same clock here keeps
  /// the line change and the word sweep on one timebase; a surface without a
  /// clock still works, just at player resolution.
  ///
  /// Note: `prefer_initializing_formals` is intentionally not applied
  /// below — public named parameters cannot be private initializing
  /// formals (`this._player` is not a legal parameter name).
  LyricFollowController({
    required TunePlayer player,
    required Lrc? lrc,
    ValueListenable<Duration>? clock,
  })
    // ignore: prefer_initializing_formals
    : _player = player,
       // ignore: prefer_initializing_formals
       _lrc = lrc,
       // ignore: prefer_initializing_formals
       _clock = clock {
    _activeIndex = _resolve(_position);
    _source.addListener(_onPlayerTick);
  }

  final TunePlayer _player;
  final ValueListenable<Duration>? _clock;
  Lrc? _lrc;
  int? _activeIndex;
  bool _following = true;

  /// Whichever notifier actually reports movement. Listening to the clock
  /// when there is one avoids resolving twice per player report.
  Listenable get _source => _clock ?? _player;

  Duration get _position => _clock?.value ?? _player.position;

  /// Index into the lyric lines of the currently playing line, or null
  /// before the first line / without timed lines.
  int? get activeIndex => _activeIndex;

  /// Whether the view should track the playhead. False after a manual
  /// scroll until playback reaches a new line or [resumeFollowing].
  bool get following => _following;

  int? _resolve(Duration position) {
    final lrc = _lrc;
    if (lrc == null) return null;
    return lyricActiveIndex(lrc, position);
  }

  /// Swap the lyric blob (track change). Re-anchors to the playhead and
  /// resumes following.
  void updateLyrics(Lrc? lrc) {
    _lrc = lrc;
    _activeIndex = _resolve(_position);
    _following = true;
    notifyListeners();
  }

  /// A manual scroll temporarily overrides auto-follow.
  void userScrolled() {
    if (_following) {
      _following = false;
      notifyListeners();
    }
  }

  /// Re-engage auto-follow (user scrolled back, or tapped recenter).
  void resumeFollowing() {
    if (!_following) {
      _following = true;
      notifyListeners();
    }
  }

  void _onPlayerTick() {
    final next = _resolve(_position);
    if (next != _activeIndex) {
      _activeIndex = next;
      // Playback reaching a new line resumes following on its own.
      _following = true;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    // Detach from whatever was attached to. The clock itself is owned by the
    // view that created it, not by this controller.
    _source.removeListener(_onPlayerTick);
    super.dispose();
  }
}
