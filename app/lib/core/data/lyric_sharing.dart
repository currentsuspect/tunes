import 'manifest_store.dart';

/// Lyrics that one listener adds becoming lyrics everyone has.
///
/// The words live on the daemon. A listener saving lyrics keeps them on the
/// phone straight away (so they show at once, and survive being offline) and
/// sends them to the daemon; once the daemon's copy comes back in the manifest
/// the phone's own copy has done its job and is dropped, so the daemon's
/// version is the one everybody sees from then on.
///
/// What is left on the phone is exactly what has not got there yet, which is
/// what [reconcile] retries.
class LyricSharing {
  LyricSharing({required this.store, required this.put, this.onChanged});

  /// Told whenever the lyrics a screen would show may have changed, so what is
  /// already playing can be refreshed rather than waiting for a relaunch.
  final void Function()? onChanged;

  final ManifestStore store;

  /// Sends lyrics to the daemon. True when it took them.
  final Future<bool> Function(String sha, String text) put;

  /// A listener saved these lyrics: keep them, and share them. Always sends,
  /// because this is the listener deciding what the words should be.
  Future<void> save(String sha, String text) async {
    await store.setEdit(sha, 'lyrics', text);
    // Before the network: the words are on this phone now, and the screens
    // should show them now, not after the daemon has answered (or timed out).
    onChanged?.call();
    await put(sha, text);
  }

  /// Run after a sync, when the daemon's copy of every track is fresh.
  ///
  /// For each lyric typed on this phone:
  ///   * the daemon already has exactly these words: done, drop the local copy;
  ///   * the daemon has nothing from a listener: send it (this is also how
  ///     lyrics typed before sharing existed reach everyone, and how an offline
  ///     save gets there);
  ///   * the daemon has different words from a listener: leave both alone. A
  ///     background retry must not undo somebody else's work; only a listener
  ///     saving does that.
  ///
  /// Returns how many were sent.
  Future<int> reconcile() async {
    var sent = 0;
    final edits = await store.lyricEdits();
    for (final e in edits.entries) {
      final server = await store.serverLyrics(e.key);
      if (_same(server.text, e.value)) {
        await store.setEdit(e.key, 'lyrics', null);
        continue;
      }
      if (server.source == 'user') continue;
      if (await put(e.key, e.value)) sent += 1;
    }
    onChanged?.call();
    return sent;
  }

  static bool _same(String? a, String b) =>
      a != null && a.replaceAll('\r\n', '\n').trim() == b.trim();
}
