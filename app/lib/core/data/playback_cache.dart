import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../audio/stream_relay.dart';
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
  StreamCache(this.store, {this.maxBytes = 5 * 1024 * 1024 * 1024});

  final DownloadStore store;

  /// How much the cache may hold. Set from Settings (see
  /// [SettingsStore.cacheBytes]); a smaller size takes effect at the next
  /// sweep.
  int maxBytes;

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

  Future<void>? _sweeping;
  DateTime? _sweptAt;

  /// [sweep], at most once per [every] and never two at a time. Resolving a
  /// queue asks for one per song, and each sweep sizes every file in the
  /// cache: a long queue opening meant hundreds of full passes over the disk.
  Future<void> sweepSoon({Duration every = const Duration(seconds: 30)}) {
    final running = _sweeping;
    if (running != null) return running;
    final last = _sweptAt;
    if (last != null && DateTime.now().difference(last) < every) {
      return Future<void>.value();
    }
    final run = sweep().whenComplete(() {
      _sweeping = null;
      _sweptAt = DateTime.now();
    });
    _sweeping = run;
    return run;
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
/// Resolving never starts a transfer. It used to enqueue a background copy of
/// every queue entry as the queue opened, and those copies raced the stream
/// the listener was waiting on for the same bytes. Caching is now
/// [StreamFollower]'s job, and starts only once playback has.
class TrackResolver {
  TrackResolver({
    required this.store,
    required this.cache,
    required this.caching,
    required this.client,
    required this.grants,
    this.relay,
    this.prefetchOk,
  });

  final DownloadStore store;
  final StreamCache cache;
  final DownloadManager caching;
  final TunesClient client;
  final MediaGrants grants;

  /// Plays streamed songs through the phone, keeping every byte (see
  /// [StreamRelay]). Null, or not started, means straight from the server.
  final StreamRelay? relay;

  /// Whether fetching a whole song ahead of being reached is wanted now (the
  /// listener's choice, and whether the phone is on Wi-Fi).
  final Future<bool> Function()? prefetchOk;

  String uriFor(ManifestTrack track) {
    final sha = track.sha;
    final local = store.pathFor(sha);
    if (local != null && File(local).existsSync()) return local;
    final cached = cache.pathFor(sha);
    if (cached != null) return cached;
    // Read live, not captured: changing servers repoints the client, and a
    // URL baked at startup would keep streaming from the old address.
    //
    // Streams ride /t/ (cloud fetch path: DO + R2 + Telegram), same host,
    // same device grant shape. Explicit downloads stay on origin /track.
    final relayed = relay?.urlFor(sha);
    if (relayed != null) return relayed;
    final baseUrl = client.baseUrl;
    final signed = grants.urlFor('/t/$sha');
    return '$baseUrl${signed ?? '/t/$sha'}';
  }

  Future<void> _warmSigned(String sha) async {
    final path = '/t/$sha';
    try {
      if (!grants.has(path)) await grants.prime([path]);
    } catch (_) {
      // Unsigned, the worker refuses it; warming is only a hint.
    }
    await client.warm(sha, signedPath: grants.urlFor(path));
  }

  /// Whether the bytes for [track] are already on this phone, either way.
  bool isLocal(ManifestTrack track) =>
      store.pathFor(track.sha) != null || cache.pathFor(track.sha) != null;

  /// Keep a copy of a track that is already playing, so the next play is a
  /// disk read. Idempotent: finished and in-flight shas are skipped.
  void keep(ManifestTrack track) {
    if (isLocal(track)) return;
    final r = relay;
    if (r != null && r.port != null) {
      // The relay already has what was heard; it fetches the rest now.
      r.keepAll(track.sha);
    } else {
      caching.enqueue(track.sha);
    }
  }

  /// Ask the server to have a cold track ready for when it is reached, and,
  /// where the listener allows it, bring the whole song onto the phone.
  void warm(ManifestTrack track) {
    if (isLocal(track)) return;
    unawaited(_warmSigned(track.sha));
    final r = relay;
    final ok = prefetchOk;
    if (r == null || r.port == null || ok == null) return;
    unawaited(
      ok().then((yes) {
        if (yes) r.prefetch(track.sha);
      }),
    );
  }
}

/// Decides when a streamed track is worth keeping and what to warm up next.
///
/// Fed the player's state on every tick. Nothing happens until the current
/// track has actually played for [after]: by then its stream is established
/// and a second transfer of the same bytes cannot slow it. Then the track is
/// kept, and the next [ahead] tracks in the queue are warmed, once each, so
/// they start without a wait when reached.
class StreamFollower {
  StreamFollower({
    required this.keep,
    required this.warm,
    this.after = const Duration(seconds: 3),
    this.afterFor,
    this.ahead = 2,
  });

  final void Function(ManifestTrack) keep;
  final void Function(ManifestTrack) warm;
  final Duration after;

  /// Overrides [after] per tick when set: on Wi-Fi a song is kept almost at
  /// once, on mobile data only once it has clearly been chosen.
  final Duration Function()? afterFor;
  final int ahead;

  String? _sha;
  bool _started = false;
  final Set<String> _warmed = {};

  void tick({
    required List<ManifestTrack> queue,
    required int index,
    required Duration position,
    required bool playing,
  }) {
    if (index < 0 || index >= queue.length) return;
    final current = queue[index];
    if (current.sha != _sha) {
      _sha = current.sha;
      _started = false;
    }
    if (_started || !playing || position < (afterFor?.call() ?? after)) return;
    _started = true;
    keep(current);
    for (var i = index + 1; i <= index + ahead && i < queue.length; i++) {
      if (_warmed.add(queue[i].sha)) warm(queue[i]);
    }
  }
}
