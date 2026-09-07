import '../../domain/manifest.dart';

/// Where in a restored queue to sit.
///
/// [storedSha] is what was playing when the app closed. The library can change
/// while the app is shut — `QueueStore.load` drops entries whose track is no
/// longer there — so the position is resolved by identity rather than
/// remembered as a number. A remembered index would quietly come back pointing
/// at a different song.
///
/// Falls back to the start, which is the honest answer when the track that was
/// playing is gone: the queue is still worth restoring, just not the place in
/// it.
int restoreIndexFor(List<ManifestTrack> restored, String? storedSha) {
  if (storedSha == null || restored.isEmpty) return 0;
  final i = restored.indexWhere((t) => t.sha == storedSha);
  return i < 0 ? 0 : i;
}

/// Below this, resuming is not worth it — you had barely started, and being
/// dropped eight seconds in reads as a glitch rather than as a courtesy.
const kResumeFloor = Duration(seconds: 10);

/// Within this of the end, the track counts as finished. Resuming into the
/// last few seconds of something you already heard is worse than starting it
/// again, and much worse than the silence it would otherwise open on.
const kResumeEndGrace = Duration(seconds: 15);

/// Where playback should actually start, given where it stopped.
///
/// [duration] is nullable because the library does not always know it — an
/// unknown duration means the end-of-track rule cannot be applied, so it is
/// not, rather than being guessed at.
Duration resumePosition(Duration stored, Duration? duration) {
  if (stored <= Duration.zero) return Duration.zero;
  if (stored < kResumeFloor) return Duration.zero;
  if (duration != null && duration > Duration.zero) {
    if (stored >= duration - kResumeEndGrace) return Duration.zero;
    // A stored position past the end means the library changed underneath it:
    // a re-encoded file, or a sha collision in the queue. Starting over is the
    // only safe reading.
    if (stored >= duration) return Duration.zero;
  }
  return stored;
}
