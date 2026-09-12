import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/data/art_store.dart';
import 'package:tunes/core/data/download_manager.dart';
import 'package:tunes/core/data/download_store.dart';
import 'package:tunes/core/net/tunes_client.dart';

/// A client whose downloads finish only when the test says so, so queueing and
/// cancellation can be observed rather than raced.
class _FakeClient extends TunesClient {
  _FakeClient() : super('http://test');

  final Map<String, Completer<void>> started = {};
  final Map<String, void Function(int, int)> progressOf = {};
  final Map<String, CancelSignal?> signals = {};

  @override
  Future<void> downloadTrack(
    String sha,
    String path, {
    void Function(int received, int total)? onProgress,
    CancelSignal? cancel,
  }) async {
    signals[sha] = cancel;
    if (onProgress != null) progressOf[sha] = onProgress;
    final gate = Completer<void>();
    started[sha] = gate;
    await gate.future;
    if (cancel != null && cancel.isCancelled) {
      throw const DownloadCancelled();
    }
  }

  void finish(String sha) => started[sha]?.complete();
  void fail(String sha, Object error) => started[sha]?.completeError(error);
}

/// A real async gap. `Future.delayed(Duration.zero)` only drains microtasks,
/// but completing a download writes the index to disk, so the queue needs an
/// actual event-loop turn before the next job starts.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 60));

void main() {
  late Directory tmp;
  late DownloadStore store;
  late _FakeClient client;
  late DownloadManager manager;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('dlmgr');
    store = DownloadStore(tmp);
    client = _FakeClient();
    manager = DownloadManager(client: client, store: store, maxConcurrent: 2);
  });

  tearDown(() async {
    manager.dispose();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('a second tap on the same track does not start a second transfer', () {
    manager.enqueue('a');
    manager.enqueue('a');
    expect(client.started.length, 1);
    expect(manager.activeCount, 1);
  });

  test('holds concurrency at the configured limit', () async {
    manager.enqueue('a');
    manager.enqueue('b');
    manager.enqueue('c');
    await settle();
    // Three requested, two in flight: the third waits its turn instead of
    // opening a third socket.
    expect(client.started.keys, containsAll(<String>['a', 'b']));
    expect(client.started.containsKey('c'), isFalse);

    client.finish('a');
    await settle();
    expect(client.started.containsKey('c'), isTrue);
  });

  test('reports real progress, not just busy', () async {
    manager.enqueue('a');
    await settle();
    client.progressOf['a']!(512, 2048);
    expect(manager.jobFor('a')!.progress, closeTo(0.25, 0.0001));
    expect(manager.jobFor('a')!.received, 512);
  });

  test('progress is null rather than invented when size is unknown', () async {
    manager.enqueue('a');
    await settle();
    client.progressOf['a']!(512, 0);
    expect(manager.jobFor('a')!.progress, isNull);
  });

  test('cancelling a queued track drops it without starting it', () async {
    manager.enqueue('a');
    manager.enqueue('b');
    manager.enqueue('c');
    await settle();
    manager.cancel('c');
    expect(manager.jobFor('c'), isNull);
    expect(client.started.containsKey('c'), isFalse);
  });

  test('cancelling a running track signals the client', () async {
    manager.enqueue('a');
    await settle();
    manager.cancel('a');
    expect(client.signals['a']!.isCancelled, isTrue);
  });

  test('a cancelled download leaves no job and is not recorded', () async {
    manager.enqueue('a');
    await settle();
    manager.cancel('a');
    client.finish('a');
    await settle();
    expect(manager.jobFor('a'), isNull);
    expect(store.contains('a'), isFalse);
  });

  test('a failure is kept visible so the row can offer a retry', () async {
    manager.enqueue('a');
    await settle();
    client.fail('a', StateError('boom'));
    await settle();
    final job = manager.jobFor('a');
    expect(job, isNotNull);
    expect(job!.phase, DownloadPhase.failed);
    expect(manager.isActive('a'), isFalse);

    manager.dismiss('a');
    expect(manager.jobFor('a'), isNull);
  });

  test('a completed download is recorded and stops being a job', () async {
    manager.enqueue('a');
    await settle();
    client.finish('a');
    await settle();
    expect(store.contains('a'), isTrue);
    expect(manager.jobFor('a'), isNull);
  });

  test('an already-downloaded track is not queued again', () async {
    await store.add('a', '${tmp.path}/a');
    manager.enqueue('a');
    expect(client.started.containsKey('a'), isFalse);
  });

  test('the cover rides along with the download when one is named', () async {
    final art = _FakeArt(tmp);
    final m = DownloadManager(
      client: client,
      store: store,
      artStore: art,
      maxConcurrent: 2,
    );
    m.enqueue('a', artSha: 'cover-a');
    await settle();
    expect(art.fetched, ['cover-a']);
    m.dispose();
  });

  test(
    'no cover named means no art fetch, and no store means no crash',
    () async {
      final art = _FakeArt(tmp);
      final m = DownloadManager(
        client: client,
        store: store,
        artStore: art,
        maxConcurrent: 2,
      );
      m.enqueue('a');
      await settle();
      expect(art.fetched, isEmpty);
      m.dispose();
      manager.enqueue('b');
      await settle();
      expect(client.started.containsKey('b'), isTrue);
    },
  );
}

class _FakeArt extends ArtStore {
  _FakeArt(super.dir);

  final List<String> fetched = [];

  @override
  Future<void> fetch(String sha) async {
    fetched.add(sha);
  }
}
