import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/net/tunes_client.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tunes-cache-');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test(
    'manifest cache serves the library when the daemon is unreachable',
    () async {
      final seededManifest = jsonEncode({
        'schema': 1,
        'generatedAt': '2026-08-28T00:00:00Z',
        'integrity': 'x',
        'tracks': [
          {
            'sha': 'a' * 64,
            'size': 10,
            'codec': 'flac',
            'sampleRate': 44100,
            'channels': 2,
            'bitrate': 950000,
            'durationMs': 125000,
            'title': 'Cached Title',
            'artist': 'Cached Artist',
            'album': 'Cached Album',
            'year': null,
          },
        ],
      });
      await File('${tempDir.path}/manifest.json').writeAsString(seededManifest);

      final client = TunesClient('http://127.0.0.1:1', tempDir);
      final manifest = await client.fetchManifest();

      expect(manifest.tracks.length, 1);
      expect(manifest.tracks.first.title, 'Cached Title');
    },
  );

  test('no cache and no daemon throws honestly', () async {
    final client = TunesClient('http://127.0.0.1:1', tempDir);
    await expectLater(
      client.fetchManifest(),
      throwsA(isA<TunesFetchException>()),
    );
  });

  test(
    'a sync is not fooled by the cache: it fails when the daemon is down',
    () async {
      // The offline bug: the cached copy came back as if it were fresh, the app
      // recorded "synced just now" and, once online again, only asked what had
      // changed since that moment -- so anything added meanwhile never arrived.
      await File('${tempDir.path}/manifest.json').writeAsString(
        jsonEncode({'schema': 1, 'integrity': 'x', 'tracks': []}),
      );
      final client = TunesClient('http://127.0.0.1:1', tempDir);
      await expectLater(
        client.fetchManifest(fromCacheOnFailure: false),
        throwsA(isA<TunesFetchException>()),
      );
    },
  );
}
