import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';

import '../audio/tune_player.dart';
import 'database.dart';

/// Records what was actually listened to.
///
/// This is the substrate the discovery work needs: what gets played to the
/// end, what gets abandoned, what was on heavy rotation and is not any more.
/// None of that can be recovered later from a play counter, so listens are
/// stored as events and folded into answers on demand.
class PlayHistory extends ChangeNotifier {
  PlayHistory(this._db, this._player) {
    _player.addListener(_onPlayer);
  }

  final TunesDatabase _db;
  final TunePlayer _player;

  /// A play, as opposed to a skip. Half the track, or four minutes -- the
  /// scrobbling convention, and it holds up: half of a two-minute interlude
  /// is a real listen, and four minutes of a twenty-minute mix is too.
  static const _minRatio = 0.5;
  static const _minDuration = Duration(minutes: 4);

  /// A position jump larger than this is a seek, not listening. The player
  /// reports at most every 250ms, so a real advance is never near this.
  static const _seekThreshold = Duration(seconds: 2);

  String? _sha;
  int _startedAt = 0;
  int _durationMs = 0;
  int _listenedMs = 0;
  Duration _lastPosition = Duration.zero;

  void _onPlayer() {
    final current = _player.current;
    final sha = current?.sha;

    if (sha != _sha) {
      // Whatever was playing has ended, been skipped, or been replaced. Settle
      // it before the new track overwrites the counters.
      _finalise();
      _sha = sha;
      _startedAt = DateTime.now().millisecondsSinceEpoch;
      _durationMs = current?.durationMs ?? 0;
      _listenedMs = 0;
      _lastPosition = _player.position;
      return;
    }

    final position = _player.position;
    final delta = position - _lastPosition;
    // Only forward motion of a plausible size counts. A backwards jump is a
    // seek or a repeat; a large forward jump is a seek. Neither was heard.
    if (!delta.isNegative && delta < _seekThreshold && _player.playing) {
      _listenedMs += delta.inMilliseconds;
    }
    _lastPosition = position;
  }

  /// Writes the listen in progress, if there is one worth writing.
  ///
  /// Call before the app goes away: a listen that is never settled is a
  /// listen that never happened, and closing the app mid-track is ordinary.
  void flush() => _finalise();

  void _finalise() {
    final sha = _sha;
    if (sha == null) return;
    final listened = _listenedMs;
    _sha = null;
    _listenedMs = 0;
    // A second of audio is a mis-tap, not a listen, and recording it would
    // put noise into every signal built on this.
    if (listened < 1000) return;
    final completed = _countsAsPlay(listened, _durationMs);
    final startedAt = _startedAt;
    final durationMs = _durationMs;
    // Not awaited: the player has already moved on, and a write that fails
    // must not take playback with it.
    _db
        .into(_db.playEvents)
        .insert(
          PlayEventsCompanion.insert(
            sha: sha,
            startedAt: startedAt,
            listenedMs: listened,
            durationMs: Value(durationMs),
            completed: Value(completed),
          ),
        )
        .then((_) => notifyListeners(), onError: (_) {});
  }

  static bool _countsAsPlay(int listenedMs, int durationMs) {
    if (listenedMs >= _minDuration.inMilliseconds) return true;
    if (durationMs <= 0) return false;
    return listenedMs / durationMs >= _minRatio;
  }

  @override
  void dispose() {
    _player.removeListener(_onPlayer);
    super.dispose();
  }

  /// Forgets everything recorded.
  ///
  /// Deletes the events rather than marking them ignored: a history the user
  /// asked to be rid of that is still on disk is not cleared, it is hidden.
  Future<void> clear() async {
    _sha = null;
    _listenedMs = 0;
    await _db.delete(_db.playEvents).go();
    notifyListeners();
  }

  // --- reading -------------------------------------------------------------

