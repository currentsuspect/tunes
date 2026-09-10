import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/auth/media_grants.dart';
import 'package:tunes/core/auth/token_store.dart';
import 'package:tunes/core/auth/tunes_auth.dart';
import 'package:tunes/core/data/download_manager.dart';
import 'package:tunes/core/data/download_store.dart';
import 'package:tunes/core/data/playback_cache.dart';
import 'package:tunes/core/net/tunes_client.dart';
import 'package:tunes/domain/manifest.dart';

/// Streamed bytes are cached on disk, LRU-capped, so replaying a track reads
/// locally instead of fetching from the cloud again.
void main() {
  late Directory tempDir;
  late DownloadStore downloads;
  late DownloadStore cacheStore;
  late StreamCache cache;

  ManifestTrack track(String sha, String title) => ManifestTrack(
    sha: sha,
    size: 1000,
    codec: 'mp3',
    sampleRate: 44100,
    channels: 2,
    bitrate: 320000,
    durationMs: 125000,
    title: title,
    artist: 'Artist',
    album: 'Album',
    year: null,
    artSha: null,
    releaseId: null,
    trackNumber: null,
    discNumber: null,
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tunes-cache-test-');
    downloads = DownloadStore(Directory('${tempDir.path}/dl'));
    await downloads.load();
    cacheStore = DownloadStore(Directory('${tempDir.path}/cache'));
    await cacheStore.load();
    cache = StreamCache(cacheStore);
    await cache.load();
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('StreamCache', () {
    test('a miss is null', () {
      expect(cache.pathFor('x' * 64), isNull);
    });

    test('sweep evicts least-recently-used past the cap', () async {
      final small = StreamCache(cacheStore, maxBytes: 150);
      await small.load();
      for (final sha in ['a' * 64, 'b' * 64]) {
        final f = File(cacheStore.newPathFor(sha));
        await f.parent.create(recursive: true);
        await f.writeAsBytes(List.filled(100, 1));
        await cacheStore.add(sha, f.path);
      }
      // Only 'b' was touched recently; 'a' ranks oldest.
      small.pathFor('b' * 64);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await small.sweep();
      expect(cacheStore.contains('a' * 64), isFalse);
      expect(cacheStore.contains('b' * 64), isTrue);
      expect(File('${tempDir.path}/cache/${'a' * 64}').existsSync(), isFalse);
    });

    test('a hit refreshes recency and survives the next sweep', () async {
      final small = StreamCache(cacheStore, maxBytes: 250);
      await small.load();
      for (final sha in ['a' * 64, 'b' * 64]) {
        final f = File(cacheStore.newPathFor(sha));
        await f.parent.create(recursive: true);
        await f.writeAsBytes(List.filled(100, 1));
        await cacheStore.add(sha, f.path);
      }
      // Both fit (200 <= 250). Touch 'a' so a later tighter cap keeps it.
      small.pathFor('a' * 64);
      await small.sweep();
      expect(cacheStore.contains('a' * 64), isTrue);
      expect(cacheStore.contains('b' * 64), isTrue);
    });
  });

  group('TrackResolver', () {
    late _FakeClient client;
    late MediaGrants grants;
    late DownloadManager caching;
    late TrackResolver resolver;

    setUp(() {
      client = _FakeClient();
      final auth = TunesAuth(
        post: (_, _, {bearer}) async =>
            (status: 401, body: <String, dynamic>{}),
        store: MemoryTokenStore(),
      );
      grants = MediaGrants(auth: auth);
      caching = DownloadManager(client: client, store: cacheStore);
      resolver = TrackResolver(
        store: downloads,
        cache: cache,
        caching: caching,
        client: client,
        grants: grants,
      );
    });

    test('an explicit download wins and never touches the network', () async {
      final f = File('${tempDir.path}/dl/${'a' * 64}');
      await f.create(recursive: true);
      await f.writeAsBytes(const [1, 2, 3]);
      await downloads.add('a' * 64, f.path);
      client.baseUrl = 'http://box:4780';
      expect(resolver.uriFor(track('a' * 64, 'A')), f.path);
      expect(client.downloads, isEmpty);
      expect(caching.jobs, isEmpty);
    });

    test('a second play of a streamed track reads from disk', () async {
      client.baseUrl = 'http://box:4780';
      final t = track('b' * 64, 'B');
      // First play: nothing local, so a signed-or-bare URL -- and a
      // background cache starts behind it.
      final first = resolver.uriFor(t);
      expect(first, startsWith('http://box:4780/t/'));
      expect(caching.jobFor('b' * 64), isNotNull);
      // Let the background transfer land.
      for (var i = 0; i < 50 && !cacheStore.contains('b' * 64); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(cacheStore.contains('b' * 64), isTrue);
      // Second play: the disk copy, no URL, no new transfer.
      final before = client.downloads.length;
      expect(resolver.uriFor(t), cacheStore.pathFor('b' * 64));
      expect(client.downloads.length, before);
    });
  });
}

class _FakeClient extends TunesClient {
  _FakeClient() : super('http://fake:4780', Directory.systemTemp);

  final List<String> downloads = [];

  @override
  Future<void> downloadTrack(
    String sha,
    String path, {
    void Function(int received, int total)? onProgress,
    CancelSignal? cancel,
  }) async {
    downloads.add(sha);
    final f = File(path);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(List.filled(100, 7));
  }
}
