import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/audio/stream_relay.dart';

const _sha = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

/// A server that answers ranges like the fetch worker, and can be told to
/// stop part-way through a body (a phone stepping out of signal).
class _Upstream {
  _Upstream(this.body);

  final Uint8List body;
  late HttpServer server;
  final List<String?> ranges = [];
  int? dieAfter;
  int served = 0;
  int refuse = 0;
  Duration lag = Duration.zero;

  /// Requests from this many on are accepted and never answered.
  int? hangFrom;
  int requests = 0;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final range = req.headers.value(HttpHeaders.rangeHeader);
      ranges.add(range);
      requests += 1;
      final hang = hangFrom;
      if (hang != null && requests >= hang) return; // never answers
      if (refuse > 0) {
        refuse -= 1;
        req.response.statusCode = HttpStatus.forbidden;
        await req.response.close();
        return;
      }
      final m = range == null
          ? null
          : RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
      final start = m == null ? 0 : int.parse(m.group(1)!);
      final end = body.length - 1;
      final res = req.response;
      res.headers.contentType = ContentType('audio', 'flac');
      if (m != null) {
        res.statusCode = HttpStatus.partialContent;
        res.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/${body.length}',
        );
      }
      res.contentLength = end - start + 1;
      // Headers first, body after a pause: the order a real server's answer
      // reaches the phone in.
      if (lag > Duration.zero) {
        await res.flush();
        await Future<void>.delayed(lag);
      }
      var pos = start;
      try {
        while (pos <= end) {
          final n = (end + 1 - pos).clamp(0, 64 * 1024);
          final limit = dieAfter;
          if (limit != null && served >= limit) {
            await req.response.detachSocket().then((s) => s.destroy());
            return;
          }
          res.add(body.sublist(pos, pos + n));
          await res.flush();
          served += n;
          pos += n;
        }
        await res.close();
      } catch (_) {}
    });
  }

  Uri get uri => Uri.parse('http://127.0.0.1:${server.port}/t/$_sha');
}

Uint8List _bytes(int n) =>
    Uint8List.fromList(List<int>.generate(n, (i) => (i * 31 + 7) & 0xff));

/// Reads [want] bytes of the body and hangs up, as mpv does on a seek.
Future<({int status, Uint8List body})> _peek(
  String url, {
  required String range,
  int want = 64 * 1024,
}) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set(HttpHeaders.rangeHeader, range);
    final res = await req.close().timeout(const Duration(seconds: 20));
    final out = BytesBuilder();
    final done = Completer<void>();
    late StreamSubscription<List<int>> sub;
    sub = res.listen(
      (c) {
        out.add(c);
        if (out.length >= want && !done.isCompleted) done.complete();
      },
      onDone: () => done.isCompleted ? null : done.complete(),
      onError: (_) => done.isCompleted ? null : done.complete(),
    );
    await done.future.timeout(const Duration(seconds: 20));
    await sub.cancel();
    final b = out.takeBytes();
    return (
      status: res.statusCode,
      body: b.length > want ? b.sublist(0, want) : b,
    );
  } finally {
    client.close(force: true);
  }
}

Future<({int status, Uint8List body})> _get(String url, {String? range}) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    if (range != null) req.headers.set(HttpHeaders.rangeHeader, range);
    final res = await req.close();
    final out = BytesBuilder();
    try {
      await for (final c in res) {
        out.add(c);
      }
    } catch (_) {
      // A stream that ends early is part of what is being tested.
    }
    return (status: res.statusCode, body: out.takeBytes());
  } finally {
    client.close(force: true);
  }
}