  /// Distinct tracks most recently played, newest first.
  ///
  /// Distinct because a track played five times running is one thing you were
  /// listening to, not five entries worth of screen.
  Future<List<String>> recentShas({int limit = 20}) async {
    final rows =
        await (_db.selectOnly(_db.playEvents)
              ..addColumns([
                _db.playEvents.sha,
                _db.playEvents.startedAt.max(),
                _db.playEvents.id.max(),
              ])
              ..where(_db.playEvents.completed.equals(true))
              ..groupBy([_db.playEvents.sha])
              // Two listens can start in the same millisecond -- an interlude
              // straight into the next track, or anything replayed quickly --
              // and a timestamp alone leaves their order to the database to
              // decide. The row id records which was written second, which is
              // exactly what "more recent" means here.
              ..orderBy([
                OrderingTerm.desc(_db.playEvents.startedAt.max()),
                OrderingTerm.desc(_db.playEvents.id.max()),
              ])
              ..limit(limit))
            .get();
    return rows
        .map((r) => r.read(_db.playEvents.sha))
        .whereType<String>()
        .toList();
  }

  /// The tracks played most, heaviest first.
  ///
  /// [minPlays] defaults to two because "most played" over a set of things
  /// played once each is not a ranking, it is an arbitrary order wearing the
  /// word "most". Below the threshold the section is absent rather than
  /// filled with noise.
  Future<List<String>> topShas({int limit = 20, int minPlays = 2}) async {
    final count = _db.playEvents.id.count();
    final rows =
        await (_db.selectOnly(_db.playEvents)
              ..addColumns([_db.playEvents.sha, count])
              ..where(_db.playEvents.completed.equals(true))
              ..groupBy([
                _db.playEvents.sha,
              ], having: count.isBiggerOrEqualValue(minPlays))
              ..orderBy([
                OrderingTerm.desc(count),
                OrderingTerm.desc(_db.playEvents.startedAt.max()),
              ])
              ..limit(limit))
            .get();
    return rows
        .map((r) => r.read(_db.playEvents.sha))
        .whereType<String>()
        .toList();
  }

  /// Tracks that were played properly, but are not what is being played now.
  ///
  /// Defined by rank rather than by calendar age. "Nothing in three weeks"
  /// is the natural definition and it is useless on a young history -- it
  /// would return nothing at all until the app had been in use for three
  /// weeks. Skipping the [skipRecent] most recent tracks instead means the
  /// section works from the first day and still says the same thing: things
  /// you liked, that are not in current rotation.
  Future<List<String>> listenAgainShas({
    int limit = 20,
    int skipRecent = 10,
  }) async {
    final count = _db.playEvents.id.count();
    final last = _db.playEvents.startedAt.max();
    final rows =
        await (_db.selectOnly(_db.playEvents)
              ..addColumns([_db.playEvents.sha, count, last])
              ..where(_db.playEvents.completed.equals(true))
              ..groupBy([_db.playEvents.sha])
              ..orderBy([OrderingTerm.desc(last)]))
            .get();
    // The set is at most one row per track ever played, so ordering it in
    // memory costs nothing and keeps the "skip the current rotation" rule in
    // one readable place rather than in a window function.
    final older = rows.skip(skipRecent).toList()
      ..sort((a, b) {
        final byCount = (b.read(count) ?? 0).compareTo(a.read(count) ?? 0);
        if (byCount != 0) return byCount;
        return (b.read(last) ?? 0).compareTo(a.read(last) ?? 0);
      });
    return older
        .take(limit)
        .map((r) => r.read(_db.playEvents.sha))
        .whereType<String>()
        .toList();
  }

  /// How many times each track was played, for the tracks that were.
  Future<Map<String, int>> playCounts() async {
    final count = _db.playEvents.id.count();
    final rows =
        await (_db.selectOnly(_db.playEvents)
              ..addColumns([_db.playEvents.sha, count])
              ..where(_db.playEvents.completed.equals(true))
              ..groupBy([_db.playEvents.sha]))
            .get();
    return {
      for (final r in rows)
        if (r.read(_db.playEvents.sha) case final String sha)
          sha: r.read(count) ?? 0,
    };
  }

  /// How many times each track was started and abandoned.
  ///
  /// Kept apart from play counts rather than netted off: repeatedly skipping
  /// something is a signal in its own right, and a track with fifty plays and
  /// forty skips is not the same as one with ten plays and none.
  Future<Map<String, int>> skipCounts() async {
    final count = _db.playEvents.id.count();
    final rows =
        await (_db.selectOnly(_db.playEvents)
              ..addColumns([_db.playEvents.sha, count])
              ..where(_db.playEvents.completed.equals(false))
              ..groupBy([_db.playEvents.sha]))
            .get();
    return {
      for (final r in rows)
        if (r.read(_db.playEvents.sha) case final String sha)
          sha: r.read(count) ?? 0,
    };
  }
}
