import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/auth/token_store.dart';
import 'package:tunes/core/auth/tunes_auth.dart';

/// Records calls and replays canned responses. Keeps these tests off the
/// network entirely, per AGENTS.md §6.
class FakeTransport {
  FakeTransport(this.responses);

  final Map<String, ({int status, Map<String, dynamic> body})> responses;
  final List<String> calls = [];
  final List<String?> bearers = [];
  int failuresToThrow = 0;

  Future<({int status, Map<String, dynamic> body})> post(
    String path,
    Map<String, dynamic> body, {
    String? bearer,
  }) async {
    calls.add(path);
    bearers.add(bearer);
    if (failuresToThrow > 0) {
      failuresToThrow--;
      throw const SocketExceptionStub();
    }
    return responses[path] ?? (status: 404, body: <String, dynamic>{});
  }
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}

void main() {
  late DateTime clock;
  DateTime now() => clock;

  setUp(() => clock = DateTime.utc(2026, 9, 8, 12));

  TunesAuth build(FakeTransport t, TokenStore store) =>
      TunesAuth(post: t.post, store: store, now: now);

  group('enrolment', () {
    test(
      'stores the refresh token and immediately returns an access token',
      () async {
        final t = FakeTransport({
          '/auth/redeem': (
            status: 200,
            body: {'refresh_token': 'r-1', 'device_id': 'd-1'},
          ),
          '/auth/token': (
            status: 200,
            body: {'access_token': 'a-1', 'expires_in': 600},
          ),
        });
        final store = MemoryTokenStore();
        final auth = build(t, store);

        final res = await auth.enrol('invite-code', 'Test device');

        expect(res, isA<AuthOk>());
        expect(await store.readRefreshToken(), 'r-1');
        expect(await store.readDeviceId(), 'd-1');
      },
    );

    test(
      'a rejected invite asks for enrolment rather than looking offline',
      () async {
        final t = FakeTransport({
          '/auth/redeem': (status: 401, body: {'error': 'invalid'}),
        });
        final auth = build(t, MemoryTokenStore());
        expect(
          await auth.enrol('bad', 'Test device'),
          isA<AuthNeedsEnrolment>(),
        );
      },
    );
  });

  group('access tokens', () {
    test(
      'with no refresh token, asks for enrolment without calling the server',
      () async {
        final t = FakeTransport({});
        expect(
          await build(t, MemoryTokenStore()).accessToken(),
          isA<AuthNeedsEnrolment>(),
        );
        expect(t.calls, isEmpty);
      },
    );

    test('caches, so repeat calls do not hit the network', () async {
      final t = FakeTransport({
        '/auth/token': (
          status: 200,
          body: {'access_token': 'a-1', 'expires_in': 600},
        ),
      });
      final store = MemoryTokenStore()..writeRefreshToken('r-1');
      final auth = build(t, store);

      await auth.accessToken();
      await auth.accessToken();
      await auth.accessToken();

      expect(t.calls.where((c) => c == '/auth/token').length, 1);
    });

    test('re-mints early, before the token actually expires', () async {
      // 600s TTL with 30s skew: still cached at 560s, refreshed at 580s.
      final t = FakeTransport({
        '/auth/token': (
          status: 200,
          body: {'access_token': 'a-1', 'expires_in': 600},
        ),
      });
      final auth = build(t, MemoryTokenStore()..writeRefreshToken('r-1'));

      await auth.accessToken();
      clock = clock.add(const Duration(seconds: 560));
      expect(auth.hasCachedToken, isTrue);
      clock = clock.add(const Duration(seconds: 20));
      expect(auth.hasCachedToken, isFalse);
    });

    test('a 401 clears the refresh token and demands enrolment', () async {
      // Revoked device. Retrying forever would be the wrong behaviour.
      final t = FakeTransport({
        '/auth/token': (status: 401, body: {'error': 'invalid'}),
      });
      final store = MemoryTokenStore()..writeRefreshToken('r-1');
      final auth = build(t, store);

      expect(await auth.accessToken(), isA<AuthNeedsEnrolment>());
      expect(await store.readRefreshToken(), isNull);
    });

    test('a network failure keeps the refresh token', () async {
      // The distinction that matters: unreachable is not revoked. Clearing
      // here would make a flaky connection cost a manual re-enrolment.
      final t = FakeTransport({})..failuresToThrow = 1;
      final store = MemoryTokenStore()..writeRefreshToken('r-1');
      final auth = build(t, store);

      expect(await auth.accessToken(), isA<AuthUnavailable>());
      expect(await store.readRefreshToken(), 'r-1');
    });
  });

  group('media grants', () {
    test('sends the bearer token and returns the mapping', () async {
      final t = FakeTransport({
        '/auth/token': (
          status: 200,
          body: {'access_token': 'a-1', 'expires_in': 600},
        ),
        '/auth/media/grant': (
          status: 200,
          body: {
            'grants': {
              '/track/aa': '/track/aa?sig=x',
              '/track/bb': '/track/bb?sig=y',
            },
            'expires_in': 14400,
          },
        ),
      });
      final auth = build(t, MemoryTokenStore()..writeRefreshToken('r-1'));

      final grants = await auth.mediaGrants(['/track/aa', '/track/bb']);

      expect(grants.grants['/track/aa'], '/track/aa?sig=x');
      expect(grants.expiresIn, 14400);
      expect(t.bearers.last, 'a-1');
    });

    test('an empty request never touches the network', () async {
      final t = FakeTransport({});
      expect(
        (await build(t, MemoryTokenStore()).mediaGrants([])).grants,
        isEmpty,
      );
      expect(t.calls, isEmpty);
    });

    test('returns empty rather than throwing when unauthenticated', () async {
      // A queue that cannot be signed must fall back to downloads, not crash
      // the player.
      final t = FakeTransport({});
      expect(
        (await build(t, MemoryTokenStore()).mediaGrants(['/track/aa'])).grants,
        isEmpty,
      );
    });
  });

  group('peekClaims', () {
    test('reads a payload without verifying it', () {
      // header.payload.signature where payload is {"sub":"acct-1","did":"d-1"}
      const jwt =
          'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhY2N0LTEiLCJkaWQiOiJkLTEifQ.notchecked';
      expect(peekClaims(jwt), containsPair('sub', 'acct-1'));
    });

    test('returns null on rubbish instead of throwing', () {
      for (final bad in ['', 'a', 'a.b', 'a.b.c', '...']) {
        expect(peekClaims(bad), isNull);
      }
    });
  });
}
