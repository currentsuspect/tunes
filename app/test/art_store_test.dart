import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/data/art_store.dart';
import 'package:tunes/core/net/tunes_client.dart';

class _FakeClient extends TunesClient {
  _FakeClient() : super('http://test');

  final List<String> fetched = [];

  @override
  Future<void> downloadArt(String sha, String path) async {
    fetched.add(sha);
    await File(path).parent.create(recursive: true);
    await File(path).writeAsBytes(const [1, 2, 3]);
  }
}

void main() {
  late Directory tmp;
  late ArtStore store;
  late _FakeClient client;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('artstore');
    client = _FakeClient();
    store = ArtStore(Directory('${tmp.path}/art'), client: client);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test(
    'fetch writes the file, indexes it, and round-trips the index',
    () async {
      await store.fetch('abc');
      await store.flush();
      expect(client.fetched, ['abc']);
      expect(store.contains('abc'), isTrue);
      expect(await File(store.pathFor('abc')!).exists(), isTrue);

      final again = ArtStore(Directory('${tmp.path}/art'));
      await again.load();
      expect(again.contains('abc'), isTrue);
    },
  );

  test(
    'fetch is a no-op without a client, on doubles, or when present',
    () async {
      final bare = ArtStore(Directory('${tmp.path}/bare'));
      await bare.fetch('abc');
      expect(bare.contains('abc'), isFalse);

      await store.fetch('abc');
      await store.fetch('abc');
      expect(client.fetched, ['abc']);
    },
  );

  test('a failed fetch leaves no trace', () async {
    final failing = _FailingClient();
    final s = ArtStore(Directory('${tmp.path}/fail'), client: failing);
    await s.fetch('abc');
    expect(s.contains('abc'), isFalse);
    expect(await Directory('${tmp.path}/fail').exists(), isFalse);
  });

  test('prefetch saves what is missing and skips what is held', () async {
    await store.fetch('a');
    client.fetched.clear();
    await store.prefetch(['a', 'b', 'c', '']);
    expect(client.fetched.toSet(), {'b', 'c'});
    expect(store.contains('b') && store.contains('c'), isTrue);
  });

  test('prefetch gives up after a run of failures', () async {
    final failing = _CountingFailingClient();
    final s = ArtStore(Directory('${tmp.path}/down'), client: failing);
    await s.prefetch([for (var i = 0; i < 20; i++) 'sha$i'], concurrency: 1);
    // The server is almost certainly unreachable; hammering it for the other
    // seventeen helps nobody.
    expect(failing.calls, 3);
  });

  test('a recent failure is not retried straight away', () async {
    final failing = _CountingFailingClient();
    final s = ArtStore(Directory('${tmp.path}/pause'), client: failing);
    await s.fetch('abc');
    await s.fetch('abc');
    await s.fetch('abc');
    expect(failing.calls, 1);
  });

  test('an index entry whose file has gone is dropped on load', () async {
    await store.fetch('abc');
    await store.flush();
    await File(store.pathFor('abc')!).delete();
    final again = ArtStore(Directory('${tmp.path}/art'));
    await again.load();
    expect(again.contains('abc'), isFalse);
  });

  test('usage counts saved covers and clear removes them', () async {
    await store.fetch('abc');
    var u = await store.usage();
    expect(u.count, 1);
    expect(u.bytes, 3);
    await store.clear();
    u = await store.usage();
    expect(u.count, 0);
    expect(store.contains('abc'), isFalse);
  });
}

class _FailingClient extends TunesClient {
  _FailingClient() : super('http://test');

  @override
  Future<void> downloadArt(String sha, String path) async {
    throw TunesFetchException('art 404');
  }
}

class _CountingFailingClient extends TunesClient {
  _CountingFailingClient() : super('http://test');

  int calls = 0;

  @override
  Future<void> downloadArt(String sha, String path) async {
    calls += 1;
    throw TunesFetchException('unreachable');
  }
}
