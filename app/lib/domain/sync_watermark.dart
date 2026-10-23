/// The sync watermark: how much of the library this phone is known to hold.
///
/// The watermark is the phone's claim about what it already has. It is sent
/// to the daemon as `since`, and the daemon answers with everything added
/// after it. So it must never sit past a track the phone does not actually
/// hold — otherwise that track is never named again and the library quietly
/// stops growing.
///
/// It used to be `DateTime.now()`. That is right only when the manifest the
/// phone applied was complete. It is not always: the edge serves /manifest
/// from a cached copy while /changes is answered by the live daemon, so a
/// publish that failed leaves the two disagreeing. The phone then sees "three
/// new tracks", pulls a manifest that predates them, applies it, and — having
/// recorded the time as its watermark — never asks about those three again.
///
/// The honest watermark is the moment the applied manifest was built. A copy
/// built at T holds everything the daemon knew at T, so T is safe; anything
/// added after T is still missing here and still gets named by /changes. A
/// stale copy carries a stale T, which is exactly the point: it keeps the
/// daemon naming what that copy lacks until a fresh one lands.
library;

/// The newest `addedAt` in a collection, ignoring the ones that are absent.
///
/// The fallback for a manifest that carries no build time: the newest track it
/// contains bounds what it can have been missing.
///
/// Pure so the rule is testable without a phone, and so it stays in the
/// domain layer where it belongs (AGENTS.md §1: domain logic is pure Dart,
/// zero Flutter imports).
DateTime? newestAddedAt(Iterable<DateTime?> addedAts) {
  DateTime? newest;
  for (final a in addedAts) {
    if (a == null) continue;
    if (newest == null || a.isAfter(newest)) newest = a;
  }
  return newest;
}

/// The watermark to keep after applying a manifest.
///
/// [generatedAt] is the build time of the manifest that was just applied, and
/// wins. Failing that, the newest track the manifest carried is the best
/// available claim about its coverage.
///
/// Returns the current watermark unchanged when the manifest offers neither:
/// there is nothing to learn from it, and the clock is not a substitute — it
/// would claim tracks the manifest never contained.
DateTime? watermarkAfterApply({
  required DateTime? current,
  DateTime? generatedAt,
  Iterable<DateTime?> addedAts = const [],
}) {
  if (generatedAt != null) return generatedAt;
  return newestAddedAt(addedAts) ?? current;
}
