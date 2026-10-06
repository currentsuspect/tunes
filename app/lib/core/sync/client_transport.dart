import '../net/tunes_client.dart';
import 'sync_models.dart';

/// [SyncTransport] over the app's own client, so sync rides the same address,
/// bearer token and timeouts as everything else.
class ClientSyncTransport extends SyncTransport {
  ClientSyncTransport(this.client);
  final TunesClient client;

  @override
  Future<int?> push(List<SyncDoc> docs) => client.syncPush(docs);

  @override
  Future<SyncPullPage?> pull(int after, {bool onlyLive = false}) =>
      client.syncPull(after, onlyLive: onlyLive);
}
