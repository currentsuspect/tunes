import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';

import '../net/tunes_client.dart';
import 'art_store.dart';
import 'download_store.dart';

/// Where a track is in the download pipeline.
enum DownloadPhase { queued, running, failed }

/// A download in flight or waiting its turn. Completed downloads are not
/// represented here — once a file is on disk, [DownloadStore] is the truth.
@immutable
class DownloadJob {
  const DownloadJob({
    required this.sha,
    required this.phase,
    this.received = 0,
    this.total = 0,
    this.error,
  });

  final String sha;
  final DownloadPhase phase;
  final int received;
  final int total;
  final String? error;

  /// 0..1, or null when the server did not send a content-length and there is
  /// nothing honest to show. Callers should fall back to an indeterminate bar
  /// rather than inventing a number.
  double? get progress {
    if (total <= 0) return null;
    final p = received / total;
    if (p.isNaN || p.isInfinite) return null;
    return p.clamp(0.0, 1.0);
  }

  DownloadJob copyWith({
    DownloadPhase? phase,
    int? received,
    int? total,
    String? error,
  }) {
    return DownloadJob(
      sha: sha,
      phase: phase ?? this.phase,
      received: received ?? this.received,
      total: total ?? this.total,
      error: error ?? this.error,
    );
  }
}

/// Runs downloads with bounded concurrency and real progress.
///
/// Before this, `main.dart` held a `Set<String>` of in-flight shas and passed
/// no progress callback, so a 20 MB FLAC showed an indeterminate spinner with
/// no way to tell it apart from a hang — and no way to stop it. Tapping ten
/// rows opened ten concurrent HTTP streams.
class DownloadManager extends ChangeNotifier {
  DownloadManager({
    required this.client,
    required this.store,
    this.maxConcurrent = 2,
    this.artStore,
  });

  final TunesClient client;
  final DownloadStore store;

  /// Covers ride along with track downloads so a downloaded library is a
  /// complete offline copy, not audio with empty frames. Best effort and
  /// outside the track pipeline: art never blocks, fails, or cancels audio.
  final ArtStore? artStore;

  /// Two at a time: enough to keep the link busy, few enough that a phone on
  /// wi-fi is not fighting itself for bandwidth.
  final int maxConcurrent;

  /// Told each time a song's file is complete on the phone, so playback can
  /// move a queued song off the server and onto the copy.
  void Function(String sha)? onSaved;

  final Map<String, DownloadJob> _jobs = {};
  final Map<String, CancelSignal> _signals = {};
  final Queue<String> _waiting = Queue<String>();
  int _running = 0;

  /// What the current burst of downloading adds up to, so the whole of it can
  /// be shown as one progress ("3 of 12") however many songs it is. Resets when
  /// the queue goes quiet.
  int _batchTotal = 0;
  int _batchDone = 0;

  int get batchTotal => _batchTotal;
  int get batchDone => _batchDone;

  /// Waiting or running, not failed.
  int get queuedCount =>
      _jobs.values.where((j) => j.phase == DownloadPhase.queued).length;
  int get runningCount =>
      _jobs.values.where((j) => j.phase == DownloadPhase.running).length;
  int get failedCount =>
      _jobs.values.where((j) => j.phase == DownloadPhase.failed).length;

  /// How far through the whole batch, 0 to 1: finished songs plus the part of
  /// each running one that has arrived. Null when nothing is in flight. A
  /// running song whose size is unknown counts for nothing until it finishes,
  /// rather than being guessed at.
  double? get overallProgress {
    if (_batchTotal <= 0 || activeCount == 0) return null;
    var partial = 0.0;
    for (final j in _jobs.values) {
      if (j.phase == DownloadPhase.running) partial += j.progress ?? 0;
    }
    return ((_batchDone + partial) / _batchTotal).clamp(0.0, 1.0);
  }

  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  /// Progress arrives per chunk, hundreds of times a song, and every listening
  /// row rebuilds on each. Ten a second is smooth to the eye and a fraction of
  /// the work. Anything that changes what is shown, like starting or finishing,
  /// still notifies at once.
  void _notifyProgress() {
    final now = DateTime.now();
    if (now.difference(_lastNotify) < const Duration(milliseconds: 100)) return;
    _lastNotify = now;
    notifyListeners();
  }

