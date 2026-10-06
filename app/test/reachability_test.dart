import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/data/reachability.dart';
import 'package:tunes/core/net/tunes_client.dart';

void main() {
  group('Reachability', () {
    test('one or two missed answers do not make the app say offline', () {
      final r = Reachability();
      r.failed();
      r.failed();
      expect(r.offline, isFalse);
    });

    test('three in a row do, and one answer brings it straight back', () {
      final r = Reachability();
      r.failed();
      r.failed();
      r.failed();
      expect(r.offline, isTrue);
      r.ok();
      expect(r.offline, isFalse);
    });

    test('an answer in between starts the count again', () {
      final r = Reachability();
      r.failed();
      r.failed();
      r.ok();
      r.failed();
      r.failed();
      expect(r.offline, isFalse);
    });

    test('does not announce the same state twice', () {
      final r = Reachability();
      var n = 0;
      r.addListener(() => n++);
      for (var i = 0; i < 6; i++) {
        r.failed();
      }
      expect(n, 1);
    });
  });

  group('Heartbeat', () {
    test('a flaky check never flips a good connection', () async {
      final r = Reachability();
      final answers = [false, true, false, false, true, false, true];
      var i = 0;
      final beat = Heartbeat(ping: () async => answers[i++], reachability: r);
      var flipped = false;
      r.addListener(() => flipped = true);
      for (var k = 0; k < answers.length; k++) {
        await beat.probe();
      }
      expect(flipped, isFalse);
    });

    test(
      'a connection that is really gone is noticed in three checks',
      () async {
        final r = Reachability();
        final beat = Heartbeat(ping: () async => false, reachability: r);
        await beat.probe();
        await beat.probe();
        expect(r.offline, isFalse);
        await beat.probe();
        expect(r.offline, isTrue);
      },
    );
  });

  group('the check itself', () {
    late HttpServer server;
    late String? hit;
    late int status;

    setUp(() async {
      hit = null;
      status = 200;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        hit = req.uri.path;
        req.response.statusCode = status;
        req.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    test('asks the tiny public /update, not the library', () async {
      final c = TunesClient('http://127.0.0.1:${server.port}');
      expect(await c.ping(), isTrue);
      expect(hit, '/update');
    });

    test('a 401 is the server being there; a 503 is not', () async {
      final c = TunesClient('http://127.0.0.1:${server.port}');
      status = 401;
      expect(await c.ping(), isTrue);
      status = 503;
      expect(await c.ping(), isFalse);
    });

    test('nothing listening is not reachable', () async {
      final port = server.port;
      await server.close(force: true);
      expect(await TunesClient('http://127.0.0.1:$port').ping(), isFalse);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    });
  });
}
