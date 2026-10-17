import '../../domain/manifest.dart';

/// What the listener has been doing, right now.
///
/// Deliberately small and in-memory. This is the "session" half of
/// `session -> next track` (docs/RADIO.md §1): not what they like in general,
/// but what they are in the middle of. It is rebuilt on every app start,
/// because a session that survives a restart is not a session.
class RadioSession {
  RadioSession({this.recentWindow = 20, this.artistWindow = 10});

  /// How many recent tracks count as "recently played" for the repetition
  /// penalty. Twenty is the spec's number.
  final int recentWindow;

  /// How many recent artists count for the artist penalty. Shorter than the
  /// track window on purpose: hearing the same artist twice in ten tracks is
  /// ordinary, hearing the same track twice in twenty is not.
  final int artistWindow;

  final List<String> _recentShas = [];
  final List<String> _recentArtists = [];
  final Set<String> _skipped = {};

  /// How far the wander is currently willing to go, 0..1.
  ///
  /// Starts cautious. Every track heard to the end widens it; every skip
  /// narrows it, and by more than a completion widens it -- an unwanted
  /// suggestion should cost more than a wanted one earns, or the radio
  /// wanders off and takes a dozen tracks to come back.
  double _exploration = 0.2;

  /// The listener's own dial, 0 (familiar) to 1 (further out). It shifts the
  /// whole range: the session still adapts to skips and finished songs, but
  /// around a centre the listener chose. At [defaultReach] it changes nothing.
  double reach = defaultReach;

  static const double defaultReach = 0.2;

  /// Every [stretchEvery]th pick is a stretch: something next door to the
  /// kind of music playing, not more of it. The reserved slot is what keeps
  /// the radio out of the echo chamber however sticky the lane gets. Zero
  /// means never.
  int stretchEvery = 0;

  int _picks = 0;

  /// Whether the pick about to be made is a stretch.
  bool get stretchTurn => stretchEvery > 0 && (_picks + 1) % stretchEvery == 0;

  /// The radio made a pick (called by the engine).
  void picked() => _picks++;

  /// Sets reach and stretch from one of the listener's quick modes.
  void useMode(RadioMode mode) {
    reach = mode.reach;
    stretchEvery = mode.stretchEvery;
  }

  double get exploration =>
      (_exploration + (reach - defaultReach)).clamp(0.0, 1.0);
  List<String> get recentShas => List.unmodifiable(_recentShas);
  List<String> get recentArtists => List.unmodifiable(_recentArtists);

  /// How many of the last [artistWindow] tracks were by [artist].
  int recentCountFor(String artist) {
    final key = artist.toLowerCase();
    return _recentArtists.where((a) => a.toLowerCase() == key).length;
  }

  bool wasRecentlyPlayed(String sha) => _recentShas.contains(sha);
  bool wasSkipped(String sha) => _skipped.contains(sha);

  /// Records that a track was heard to the end.
  void completed(ManifestTrack track) {
    _remember(track);
    _skipped.remove(track.sha);
    _exploration = (_exploration + 0.06).clamp(0.0, 1.0);
  }

  /// Records that a track was abandoned.
  ///
  /// A skip is the strongest signal the listener gives without typing
  /// anything, so it does two things: narrows the wander, and marks the track
  /// so the same suggestion is not made again this session.
  void skipped(ManifestTrack track) {
    _remember(track);
    _skipped.add(track.sha);
    _exploration = (_exploration - 0.10).clamp(0.0, 1.0);
  }

  void _remember(ManifestTrack track) {
    _recentShas.insert(0, track.sha);
    if (_recentShas.length > recentWindow) _recentShas.removeLast();

    final act = (track.primaryArtist ?? track.artist).trim();
    if (act.isNotEmpty) {
      _recentArtists.insert(0, act);
      if (_recentArtists.length > artistWindow) _recentArtists.removeLast();
    }
  }

  void reset() {
    _recentShas.clear();
    _recentArtists.clear();
    _skipped.clear();
    _exploration = 0.2;
    _picks = 0;
  }
}

/// The three ways the listener can ask the radio to go (owner, 5 Oct): a
/// tap each, in the queue, instead of a dial buried on Discover.
enum RadioMode {
  /// More of what is playing; a stretch now and then.
  stayClose('Stay close', 0.10, 8),

  /// Wanders from what is playing, comes back.
  drift('Drift', 0.30, 5),

  /// Further out, often: new to you, next door, sometimes a family away.
  surprise('Surprise me', 0.85, 3);

  const RadioMode(this.label, this.reach, this.stretchEvery);

  final String label;
  final double reach;
  final int stretchEvery;

  static RadioMode? byName(String? n) =>
      values.where((m) => m.name == n).firstOrNull;
}