  /// Snapshot of everything queued, running or failed.
  Map<String, DownloadJob> get jobs => Map.unmodifiable(_jobs);

  DownloadJob? jobFor(String sha) => _jobs[sha];

  bool isActive(String sha) {
    final j = _jobs[sha];
    return j != null &&
        (j.phase == DownloadPhase.queued || j.phase == DownloadPhase.running);
  }

  int get activeCount =>
      _jobs.values.where((j) => j.phase != DownloadPhase.failed).length;

  /// Adds a track to the queue. Already-downloaded and already-queued tracks
  /// are ignored, so a double tap cannot start two transfers of one file.
  /// The cover goes with it when one is named: a download that leaves its
  /// sleeve behind is half an offline copy.
  void enqueue(String sha, {String? artSha}) {
    final art = artSha;
    if (art != null && art.isNotEmpty) {
      unawaited(artStore?.fetch(art));
    }
    if (store.contains(sha)) return;
    if (isActive(sha)) return;
    if (activeCount == 0) {
      _batchTotal = 0;
      _batchDone = 0;
    }
    _batchTotal += 1;
    _jobs[sha] = DownloadJob(sha: sha, phase: DownloadPhase.queued);
    _waiting.add(sha);
    notifyListeners();
    _pump();
  }

  /// Stops a download. A queued job is simply dropped; a running one is
  /// signalled and its partial file is discarded by the client.
  void cancel(String sha) {
    _signals[sha]?.cancel();
    _waiting.remove(sha);
    if (_jobs[sha]?.phase == DownloadPhase.queued) {
      _jobs.remove(sha);
      if (_batchTotal > 0) _batchTotal -= 1;
    }
    notifyListeners();
  }

  /// Clears a failed job so the row stops showing an error.
  void dismiss(String sha) {
    if (_jobs[sha]?.phase == DownloadPhase.failed) {
      _jobs.remove(sha);
      notifyListeners();
    }
  }

  void cancelAll() {
    for (final sha in _jobs.keys.toList()) {
      cancel(sha);
    }
  }

  void _pump() {
    while (_running < maxConcurrent && _waiting.isNotEmpty) {
      final sha = _waiting.removeFirst();
      // Could have been cancelled while waiting.
      if (!_jobs.containsKey(sha)) continue;
      unawaited(_run(sha));
    }
  }

  Future<void> _run(String sha) async {
    _running++;
    final signal = CancelSignal();
    _signals[sha] = signal;
    _jobs[sha] =
        (_jobs[sha] ?? DownloadJob(sha: sha, phase: DownloadPhase.queued))
            .copyWith(phase: DownloadPhase.running);
    notifyListeners();

    final path = store.newPathFor(sha);
    try {
      await client.downloadTrack(
        sha,
        path,
        cancel: signal,
        onProgress: (received, total) {
          final job = _jobs[sha];
          if (job == null) return;
          _jobs[sha] = job.copyWith(received: received, total: total);
          _notifyProgress();
        },
      );
      await store.add(sha, path);
      _jobs.remove(sha);
      _batchDone += 1;
      onSaved?.call(sha);
    } on DownloadCancelled {
      // Not a failure: the user asked for this. Leave no trace.
      _jobs.remove(sha);
      if (_batchTotal > 0) _batchTotal -= 1;
    } catch (e) {
      _jobs[sha] =
          (_jobs[sha] ?? DownloadJob(sha: sha, phase: DownloadPhase.running))
              .copyWith(phase: DownloadPhase.failed, error: e.toString());
    } finally {
      _signals.remove(sha);
      _running--;
      notifyListeners();
      _pump();
    }
  }

  @override
  void dispose() {
    cancelAll();
    super.dispose();
  }
}

/// Makes the [DownloadManager] reachable from any row without threading it
/// through six screens. Rows rebuild automatically when the manager notifies.
class DownloadScope extends InheritedNotifier<DownloadManager> {
  const DownloadScope({
    super.key,
    required DownloadManager manager,
    required super.child,
  }) : super(notifier: manager);

  static DownloadManager? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<DownloadScope>()
        ?.notifier;
  }
}
