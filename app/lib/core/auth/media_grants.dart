// Same reason as tunes_auth.dart: the fields are private, so an initializing
// formal would have to be named `_auth`, and Dart forbids named parameters
// beginning with an underscore.
// ignore_for_file: prefer_initializing_formals

import 'tunes_auth.dart';

/// Signed media URLs, cached until they expire.
///
/// Sits between the auth client and everything that needs a URL for bytes:
/// the player, the artwork widgets, and the notification. Those callers are
/// synchronous by nature -- `trackUriFor` is called once per queue entry while
/// building a playlist, and artwork is resolved inside `build()` -- so this
/// separates the async part (minting) from the sync part (lookup).
///
///   await grants.prime(paths);   // one round trip, batched
///   grants.urlFor(path);         // sync, no network
///
/// A miss returns null rather than an unsigned URL. The caller decides what
/// that means: the player falls back to the bare URL so the failure is a
/// visible 403 rather than a silent skip, and artwork simply shows its
/// placeholder.
class MediaGrants {
  MediaGrants({required TunesAuth auth, DateTime Function() now = DateTime.now})
    : _auth = auth,
      _now = now;

  final TunesAuth _auth;
  final DateTime Function() _now;

  final Map<String, ({String url, DateTime expiry})> _cache = {};

  /// The edge caps one mint at 500 paths. "Play all" on this library is 600+,
  /// so requests are chunked rather than truncated -- silently dropping the
  /// tail would produce a queue whose later half does not play.
  static const _chunk = 500;

  /// Re-mint this far before real expiry, so a grant handed to mpv is not
  /// already dead by the time it is fetched.
  static const _skew = Duration(minutes: 5);

  /// Signed URL for [path], or null when there is no live grant.
  String? urlFor(String path) {
    final hit = _cache[path];
    if (hit == null) return null;
    if (!_now().isBefore(hit.expiry)) {
      _cache.remove(path);
      return null;
    }
    return hit.url;
  }

  bool has(String path) => urlFor(path) != null;

  /// Mints grants for any of [paths] that do not already have a live one.
  ///
  /// Cheap to call repeatedly: paths already covered are filtered out before
  /// anything touches the network, so priming a queue that overlaps the last
  /// one costs nothing.
  Future<void> prime(Iterable<String> paths) async {
    final wanted = <String>{};
    for (final p in paths) {
      if (!has(p)) wanted.add(p);
    }
    if (wanted.isEmpty) return;

    final list = wanted.toList(growable: false);
    for (var i = 0; i < list.length; i += _chunk) {
      final slice = list.sublist(
        i,
        i + _chunk > list.length ? list.length : i + _chunk,
      );
      final res = await _auth.mediaGrants(slice);
      if (res.grants.isEmpty) continue;
      final expiry = _now()
          .add(Duration(seconds: res.expiresIn))
          .subtract(_skew);
      for (final e in res.grants.entries) {
        _cache[e.key] = (url: e.value, expiry: expiry);
      }
    }
  }

  /// Drops everything. Used when the device is re-enrolled or the server
  /// changes, since grants are signed for one device against one origin.
  void clear() => _cache.clear();

  int get cachedCount => _cache.length;
}
