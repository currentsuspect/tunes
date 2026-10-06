/// The wire shapes of account sync (see edge/src/sync.ts).
library;

/// One thing a listener owns, as it travels between a device and the server.
class SyncDoc {
  const SyncDoc({
    required this.key,
    required this.value,
    required this.updatedAt,
    this.deviceId,
    this.seq = 0,
  });

  /// `like:<sha>`, `playlist:<uuid>`, `edit:<sha>:<field>`, `profile`,
  /// `now`, `queue`.
  final String key;

  /// Null means deleted. Kept as a tombstone so a device that was offline
  /// when it happened does not bring the thing back.
  final String? value;

  /// When the listener made the change, in ms. Decides which of two writes wins.
  final int updatedAt;

  /// Which device wrote it. Only present on documents that came from the server.
  final String? deviceId;
  final int seq;

  bool get deleted => value == null;

  Map<String, Object?> toJson() => {
    'key': key,
    'value': value,
    'deleted': deleted,
    'updatedAt': updatedAt,
  };

  static SyncDoc? fromJson(Object? json) {
    if (json is! Map) return null;
    final key = json['key'];
    final at = json['updatedAt'];
    if (key is! String || at is! num) return null;
    final deleted = json['deleted'] == true;
    final value = json['value'];
    if (!deleted && value is! String) return null;
    return SyncDoc(
      key: key,
      value: deleted ? null : value as String,
      updatedAt: at.toInt(),
      deviceId: json['deviceId'] as String?,
      seq: (json['seq'] as num?)?.toInt() ?? 0,
    );
  }
}

class SyncPullPage {
  const SyncPullPage({
    required this.docs,
    required this.next,
    required this.more,
    required this.devices,
    required this.serverNow,
  });

  final List<SyncDoc> docs;

  /// Ask for everything after this to carry on from here.
  final int next;
  final bool more;

  /// Device id to the name it was enrolled with, so "playing on Laptop" needs
  /// no second request.
  final Map<String, String> devices;

  /// The server's clock in ms, from which a device works out how far off its
  /// own is.
  final int serverNow;

  static SyncPullPage? fromJson(Object? json) {
    if (json is! Map) return null;
    final docs = <SyncDoc>[];
    for (final d in (json['docs'] as List?) ?? const []) {
      final doc = SyncDoc.fromJson(d);
      if (doc != null) docs.add(doc);
    }
    final devices = <String, String>{};
    final raw = json['devices'];
    if (raw is Map) {
      for (final e in raw.entries) {
        if (e.key is String && e.value is String) {
          devices[e.key as String] = e.value as String;
        }
      }
    }
    return SyncPullPage(
      docs: docs,
      next: (json['next'] as num?)?.toInt() ?? 0,
      more: json['more'] == true,
      devices: devices,
      serverNow: (json['now'] as num?)?.toInt() ?? 0,
    );
  }
}

/// What the app needs from the network for sync. An interface so the engine
/// can be tested without one.
abstract class SyncTransport {
  /// Sends [docs]. Returns the server's clock in ms, or null when it could not
  /// be done (offline, refused): the caller keeps the changes and tries again.
  Future<int?> push(List<SyncDoc> docs);

  /// Everything after [after], or null when it could not be fetched.
  ///
  /// [onlyLive] asks for just where the music is, the queue and commands: the
  /// fast lane a device polls every second or two while music is in play.
  Future<SyncPullPage?> pull(int after, {bool onlyLive = false});
}
