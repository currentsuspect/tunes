import 'package:tunes/core/sync/sync_models.dart';

/// The server's rule, as edge/src/sync.ts applies it: newest write per key,
/// every accepted change numbered.
class FakeSyncServer {
  final docs = <String, SyncDoc>{};
  int seq = 0;
  int? _fixed;

  /// The server's time. Real unless a test pins it, which the engine tests do
  /// to make clocks disagree on purpose.
  int get clock => _fixed ?? DateTime.now().millisecondsSinceEpoch;
  set clock(int v) => _fixed = v;

  FakeSyncTransport as(String device, {bool online = true}) =>
      FakeSyncTransport(this, device)..online = online;
}

class FakeSyncTransport extends SyncTransport {
  FakeSyncTransport(this.server, this.device);
  final FakeSyncServer server;
  final String device;
  bool online = true;

  @override
  Future<int?> push(List<SyncDoc> docs) async {
    if (!online) return null;
    for (final d in docs) {
      final have = server.docs[d.key];
      if (have != null && d.updatedAt <= have.updatedAt) continue;
      server.docs[d.key] = SyncDoc(
        key: d.key,
        value: d.value,
        updatedAt: d.updatedAt,
        deviceId: device,
        seq: ++server.seq,
      );
    }
    return server.clock;
  }

  @override
  Future<SyncPullPage?> pull(int after, {bool onlyLive = false}) async {
    if (!online) return null;
    final docs =
        server.docs.values
            .where((d) => d.seq > after)
            .where(
              (d) =>
                  !onlyLive ||
                  d.key == 'now' ||
                  d.key == 'queue' ||
                  d.key == 'cmd',
            )
            .toList()
          ..sort((a, b) => a.seq.compareTo(b.seq));
    return SyncPullPage(
      docs: docs,
      next: docs.isEmpty ? after : docs.last.seq,
      more: false,
      devices: const {'phone': 'Phone', 'laptop': 'Laptop'},
      serverNow: server.clock,
    );
  }
}
