import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/data/database.dart';
import 'package:tunes/core/data/lyric_sharing.dart';
import 'package:tunes/core/data/manifest_store.dart';
import 'package:tunes/core/net/tunes_client.dart';
import 'package:tunes/domain/manifest.dart';

/// Lyrics one listener adds reaching everyone: what the phone keeps, what it
/// sends, and when it lets go of its own copy.
ManifestTrack _track(String sha, {String? lyrics, String? source}) =>
    ManifestTrack(
      sha: sha,
      size: 1,
      codec: 'flac',
      sampleRate: 44100,
      channels: 2,
      bitrate: 900000,
      durationMs: 180000,
      title: 'T $sha',
      artist: 'A',
      album: 'Al',
      year: null,
      artSha: null,
      releaseId: null,
      trackNumber: null,
      discNumber: null,
      lyrics: lyrics,
      lyricsSource: source,
    );

void main() {
  late TunesDatabase db;
  late ManifestStore store;
  late List<(String, String)> sent;
  late bool accept;
  late LyricSharing sharing;

  setUp(() {
    db = TunesDatabase.forTesting(NativeDatabase.memory());
    store = ManifestStore(db);
    sent = [];
    accept = true;
    sharing = LyricSharing(
      store: store,
      put: (sha, text) async {
        sent.add((sha, text));
        return accept;
      },
    );
  });

  tearDown(() => db.close());

  Future<void> serverHas(String sha, {String? lyrics, String? source}) async {
    await store.apply(
      TunesManifest(
        tracks: [_track(sha, lyrics: lyrics, source: source)],
        releases: const [],
      ),
    );
  }

  group('what the manifest carries is kept', () {
    test(
      'the daemon\'s lyrics survive a sync (they used to be dropped)',
      () async {
        await serverHas('a', lyrics: '[00:01.00] hi', source: 'lrclib');
        final t = await store.trackBySha('a');
        expect(t.lyrics, '[00:01.00] hi');
        expect(t.lyricsSource, 'lrclib');
      },
    );

    test('a later sync brings a change in', () async {
      await serverHas('a', lyrics: 'first', source: 'lrclib');
      await serverHas('a', lyrics: 'second', source: 'user');
      expect((await store.trackBySha('a')).lyrics, 'second');
    });

    test(
      'the daemon\'s copy can be read apart from this phone\'s own',
      () async {
        await serverHas('a', lyrics: 'theirs', source: 'user');
        await store.setEdit('a', 'lyrics', 'mine');
        expect((await store.trackBySha('a')).lyrics, 'mine');
        final raw = await store.serverLyrics('a');
        expect(raw.text, 'theirs');
        expect(raw.source, 'user');
      },
    );
  });

  group('saving lyrics', () {
    test('shows at once and is sent', () async {
      await serverHas('a');
      await sharing.save('a', 'my words');
      expect((await store.trackBySha('a')).lyrics, 'my words');
      expect(sent, [('a', 'my words')]);
    });

    test('is kept when the daemon cannot be reached', () async {
      await serverHas('a');
      accept = false;
      await sharing.save('a', 'my words');
      expect((await store.trackBySha('a')).lyrics, 'my words');
      expect(await store.lyricEdits(), {'a': 'my words'});
    });
  });

  group('after a sync', () {
    test(
      'lets go of its own copy once the daemon has the same words',
      () async {
        await serverHas('a');
        await store.setEdit('a', 'lyrics', 'my words');
        await serverHas('a', lyrics: 'my words\n', source: 'user');
        expect(await sharing.reconcile(), 0);
        expect(await store.lyricEdits(), isEmpty);
        expect((await store.trackBySha('a')).lyrics, 'my words\n');
        expect(sent, isEmpty);
      },
    );

    test(
      'sends what the daemon has not seen, which retries an offline save',
      () async {
        await serverHas('a');
        accept = false;
        await sharing.save('a', 'my words');
        accept = true;
        sent.clear();
        expect(await sharing.reconcile(), 1);
        expect(sent, [('a', 'my words')]);
      },
    );

    test(
      'sends lyrics typed before sharing existed, over a fetched copy',
      () async {
        await serverHas('a', lyrics: 'from lrclib', source: 'lrclib');
        await store.setEdit('a', 'lyrics', 'older edit');
        expect(await sharing.reconcile(), 1);
        expect(sent.single, ('a', 'older edit'));
      },
    );

    test('does not undo somebody else\'s lyrics in the background', () async {
      await serverHas('a', lyrics: 'theirs', source: 'user');
      await store.setEdit('a', 'lyrics', 'mine');
      expect(await sharing.reconcile(), 0);
      expect(sent, isEmpty);
      // Both are left alone; only saving again would replace theirs.
      expect(await store.lyricEdits(), {'a': 'mine'});
    });

    test('keeps the local copy when the send fails', () async {
      await serverHas('a');
      await store.setEdit('a', 'lyrics', 'mine');
      accept = false;
      expect(await sharing.reconcile(), 0);
      expect(await store.lyricEdits(), {'a': 'mine'});
    });
  });

  group('talking to the daemon', () {
    late HttpServer server;
    late String base;
    final seen = <(String, String, String?, String)>[];
    var status = 204;

    setUp(() async {
      seen.clear();
      status = 204;
      server = await HttpServer.bind('127.0.0.1', 0);
      base = 'http://127.0.0.1:${server.port}';
      server.listen((req) async {
        final body = await utf8.decodeStream(req);
        seen.add((
          req.method,
          req.uri.path,
          req.headers.value('authorization'),
          body,
        ));
        if (req.uri.path == '/changes') {
          req.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'generatedAt': '2026-10-05T00:00:00Z',
                'integrity': 'x',
                'addedShas': <String>[],
                'lyricsChanged': ['a', 'b'],
              }),
            );
        } else {
          req.response.statusCode = status;
        }
        await req.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    test(
      'PUT carries the words and the bearer token, and 204 is success',
      () async {
        final client = TunesClient(base)..bearer = () async => 'tok';
        expect(await client.putLyrics('a' * 64, 'hello'), isTrue);
        final (method, path, auth, body) = seen.single;
        expect(method, 'PUT');
        expect(path, '/lyrics/${'a' * 64}');
        expect(auth, 'Bearer tok');
        expect(jsonDecode(body), {'lyrics': 'hello'});
      },
    );

    test('a refusal is a plain false, not an exception', () async {
      status = 404;
      expect(await TunesClient(base).putLyrics('a' * 64, 'x'), isFalse);
      // Nobody listening at all.
      expect(
        await TunesClient('http://127.0.0.1:1').putLyrics('a', 'x'),
        isFalse,
      );
    });

    test('/changes reports which tracks\' lyrics changed', () async {
      final r = await TunesClient(base).fetchChanges(DateTime(2026));
      expect(r.addedShas, isEmpty);
      expect(r.lyricsChanged, ['a', 'b']);
    });

    test('a daemon that predates lyrics reports none', () {
      const r = ChangesResponse(
        generatedAt: null,
        integrity: 'x',
        addedShas: [],
      );
      expect(r.lyricsChanged, isEmpty);
    });
  });
}
