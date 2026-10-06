import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';

import '../audio/tune_player.dart';
import '../../domain/mixes.dart' show PlayStamp;
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

  // --- account sync -----------------------------------------------------------

  /// Listens made on this device, as `[startedAt, sha, listenedMs, durationMs,
  /// completed]`, by UTC day (yyyymmdd), each day in time order so the same
  /// listens always give the same text.
  Future<Map<String, List<List<Object>>>> localEventsByDay() async {
    final rows =
        await (_db.select(_db.playEvents)
              ..where((e) => e.origin.isNull())
              ..orderBy([(e) => OrderingTerm.asc(e.startedAt)]))
            .get();
    final out = <String, List<List<Object>>>{};
    for (final r in rows) {
      out.putIfAbsent(dayOf(r.startedAt), () => []).add([
        r.startedAt,
        r.sha,
        r.listenedMs,
        r.durationMs,
        r.completed ? 1 : 0,
      ]);
    }
    return out;
  }

  static String dayOf(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}';
  }

  /// Another device's listens for one day, replacing what was held for that
  /// device and day. Null [events] removes them.
  Future<void> replaceFromDevice(
    String device,
    String day,
    List<List<Object?>>? events,
  ) async {
    final start = DateTime.utc(
      int.parse(day.substring(0, 4)),
      int.parse(day.substring(4, 6)),
      int.parse(day.substring(6, 8)),
    ).millisecondsSinceEpoch;
    await _db.transaction(() async {
      await (_db.delete(_db.playEvents)..where(
            (e) =>
                e.origin.equals(device) &
                e.startedAt.isBetweenValues(start, start + 86400000 - 1),
          ))
          .go();
      for (final e in events ?? const <List<Object?>>[]) {
        await _db
            .into(_db.playEvents)
            .insert(
              PlayEventsCompanion.insert(
                sha: e[1] as String,
                startedAt: (e[0] as num).toInt(),
                listenedMs: (e[2] as num).toInt(),
                durationMs: Value((e[3] as num).toInt()),
                completed: Value(e[4] == 1),
                origin: Value(device),
              ),
            );
      }
    });
    notifyListeners();
  }

  /// Wipes listens that came from other devices (sharing was turned off), so
  /// this device's taste is its own again.
  Future<void> dropForeign() async {
    await (_db.delete(_db.playEvents)..where((e) => e.origin.isNotNull())).go();
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

  /// What is on repeat right now: played through at least [minPlays] times in
  /// the last [window], heaviest first.
  ///
  /// This used to count every play ever made, so "on repeat" was the listener's
  /// all-time favourites and never changed once the history was long. It is now
  /// a window onto today, a day by default, so it follows what is actually on:
  /// a track you loved last spring does not stay on it, and what you have been
  /// looping since this morning does.
  ///
  /// [minPlays] stays at two because "most played" over a set of things played
  /// once each is not a ranking, it is an arbitrary order wearing the word
  /// "most". Below the threshold the section is absent rather than filled with
  /// noise. [now] is injectable so the window can be tested.
  Future<List<String>> topShas({
    int limit = 20,
    int minPlays = 2,
    Duration window = const Duration(hours: 24),
    DateTime? now,
  }) async {
    final since = (now ?? DateTime.now())
        .subtract(window)
        .millisecondsSinceEpoch;
    final count = _db.playEvents.id.count();
    final rows =
        await (_db.selectOnly(_db.playEvents)
              ..addColumns([_db.playEvents.sha, count])
              ..where(
                _db.playEvents.completed.equals(true) &
                    _db.playEvents.startedAt.isBiggerOrEqualValue(since),
              )
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

  /// Songs you played properly a while back and have not played since.
  ///
  /// A track qualifies when it was last played between [within] and [quietFor]
  /// ago: not in the last fortnight, and not so long ago that it is a different
  /// listener's taste. Ranked by how much it was played in total, so the ones
  /// you really had on heavy rotation come first. [exclude] keeps anything that
  /// is on repeat out of it, though the windows cannot overlap by construction.
  ///
  /// This used to take every track ever played, drop the ten most recent and
  /// sort the rest by play count, which is to say it ranked all-time favourites
  /// just as On repeat did, and the two lists were the same songs.
  Future<List<String>> listenAgainShas({
    int limit = 20,
    Duration quietFor = const Duration(days: 14),
    Duration within = const Duration(days: 180),
    Set<String> exclude = const {},
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final newest = at.subtract(quietFor).millisecondsSinceEpoch;
    final oldest = at.subtract(within).millisecondsSinceEpoch;
    final count = _db.playEvents.id.count();
    final last = _db.playEvents.startedAt.max();
    final rows =
        await (_db.selectOnly(_db.playEvents)
              ..addColumns([_db.playEvents.sha, count, last])
              ..where(_db.playEvents.completed.equals(true))
              ..groupBy([_db.playEvents.sha]))
            .get();
    // At most one row per track ever played, so doing the window and the
    // ordering in memory costs nothing and keeps the rule in one readable place.
    final quiet =
        [
          for (final r in rows)
            if ((r.read(last) ?? 0) <= newest &&
                (r.read(last) ?? 0) >= oldest &&
                !exclude.contains(r.read(_db.playEvents.sha)))
              r,
        ]..sort((a, b) {
          final byCount = (b.read(count) ?? 0).compareTo(a.read(count) ?? 0);
          if (byCount != 0) return byCount;
          return (b.read(last) ?? 0).compareTo(a.read(last) ?? 0);
        });
    return quiet
        .take(limit)
        .map((r) => r.read(_db.playEvents.sha))
        .whereType<String>()
        .toList();
  }

  /// Every finished play in the last [within], newest first, with when it
  /// started. What the mixes are built from: not a total per song but the times,
  /// so "what you play on Fridays" and "what you play after dark" can be asked.
  ///
  /// Capped at [limit] rows so a very long history cannot make this slow; the
  /// newest are the ones that say what you are into now.
  Future<List<PlayStamp>> playStamps({
    Duration within = const Duration(days: 365),
    int limit = 20000,
    DateTime? now,
  }) async {
    final since = (now ?? DateTime.now())
        .subtract(within)
        .millisecondsSinceEpoch;
    final rows =
        await (_db.select(_db.playEvents)
              ..where(
                (e) =>
                    e.completed.equals(true) &
                    e.startedAt.isBiggerOrEqualValue(since),
              )
              ..orderBy([(e) => OrderingTerm.desc(e.startedAt)])
              ..limit(limit))
            .get();
    return [
      for (final r in rows)
        PlayStamp(r.sha, DateTime.fromMillisecondsSinceEpoch(r.startedAt)),
    ];
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
