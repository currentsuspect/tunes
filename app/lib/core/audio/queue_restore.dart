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
