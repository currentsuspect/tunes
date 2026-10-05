import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../net/tunes_client.dart';

/// On-disk cover cache, keyed by art sha.
///
/// Every sleeve in the app loads from the network; with no local copy a
/// downloaded library still shows empty frames the moment the box is
/// unreachable. Covers are content-addressed and immutable like the audio,
/// so a file on disk is never stale -- presence is the whole index.
class ArtStore extends ChangeNotifier {
  ArtStore(this.dir, {this._client});

  final Directory dir;

  /// Set at download time (see [DownloadManager]) or lazily by [fetch].
  TunesClient? _client;

  void attachClient(TunesClient client) => _client = client;

  final Map<String, String> _bySha = {};
  final Set<String> _inflight = {};

  File get _indexFile => File('${dir.path}/art.json');

  bool contains(String sha) => _bySha.containsKey(sha);

  String? pathFor(String sha) => _bySha[sha];

  Future<void> load() async {
    try {
      if (await _indexFile.exists()) {
        final raw = await _indexFile.readAsString();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        _bySha
          ..clear()
          ..addAll(
            (json['files'] as Map<String, dynamic>? ?? {}).map(
              (k, v) => MapEntry(k, v as String),
            ),
          );
      }
    } catch (_) {
      _bySha.clear();
    }
    // The system can clear app storage out from under the index. An entry
    // whose file is gone would otherwise count as held forever, and the sleeve
    // would show its fallback instead of fetching the cover again.
    _bySha.removeWhere((_, path) => !File(path).existsSync());
    notifyListeners();
  }

  /// When a fetch last failed, per sha. A sleeve asks for its cover each time
  /// it builds; without this, an unreachable box would be asked again for every
  /// visible cover on every scroll frame.
  final Map<String, DateTime> _failedAt = {};
  static const _retryAfter = Duration(seconds: 45);

  /// Fetches a cover unless it is already on disk or in flight. Best effort:
  /// a missing cover is an empty frame, never an error surface.
  Future<void> fetch(String sha) async {
    if (sha.isEmpty || contains(sha) || _inflight.contains(sha)) return;
    final client = _client;
    if (client == null) return;
    final failed = _failedAt[sha];
    if (failed != null && DateTime.now().difference(failed) < _retryAfter) {
      return;
    }
    _inflight.add(sha);
    try {
      final path = '${dir.path}/$sha';
      await client.downloadArt(sha, path);
      _bySha[sha] = path;
      _failedAt.remove(sha);
      _notifySoon();
      _persistSoon();
    } catch (_) {
      // Leave no trace on disk; a later view retries once the pause is up.
      _failedAt[sha] = DateTime.now();
    } finally {
      _inflight.remove(sha);
    }
  }

  /// Saves every cover the library can show, so it looks the same without a
  /// connection.
  ///
  /// Quiet and bounded in the same spirit as the fetch discipline for the box:
  /// a few at a time, and it gives up after a short run of failures, because a
  /// failure here almost always means the server is unreachable and not that
  /// one cover is bad. Whatever was missed is picked up on the next sync or
  /// when a sleeve asks for it.
  Future<void> prefetch(Iterable<String> shas, {int concurrency = 3}) async {
    final queue = [
      for (final sha in shas)
        if (sha.isNotEmpty && !contains(sha)) sha,
    ];
    var failures = 0;
    var next = 0;
    Future<void> worker() async {
      while (failures < 3 && next < queue.length) {
        final sha = queue[next++];
        await fetch(sha);
        failures = contains(sha) ? 0 : failures + 1;
      }
    }

    await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
    await _persist();
  }

  /// What is saved: how many covers and how many bytes.
  Future<({int count, int bytes})> usage() async {
    var bytes = 0;
    var count = 0;
    for (final path in _bySha.values) {
      try {
        bytes += await File(path).length();
        count += 1;
      } catch (_) {}
    }
    return (count: count, bytes: bytes);
  }

  /// Covers are re-fetched on demand, so clearing costs only a re-download.
  Future<void> clear() async {
    for (final path in _bySha.values) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    _bySha.clear();
    _failedAt.clear();
    await _persist();
    notifyListeners();
  }

  Timer? _notifyTimer;

  /// Every sleeve on screen listens to this store, so a prefetch landing a
  /// cover a moment would otherwise rebuild all of them each time. Coalesced:
  /// one repaint per short window, however many covers arrived in it.
  void _notifySoon() {
    _notifyTimer ??= Timer(const Duration(milliseconds: 300), () {
      _notifyTimer = null;
      notifyListeners();
    });
  }

  /// Writes the index now. For tests and shutdown; fetches coalesce their own.
  Future<void> flush() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    await _persist();
  }

  Timer? _persistTimer;

  /// A prefetch lands hundreds of covers in a minute; rewriting the whole index
  /// after each one would be quadratic. Coalesced into one write.
  void _persistSoon() {
    _persistTimer ??= Timer(const Duration(seconds: 2), () {
      _persistTimer = null;
      unawaited(_persist());
    });
  }

  Future<void> _persist() async {
    try {
      await dir.create(recursive: true);
      await _indexFile.writeAsString(jsonEncode({'files': _bySha}));
    } catch (_) {}
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    _notifyTimer?.cancel();
    super.dispose();
  }
}

/// Makes the [ArtStore] reachable from any sleeve without threading it
/// through every screen. Sleeves repaint when the store notifies.
class ArtScope extends InheritedNotifier<ArtStore> {
  const ArtScope({super.key, required ArtStore store, required super.child})
    : super(notifier: store);

  static ArtStore? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ArtScope>()?.notifier;
  }
}
