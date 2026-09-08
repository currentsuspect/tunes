import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/auth/media_grants.dart';
import 'package:tunes/core/auth/token_store.dart';
import 'package:tunes/core/auth/tunes_auth.dart';

/// Mints a URL per requested path and records every batch, so the tests can
/// assert on chunking and on how often the network was touched.
class GrantSpy {
  GrantSpy({this.expiresIn = 14400});

  final int expiresIn;
  final List<List<String>> batches = [];
  bool refuse = false;

  Future<({int status, Map<String, dynamic> body})> post(
    String path,
    Map<String, dynamic> body, {
    String? bearer,
  }) async {
    if (path == '/auth/token') {
      return (status: 200, body: {'access_token': 'a-1', 'expires_in': 600});
    }
    final paths = (body['paths'] as List).cast<String>();
    batches.add(paths);
    if (refuse) return (status: 403, body: <String, dynamic>{});
    return (
      status: 200,
      body: {
        'grants': {for (final p in paths) p: '$p?sig=deadbeef'},
        'expires_in': expiresIn,
      },
    );
  }
}

void main() {
  late DateTime clock;
  DateTime now() => clock;

  setUp(() => clock = DateTime.utc(2026, 9, 8, 12));

  MediaGrants build(GrantSpy spy) => MediaGrants(
    auth: TunesAuth(
      post: spy.post,
      store: MemoryTokenStore()..writeRefreshToken('r-1'),
      now: now,
    ),
    now: now,
  );

  test('primes and then resolves synchronously', () async {
    final spy = GrantSpy();
    final g = build(spy);

    expect(g.urlFor('/track/aa'), isNull);
    await g.prime(['/track/aa']);
    expect(g.urlFor('/track/aa'), '/track/aa?sig=deadbeef');
  });

  test('does not re-request paths it already holds', () async {
    final spy = GrantSpy();
    final g = build(spy);

    await g.prime(['/track/aa', '/track/bb']);
    await g.prime(['/track/aa', '/track/bb']);

    expect(spy.batches, hasLength(1));
  });

  test('asks only for the paths that are missing', () async {
    final spy = GrantSpy();
    final g = build(spy);

    await g.prime(['/track/aa']);
    await g.prime(['/track/aa', '/track/bb']);

    expect(spy.batches.last, ['/track/bb']);
  });

  test('chunks a queue larger than the edge cap', () async {
    // "Play all" on this library is 600+ tracks against a 500 cap. Truncating
    // would produce a queue whose second half silently does not play.
    final spy = GrantSpy();
    final g = build(spy);
    final many = List.generate(
      1200,
      (i) => '/track/${i.toString().padLeft(3, '0')}',
    );

    await g.prime(many);

    expect(spy.batches.map((b) => b.length).toList(), [500, 500, 200]);
    expect(g.cachedCount, 1200);
  });

  test('a grant stops resolving before it actually expires', () async {
    // 4h TTL with a 5m skew: live at 3h50m, gone at 3h56m.
    final spy = GrantSpy(expiresIn: 14400);
    final g = build(spy);
    await g.prime(['/track/aa']);

    clock = clock.add(const Duration(hours: 3, minutes: 50));
    expect(g.urlFor('/track/aa'), isNotNull);

    clock = clock.add(const Duration(minutes: 6));
    expect(g.urlFor('/track/aa'), isNull);
  });

  test('re-primes a path whose grant has expired', () async {
    final spy = GrantSpy();
    final g = build(spy);
    await g.prime(['/track/aa']);

    clock = clock.add(const Duration(hours: 5));
    await g.prime(['/track/aa']);

    expect(spy.batches, hasLength(2));
    expect(g.urlFor('/track/aa'), isNotNull);
  });

  test('a refused mint leaves no grant rather than a broken one', () async {
    final spy = GrantSpy()..refuse = true;
    final g = build(spy);

    await g.prime(['/track/aa']);

    expect(g.urlFor('/track/aa'), isNull);
  });

  test('priming nothing never touches the network', () async {
    final spy = GrantSpy();
    await build(spy).prime([]);
    expect(spy.batches, isEmpty);
  });

  test('clear drops everything', () async {
    final spy = GrantSpy();
    final g = build(spy);
    await g.prime(['/track/aa']);
    g.clear();
    expect(g.urlFor('/track/aa'), isNull);
    expect(g.cachedCount, 0);
  });
}