void main() {
  late Directory dir;
  late _Upstream up;
  late StreamRelay relay;
  final committed = <String, String>{};

  final refused = <String>[];

  Future<void> setUpRelay(
    Uint8List body, {
    Uri? upstream,
    Duration stallAfter = const Duration(seconds: 15),
  }) async {
    up = _Upstream(body);
    await up.start();
    relay = StreamRelay(
      dir: dir,
      upstreamFor: (_) async => upstream ?? up.uri,
      commit: (sha, path) async => committed[sha] = path,
      onRefused: refused.add,
      stallAfter: stallAfter,
      window: 256 * 1024,
    );
    await relay.start();
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('relay');
    committed.clear();
    refused.clear();
  });

  tearDown(() async {
    await relay.close();
    await up.server.close(force: true);
    await dir.delete(recursive: true);
  });

  test('a song played through arrives whole and lands in the cache', () async {
    final body = _bytes(900 * 1024);
    await setUpRelay(body);
    relay.keepAll(_sha);
    final got = await _get(relay.urlFor(_sha)!, range: 'bytes=0-');
    expect(got.status, HttpStatus.partialContent);
    expect(got.body, body);
    for (var i = 0; i < 50 && committed.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(committed[_sha], isNotNull);
    expect(await File(committed[_sha]!).readAsBytes(), body);
  });

  test(
    'a seek before the bytes arrived is fetched from the new spot',
    () async {
      final body = _bytes(600 * 1024);
      await setUpRelay(body);
      final from = 400 * 1024;
      final got = await _get(relay.urlFor(_sha)!, range: 'bytes=$from-');
      expect(got.status, HttpStatus.partialContent);
      expect(got.body, body.sublist(from));
      expect(up.ranges.first, 'bytes=$from-');
    },
  );

  test('a seek into bytes already here needs no new fetch', () async {
    final body = _bytes(300 * 1024);
    await setUpRelay(body);
    relay.keepAll(_sha);
    await _get(relay.urlFor(_sha)!, range: 'bytes=0-');
    final calls = up.ranges.length;
    final got = await _get(relay.urlFor(_sha)!, range: 'bytes=1000-');
    expect(got.body, body.sublist(1000));
    expect(up.ranges.length, calls);
  });

  test('offline, a song with nothing on the phone fails fast', () async {
    final body = _bytes(1000);
    // Nothing listens on port 9: the connection is refused at once.
    await setUpRelay(body, upstream: Uri.parse('http://127.0.0.1:9/t/x'));
    final sw = Stopwatch()..start();
    final got = await _get(relay.urlFor(_sha)!, range: 'bytes=0-');
    expect(got.status, HttpStatus.badGateway);
    expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
  });

  test('when the signal goes mid-song, what arrived still plays', () async {
    final body = _bytes(1024 * 1024);
    await setUpRelay(body);
    up.dieAfter = 512 * 1024;
    relay.keepAll(_sha);
    final got = await _get(relay.urlFor(_sha)!, range: 'bytes=0-');
    expect(got.body.length, greaterThanOrEqualTo(512 * 1024));
    expect(got.body.length, lessThan(body.length));
    expect(got.body, body.sublist(0, got.body.length));
    expect(committed, isEmpty);
  });

  test('a song only touched is fetched a window ahead, not whole', () async {
    final body = _bytes(4 * 1024 * 1024);
    await setUpRelay(body);
    final got = await _get(relay.urlFor(_sha)!, range: 'bytes=0-1023');
    expect(got.body, body.sublist(0, 1024));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(relay.progressOf(_sha).have, lessThan(body.length));
    expect(committed, isEmpty);
  });

  test('a refused signature is renewed and the song still plays', () async {
    final body = _bytes(200 * 1024);
    await setUpRelay(body);
    up.refuse = 1;
    final got = await _get(relay.urlFor(_sha)!, range: 'bytes=0-');
    expect(got.status, HttpStatus.partialContent);
    expect(got.body, body);
    expect(refused, [_sha]);
  });

  test('seeks like mpv: fresh, inside, then past, on a slow server', () async {
    final body = _bytes(8 * 1024 * 1024);
    await setUpRelay(body);
    up.lag = const Duration(milliseconds: 300);
    final url = relay.urlFor(_sha)!;
    const a = 3 * 1024 * 1024;
    final first = await _peek(url, range: 'bytes=$a-');
    expect(first.status, HttpStatus.partialContent);
    expect(first.body, body.sublist(a, a + 64 * 1024));
    const b = a + 400 * 1024;
    final inside = await _peek(url, range: 'bytes=$b-');
    expect(inside.body, body.sublist(b, b + 64 * 1024));
    const c = 7 * 1024 * 1024;
    final past = await _peek(url, range: 'bytes=$c-');
    expect(past.status, HttpStatus.partialContent);
    expect(past.body, body.sublist(c, c + 64 * 1024));
  });

  test('a fetch that never gets an answer frees its slot', () async {
    final body = _bytes(2 * 1024 * 1024);
    await setUpRelay(body, stallAfter: const Duration(seconds: 2));
    up.hangFrom = 1; // every request hangs
    final shas = [for (var i = 0; i < 3; i++) '${'0' * 63}$i'];
    // Three songs take all three slots and hang.
    final stuck = [
      for (final s in shas)
        _peek(
          relay.urlFor(s)!,
          range: 'bytes=0-',
        ).catchError((_) => (status: 0, body: Uint8List(0))),
    ];
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // The server answers again; a fourth song must still get a slot once
    // the watchdog has cut the hung runs off.
    up.hangFrom = null;
    final fresh = await _peek(relay.urlFor(_sha)!, range: 'bytes=0-');
    expect(fresh.status, HttpStatus.partialContent);
    expect(fresh.body, body.sublist(0, 64 * 1024));
    await Future.wait(stuck);
  });

  test('a reader that hangs up stops counting as a listener', () async {
    final body = _bytes(8 * 1024 * 1024);
    await setUpRelay(body);
    up.lag = const Duration(milliseconds: 200);
    await _peek(relay.urlFor(_sha)!, range: 'bytes=0-');
    for (var i = 0; i < 40; i++) {
      if (relay.readersOf(_sha) == 0) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(relay.readersOf(_sha), 0);
  });
}
