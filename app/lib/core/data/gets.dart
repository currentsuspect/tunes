import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../domain/soulseek.dart';
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

  /// The latest get of this song, if any was asked for.
  GetJob? jobFor(String artist, String title) =>
      _bySong[GetJob.keyOf(artist, title)];

  /// Gets of one album's songs, still going.
  int pendingFor(String release) =>
      _bySong.values.where((j) => j.release == release && !j.finished).length;

  Future<GetJob?> get(
    FoundSong? copy, {
    String? title,
    String? artist,
    String? album,
    int? durationMs,
    String? release,
  }) async {
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
    try {
      final jobs = await client.soulseekComplete(release);
      _take(jobs);
      return jobs.length;
    } catch (_) {
      return 0;
    }
  }

  void _take(List<GetJob> jobs) {
    var landed = false;
    for (final j in jobs) {
      final before = _bySong[j.songKey];
      if (j.state == GetState.done &&
          before != null &&
          before.state != GetState.done) {
        landed = true;
      }
      _bySong[j.songKey] = j;
    }
    if (_disposed) return;
    notifyListeners();
    if (landed) onLanded();
    final going = _bySong.values.any((j) => !j.finished);
    if (going && _poll == null) {
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _check());
    } else if (!going) {
      _poll?.cancel();
      _poll = null;
    }
  }

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
