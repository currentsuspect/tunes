import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/sync/sync_engine.dart';
import 'package:tunes/core/sync/sync_models.dart';

import 'support/fake_sync_server.dart';

/// A store that is a map, standing in for likes.
class _MapDomain extends SyncDomain {
  final items = <String, String>{};
  final times = <String, int>{};
  @override
  bool owns(String key) => key.startsWith('like:');
  @override
  Future<Map<String, LocalDoc>> snapshot() async => {
    for (final e in items.entries) e.key: LocalDoc(e.value, times[e.key]),
  };
  @override
  Future<bool> apply(String key, String? value, int updatedAt) async {
    if (value == null) {
      return items.remove(key) != null;
    }
    items[key] = value;
    times[key] = updatedAt;
    return true;
  }
}

class _Memory extends SyncMemory {
  final m = <String, String>{};
  int c = 0;
  @override
  Future<Map<String, String>> marks() async => Map.of(m);
  @override
  Future<void> writeMarks(Map<String, String?> changes) async {
    for (final e in changes.entries) {
      if (e.value == null) {
        m.remove(e.key);
      } else {
        m[e.key] = e.value!;
      }
    }
  }

  @override
  Future<int> cursor() async => c;
  @override
  Future<void> writeCursor(int seq) async => c = seq;
}

class _Device {
  _Device(FakeSyncServer server, String id) {
    transport = server.as(id);
    engine = SyncEngine(
      transport: transport,
      domains: [domain],
      memory: memory,
      deviceId: () async => id,
      now: () => now,
      special: (d, _) => special.add(d.key),
    );
  }
  final domain = _MapDomain();
  final memory = _Memory();
  final special = <String>[];
  late final FakeSyncTransport transport;
  late final SyncEngine engine;
  int now = 1000000;
}

void main() {
  late FakeSyncServer server;
  late _Device phone;
  late _Device laptop;

  setUp(() {
    server = FakeSyncServer()..clock = 1000000;
    phone = _Device(server, 'phone');
    laptop = _Device(server, 'laptop');
  });

  test('a like on the phone turns up on the laptop', () async {
    phone.domain.items['like:a'] = '1';
    phone.domain.times['like:a'] = 1000;
    await phone.engine.run();
    final r = await laptop.engine.run();
    expect(laptop.domain.items['like:a'], '1');
    expect(r.applied, 1);
    expect(r.changed, contains(laptop.domain));
  });

  test('a device with nothing catches up from the beginning', () async {
    for (final k in ['a', 'b', 'c']) {
      phone.domain.items['like:$k'] = '1';
    }
    await phone.engine.run();
    final fresh = _Device(server, 'tablet');
    await fresh.engine.run();
    expect(fresh.domain.items.keys.toSet(), {'like:a', 'like:b', 'like:c'});
  });

  test(
    'unliking on one device removes it on the other, and stays removed',
    () async {
      phone.domain.items['like:a'] = '1';
      await phone.engine.run();
      await laptop.engine.run();
      laptop.now += 10;
      laptop.domain.items.remove('like:a');
      await laptop.engine.run();
      await phone.engine.run();
      expect(phone.domain.items, isEmpty);
      // and the phone does not send it back
      final again = await phone.engine.run();
      expect(again.pushed, 0);
      await laptop.engine.run();
      expect(laptop.domain.items, isEmpty);
    },
  );

  test(
    'changes made offline are kept and sent when the connection returns',
    () async {
      phone.transport.online = false;
      phone.domain.items['like:a'] = '1';
      final offline = await phone.engine.run();
      expect(offline.reached, isFalse);
      await laptop.engine.run();
      expect(laptop.domain.items, isEmpty);

      phone.transport.online = true;
      await phone.engine.run();
      await laptop.engine.run();
      expect(laptop.domain.items['like:a'], '1');
    },
  );

  test('what was just taken is not sent back (no ping-pong)', () async {
    phone.domain.items['like:a'] = '1';
    await phone.engine.run();
    await laptop.engine.run();
    final r1 = await laptop.engine.run();
    final r2 = await phone.engine.run();
    expect(r1.pushed, 0);
    expect(r2.pushed, 0);
  });

  test('the later change wins when two devices disagree', () async {
    // Real time passes for everyone: the server's clock is the shared one.
    void at(_Device d, int t) {
      d.now = t;
      server.clock = t;
    }

    at(phone, 1000000);
    phone.domain.items['like:a'] = 'old';
    await phone.engine.run();
    await laptop.engine.run();

    // Both change it while apart; the laptop's change is the later one.
    at(phone, 1003000);
    phone.domain.items['like:a'] = 'phone';
    phone.domain.times['like:a'] = 1003000;
    at(laptop, 1005000);
    laptop.domain.items['like:a'] = 'laptop';
    laptop.domain.times['like:a'] = 1005000;

    // The laptop gets to the server first, then the phone arrives late.
    await laptop.engine.run();
    at(phone, 1006000);
    await phone.engine.run();
    await laptop.engine.run();
    expect(phone.domain.items['like:a'], 'laptop');
    expect(laptop.domain.items['like:a'], 'laptop');
  });

  test(
    'a device whose clock is behind still stamps changes in the server\'s time',
    () async {
      // The phone thinks it is 10 minutes earlier than the server.
      phone.now = server.clock - 600000;
      phone.domain.items['like:a'] = '1';
      await phone.engine.run(); // learns the offset
      phone.domain.items['like:b'] = '1';
      await phone.engine.run();
      final b = server.docs['like:b']!;
      expect((b.updatedAt - server.clock).abs() < 1000, isTrue);
    },
  );

  test(
    'where it is playing and the queue are handed over, not merged',
    () async {
      await phone.engine.pushNow([
        const SyncDoc(key: 'now', value: '{"sha":"a"}', updatedAt: 5),
      ]);
      await laptop.engine.run();
      expect(laptop.special, ['now']);
      expect(laptop.domain.items, isEmpty);
    },
  );

  test(
    'a document the app cannot apply is skipped, not retried for ever',
    () async {
      server.docs['like:x'] = const SyncDoc(
        key: 'like:x',
        value: '1',
        updatedAt: 1,
        deviceId: 'tablet',
        seq: 1,
      );
      server.seq = 1;
      final bad = _Device(server, 'laptop2');
      final broken = _ThrowingDomain();
      final engine = SyncEngine(
        transport: server.as('laptop2'),
        domains: [broken],
        memory: bad.memory,
        deviceId: () async => 'laptop2',
      );
      await engine.run();
      expect(await bad.memory.cursor(), 1);
    },
  );
}

class _ThrowingDomain extends SyncDomain {
  @override
  bool owns(String key) => true;
  @override
  Future<Map<String, LocalDoc>> snapshot() async => {};
  @override
  Future<bool> apply(String key, String? value, int updatedAt) async =>
      throw StateError('cannot read this');
}
