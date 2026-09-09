import 'dart:convert';
import 'dart:io';

import '../auth/media_grants.dart';
import '../net/tunes_client.dart';
import '../../domain/manifest.dart';
import 'download_manager.dart';
import 'download_store.dart';

/// LRU file cache for streamed bytes.
///
/// Explicit downloads ([DownloadStore]) are forever and user-managed. This is
/// the opposite: anything played streams once over the network and lands
/// here, so replaying it -- going back to the track that just played -- reads
/// from disk instead of fetching from the cloud again. Entries are evicted
/// least-recently-used past [maxBytes]; an evicted track simply streams
/// again, so the policy is an optimisation, never correctness.
///
/// Only complete files are ever served. A transfer in flight is invisible
/// here until the manager commits it, so a half-written file can never be
/// mistaken for a hit.
class StreamCache {
  StreamCache(this.store, {this.maxBytes = 2 * 1024 * 1024 * 1024});

  final DownloadStore store;

  /// Two gigabytes: a few hundred FLACs, small against a phone, large enough
  /// that yesterday's rotation is still here.
  final int maxBytes;

  Map<String, int> _touched = {};
  DateTime? _persistedAt;

  File get _accessFile => File('${store.dir.path}/access.json');

  Future<void> load() async {
    await store.load();
    try {
      if (await _accessFile.exists()) {
        final raw = await _accessFile.readAsString();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        _touched = {
          for (final e in json.entries)
            if (e.value is int) e.key: e.value as int,
        };
      }
    } catch (_) {
      _touched = {};
    }
    _touched.removeWhere((sha, _) => !store.contains(sha));
  }

  /// A complete cached file, or null. A hit refreshes recency; the write is
  /// throttled so scrubbing through a queue does not fsync every row.
  String? pathFor(String sha) {
    final path = store.pathFor(sha);
    if (path == null) return null;
    if (!File(path).existsSync()) return null;
    _touched[sha] = DateTime.now().millisecondsSinceEpoch;
    final last = _persistedAt;
    if (last == null ||
        DateTime.now().difference(last) > const Duration(seconds: 30)) {
      _persistedAt = DateTime.now();
      _persist();
    }
    return path;
  }

  /// Evicts least-recently-used entries until the cache fits [maxBytes].
  /// Entries never touched rank oldest. A single entry larger than the whole
  /// budget is kept -- deleting the only copy to satisfy the cap would be
  /// the policy defeating its purpose.
  Future<void> sweep() async {
    final shas = store.shas;
    if (shas.isEmpty) return;
    var total = 0;
    final sized = <String, int>{};
    for (final sha in shas) {
      final path = store.pathFor(sha);
      var size = 0;
      if (path != null) {
        try {
          size = await File(path).length();
        } catch (_) {}
      }
      sized[sha] = size;
      total += size;
    }
    if (total <= maxBytes) {
      await _persist();
      return;
    }
    final byAge = shas.toList()
      ..sort((a, b) => (_touched[a] ?? 0).compareTo(_touched[b] ?? 0));
    for (final sha in byAge) {
      if (total <= maxBytes) break;
      if (sized.length == 1) break;
      total -= sized[sha] ?? 0;
      sized.remove(sha);
      _touched.remove(sha);
      await store.remove(sha);
    }
    await _persist();
  }

  Future<void> _persist() async {
    try {
      await store.dir.create(recursive: true);
      await _accessFile.writeAsString(jsonEncode(_touched));
    } catch (_) {}
  }
}

/// Resolves a track to playable bytes: download first, stream cache second,
/// signed URL last.
///
/// The URL fallback also enqueues a background cache of the same bytes, so
/// the second play of anything is a disk read. Enqueueing is idempotent --
/// completed and in-flight shas are skipped -- so resolving a whole queue at
/// open prefetches it without ever doubling a transfer.
class TrackResolver {
  TrackResolver({
    required this.store,
    required this.cache,
    required this.caching,
    required this.client,
    required this.grants,
  });

  final DownloadStore store;
  final StreamCache cache;
  final DownloadManager caching;
  final TunesClient client;
  final MediaGrants grants;

  String uriFor(ManifestTrack track) {
    final sha = track.sha;
    final local = store.pathFor(sha);
    if (local != null && File(local).existsSync()) return local;
    final cached = cache.pathFor(sha);
    if (cached != null) return cached;
    caching.enqueue(sha);
    // Read live, not captured: changing servers repoints the client, and a
    // URL baked at startup would keep streaming from the old address.
    final baseUrl = client.baseUrl;
    final signed = grants.urlFor('/track/$sha');
    return '$baseUrl${signed ?? '/track/$sha'}';
  }
}
