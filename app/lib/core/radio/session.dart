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

  double get exploration => _exploration;
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
  }
}
