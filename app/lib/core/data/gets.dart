import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../domain/soulseek.dart';
import '../platform/notifications.dart';
import '../net/tunes_client.dart';

/// Songs being got from Soulseek, shared by every screen that offers a Get
/// (search, an album's missing songs), so a get started in one shows its
/// progress in the other.
///
/// The box does the work (tunesd getter.ts); this asks it how gets are going
/// every two seconds while any is unfinished, and not at all otherwise. When
/// one lands, [onLanded] fetches the library again so the song can play.
class GetsController extends ChangeNotifier {
  GetsController({required this.client, required this.onLanded});

  final TunesClient client;
  final VoidCallback onLanded;

  final Map<String, GetJob> _bySong = {};
  Timer? _poll;
  bool _disposed = false;

  final List<void Function(GetJob)> _landedListeners = [];

  /// Told once for each song this phone asked for, when it lands: the toast
  /// on screen and the notification (owner, 24 Oct: "they don't know it's
  /// there").
  void addLandedListener(void Function(GetJob) f) => _landedListeners.add(f);
  void removeLandedListener(void Function(GetJob) f) =>
      _landedListeners.remove(f);

  List<GetJob> _recent = const [];

  /// The week's gets on the box, everyone's, newest first, as last fetched:
  /// what Home's "Just got" shelf is made of. Empty until [refreshRecent].
  List<GetJob> get recent => _recent;

  /// Fetches the week's gets for the shelf. Quiet on failure: the shelf
  /// keeps what it had.
  Future<List<GetJob>> refreshRecent() async {
    try {
      final jobs = await client.soulseekJobs(days: 7);
      final changed =
          jobs.length != _recent.length ||
          [for (var i = 0; i < jobs.length; i++) _same(jobs[i], _recent[i])]
              .contains(false);
      _recent = jobs;
      if (changed && !_disposed) notifyListeners();
    } catch (_) {
      // The box is out of reach; try again next time.
    }
    return _recent;
  }

  /// Takes a waiting song out of the line.
  Future<bool> cancel(GetJob job) async {
    final ok = await client.soulseekCancel(job.id);
    if (ok) {
      _take([
        GetJob(
          id: job.id,
          title: job.title,
          artist: job.artist,
          album: job.album,
          release: job.release,
          by: job.by,
          state: GetState.cancelled,
        ),
      ]);
      // Out of the line, so not a failure to show either.
      _bySong.remove(job.songKey);
      if (!_disposed) notifyListeners();
    }
    return ok;
  }

  /// The latest get of this song, if any was asked for.
  GetJob? jobFor(String artist, String title) =>
      _bySong[GetJob.keyOf(artist, title)];

  /// Everything this phone asked for since it started, newest first.
  List<GetJob> get following => _bySong.values.toList().reversed.toList();

  /// Gets still going.
  List<GetJob> get active => [
    for (final j in following)
      if (!j.finished) j,
  ];

  /// The last day's gets on the box, everyone's, newest first; null when it
  /// cannot be reached. For the list that opens from the bar.
  Future<List<GetJob>?> everyone() async {
    try {
      final jobs = await client.soulseekJobs();
      // Ours among them update what this phone shows too.
      final mine = {for (final j in _bySong.values) j.id};
      _take([
        for (final j in jobs)
          if (mine.contains(j.id)) j,
      ]);
      return jobs;
    } catch (_) {
      return null;
    }
  }

  /// Gets of one album's songs, still going.
  int pendingFor(String release) =>
      _bySong.values.where((j) => j.release == release && !j.finished).length;

  /// Android asks once whether Tunes may post notes; the first Get is when
  /// a note would first be worth having.
  bool _askedToNotify = false;
  void _askToNotify() {
    if (_askedToNotify) return;
    _askedToNotify = true;
    unawaited(requestNotificationPermissionIfNeeded());
  }

  Future<GetJob?> get(
    FoundSong? copy, {
    String? title,
    String? artist,
    String? album,
    int? durationMs,
    String? release,
  }) async {
    _askToNotify();
    try {
      final job = await client.soulseekGet(
        title: copy?.title ?? title!,
        artist: copy?.artist ?? artist!,
        album: copy?.album ?? album,
        durationMs: copy?.durationMs ?? durationMs,
        release: release,
        copy: copy,
      );
      _take([job]);
      return job;
    } catch (_) {
      return null;
    }
  }

  Future<int> complete(String release) async {
    _askToNotify();
    try {
      final jobs = await client.soulseekComplete(release);
      _take(jobs);
      return jobs.length;
    } catch (_) {
      return 0;
    }
  }

  /// Gets a whole album the library has none of (the artist page's Get it).
  Future<int> completeAlbum(String artist, String album) async {
    _askToNotify();
    try {
      final jobs = await client.soulseekCompleteAlbum(artist, album);
      _take(jobs);
      return jobs.length;
    } catch (_) {
      return 0;
    }
  }

  void _take(List<GetJob> jobs) {
    final landed = <GetJob>[];
    var changed = false;
    for (final j in jobs) {
      final before = _bySong[j.songKey];
      if (j.state == GetState.done &&
          before != null &&
          before.state != GetState.done) {
        landed.add(j);
      }
      if (before == null || !_same(before, j)) changed = true;
      _bySong[j.songKey] = j;
    }
    if (_disposed) return;
    // Only when something moved. Every check used to tell every listener,
    // Home among them, so Home was rebuilt every two seconds while a song
    // was coming (24 Oct).
    if (changed) notifyListeners();
    if (landed.isNotEmpty) {
      onLanded();
      for (final j in landed) {
        for (final f in [..._landedListeners]) {
          f(j);
        }
      }
    }
    final going = _bySong.values.any((j) => !j.finished);
    if (going && _poll == null) {
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _check());
    } else if (!going) {
      _poll?.cancel();
      _poll = null;
    }
  }

  static bool _same(GetJob a, GetJob b) =>
      a.id == b.id &&
      a.state == b.state &&
      a.position == b.position &&
      a.sha == b.sha &&
      // Whole percents: the bar shows no finer.
      ((a.progress ?? -1) * 100).round() == ((b.progress ?? -1) * 100).round();

  Future<void> _check() async {
    try {
      final jobs = await client.soulseekJobs();
      // Only the songs this phone is following; the list is everyone's.
      // Matched by id, else by song: the box forgets its queue when it
      // restarts, and the same song asked again is a new job. One it no
      // longer knows at all is shown as failed, so it can be asked again,
      // rather than turning forever.
      final byId = {for (final j in jobs) j.id: j};
      final bySong = <String, GetJob>{};
      for (final j in jobs) {
        bySong.putIfAbsent(j.songKey, () => j);
      }
      _take([
        for (final f in _bySong.values)
          if (!f.finished)
            byId[f.id] ??
                bySong[f.songKey] ??
                GetJob(
                  id: f.id,
                  title: f.title,
                  artist: f.artist,
                  album: f.album,
                  release: f.release,
                  state: GetState.failed,
                ),
      ]);
    } catch (_) {
      // The box is unreachable for a moment; ask again next tick.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    super.dispose();
  }
}

class GetsScope extends InheritedNotifier<GetsController> {
  const GetsScope({
    super.key,
    required GetsController gets,
    required super.child,
  }) : super(notifier: gets);

  static GetsController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GetsScope>()?.notifier;
}
