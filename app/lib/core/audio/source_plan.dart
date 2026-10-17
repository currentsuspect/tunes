/// Where each song in the decoder's queue gets its bytes, and when that has to
/// change.
///
/// The decoder is handed an address per song when a queue opens, and keeps it.
/// A song that reaches the phone afterwards -- the stream cache keeps whatever
/// has played for a few seconds, a download finishes -- still pointed at the
/// server, so offline it played the few seconds mpv had buffered, failed, and
/// the retry opened the same server address again: the song restarting every
/// few seconds while its full copy sat on the phone.
library;

/// Whether [uri] is a file on this phone rather than a server address.
bool isLocalUri(String uri) =>
    !uri.startsWith('http://') && !uri.startsWith('https://');

/// What has to change in the decoder so every song plays from the best place
/// it can now.
class SourcePlan {
  const SourcePlan({this.reopenCurrent = false, this.rebuildTail = false});

  /// The song playing streams from the server, its copy is on the phone now,
  /// and the caller allowed touching it: reopen it from the copy, at the same
  /// spot. Never done to a stream that is playing fine on its own.
  final bool reopenCurrent;

  /// Some song still to come would open from a different address than the
  /// one it was queued with (now on the phone, or signed since).
  final bool rebuildTail;

  bool get isNone => !reopenCurrent && !rebuildTail;

  static const none = SourcePlan();
}

/// Compares the addresses the decoder [opened] with the ones the songs
/// [resolved] to now. [current] may only be reopened when [touchCurrent]:
/// offline, or after its stream failed.
SourcePlan planSources({
  required List<String> opened,
  required List<String> resolved,
  required int index,
  required bool touchCurrent,
}) {
  if (opened.length != resolved.length) return SourcePlan.none;
  if (index < 0 || index >= resolved.length) return SourcePlan.none;
  final reopen =
      touchCurrent && !isLocalUri(opened[index]) && isLocalUri(resolved[index]);
  var tail = false;
  for (var i = index + 1; i < resolved.length; i++) {
    if (opened[i] != resolved[i]) {
      tail = true;
      break;
    }
  }
  return SourcePlan(reopenCurrent: reopen, rebuildTail: tail);
}

/// The first song after [index] that is on the phone, or null. Offline, a song
/// that has to be streamed cannot play, so skipping to it only fails again.
int? nextLocalAfter(List<String> resolved, int index) {
  for (var i = index + 1; i < resolved.length; i++) {
    if (isLocalUri(resolved[i])) return i;
  }
  return null;
}
