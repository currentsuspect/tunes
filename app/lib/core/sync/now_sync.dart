import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../audio/tune_player.dart';
import 'sync_models.dart';

/// Where the listener's music is on some other device.
///
/// Not state to merge but a fact to show: the device that played last is the
/// one that is "now playing", and every other device just reads it.
class RemoteNow extends ChangeNotifier {
  String? deviceId;
  String? deviceLabel;
  String? sha;
  int index = 0;
  int positionMs = 0;
  bool playing = false;

  /// When that device's current stretch of playing began (server ms). Two
  /// devices playing at once settle by this: the one that started later keeps
  /// the music, the earlier one stops.
  int since = 0;

  /// Server time in ms of the last report.
  int updatedAt = 0;

  /// The queue it is playing, if the same device reported one.
  List<String> queue = const [];
  String? _queueDevice;

  bool get hasState => sha != null && deviceId != null;

  /// A device that is playing reports every 15 seconds; three missed reports
  /// and it is not playing any more, whatever it last said.
  bool isLive(int serverNowMs) => playing && serverNowMs - updatedAt < 45000;

  /// Whether there is a session on another device worth showing: it is
  /// playing, or it stopped within the last few minutes (so a pause from here
  /// can be undone from here).
  bool sessionOpen(int serverNowMs) =>
      hasState &&
      (isLive(serverNowMs) ||
          (!playing && serverNowMs - updatedAt < 3 * 60 * 1000));

  /// Where that device has got to, allowing for the time since it said so.
  Duration estimatedPosition(int serverNowMs) {
    final drift = playing
        ? (serverNowMs - updatedAt).clamp(0, 6 * 3600 * 1000)
        : 0;
    return Duration(milliseconds: positionMs + drift);
  }

  /// The queue to continue with, only when it is the one that device holds.
  List<String> get queueToContinue =>
      _queueDevice == deviceId && queue.isNotEmpty ? queue : [?sha];

  /// Takes a `now` or `queue` document from the server. Documents this
  /// device wrote itself are ignored.
  void ingest(SyncDoc doc, Map<String, String> devices, String? me) {
    if (doc.deviceId == null) return;
    if (doc.deviceId == me) {
      // This device spoke last, so whatever another device said earlier is
      // history: without this, pausing here would bring back "last played on
      // Laptop" about a song that was already left behind.
      if (doc.key == 'now' && doc.updatedAt >= updatedAt && sha != null) {
        sha = null;
        notifyListeners();
      }
      return;
    }
    try {
      if (doc.key == 'now') {
        if (doc.value == null) return;
        // An older report arriving late (a slow request, a re-pull) must not
        // move the picture backwards.
        if (doc.updatedAt < updatedAt && doc.deviceId == deviceId) return;
        final j = jsonDecode(doc.value!);
        if (j is! Map) return;
        deviceId = doc.deviceId;
        deviceLabel = devices[doc.deviceId] ?? 'another device';
        sha = j['sha'] as String?;
        index = (j['index'] as num?)?.toInt() ?? 0;
        positionMs = (j['positionMs'] as num?)?.toInt() ?? 0;
        playing = j['playing'] == true;
        since = (j['since'] as num?)?.toInt() ?? 0;
        updatedAt = doc.updatedAt;
        notifyListeners();
      } else if (doc.key == 'queue') {
        if (doc.value == null) return;
        final j = jsonDecode(doc.value!);
        if (j is! Map) return;
        queue = [for (final s in (j['shas'] as List?) ?? const []) s as String];
        _queueDevice = doc.deviceId;
        notifyListeners();
      }
    } catch (_) {
      // A document this build cannot read is not worth a crash.
    }
  }
}

/// Tells the account where this device's music is.
///
/// Only once the listener has actually played something this session: a
/// relaunch that restores the queue paused is not the listener doing anything,
/// and announcing it would overwrite where they really left off on another
/// device with where this one happened to be.
class NowPublisher {
  NowPublisher({
    required this.player,
    required this.push,
    int Function()? now,
    this.skew = _noSkew,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final TunePlayer player;

  /// Sends documents; true when they were taken.
  final Future<bool> Function(List<SyncDoc> docs) push;
  final int Function() _now;

  /// How far this device's clock is behind the server's, so [since] is
  /// comparable with another device's.
  final int Function() skew;
  static int _noSkew() => 0;

  static const _beat = Duration(seconds: 8);
  static const _settle = Duration(milliseconds: 250);
  static const _jump = Duration(seconds: 2);

  int _since = 0;
  int _lastPlayingAt = 0;
  Duration _expected = Duration.zero;
  int _expectedAt = 0;

  Timer? _timer;
  Timer? _debounce;
  bool _active = false;
  bool _dirty = false;
  String? _lastSha;
  bool _lastPlaying = false;
  String _lastQueue = '';
  bool _sending = false;

  void start() {
    player.addListener(_onPlayer);
    _timer = Timer.periodic(_beat, (_) => _tick());
  }

  void dispose() {
    player.removeListener(_onPlayer);
    _timer?.cancel();
    _debounce?.cancel();
  }

  void _onPlayer() {
    final cur = player.current;
    if (cur == null) return;
    if (player.playing) _active = true;
    if (!_active) return;
    final queueKey = [for (final t in player.queue) t.sha].join(',');
    final at = _now();
    // A seek is a position that is not where playing from the last report
    // would have got to. Said at once, or a remote view drifts until the next
    // heartbeat.
    final jumped =
        player.playing &&
        (player.position -
                    (_expected + Duration(milliseconds: at - _expectedAt)))
                .abs() >
            _jump;
    if (player.playing && !_lastPlaying && at - _lastPlayingAt > 4000) {
      _since = at + skew();
    }
    if (player.playing) _lastPlayingAt = at;
    _expected = player.position;
    _expectedAt = at;
    if (cur.sha != _lastSha ||
        player.playing != _lastPlaying ||
        queueKey != _lastQueue ||
        jumped) {
      _dirty = true;
      _debounce?.cancel();
      _debounce = Timer(_settle, _publish);
    }
  }

  void _tick() {
    if (!_active) return;
    if (player.playing || _dirty) _publish();
  }

  Future<void> _publish() async {
    if (_sending) {
      _dirty = true;
      return;
    }
    final cur = player.current;
    if (cur == null) return;
    _sending = true;
    try {
      final at = _now();
      final shas = [for (final t in player.queue) t.sha];
      final queueKey = shas.join(',');
      final docs = <SyncDoc>[
        SyncDoc(
          key: 'now',
          value: jsonEncode({
            'sha': cur.sha,
            'index': player.index,
            'positionMs': player.position.inMilliseconds,
            'playing': player.playing,
            'since': _since,
          }),
          updatedAt: at,
        ),
        if (queueKey != _lastQueue && shas.length <= 500)
          SyncDoc(
            key: 'queue',
            value: jsonEncode({'shas': shas}),
            updatedAt: at,
          ),
      ];
      final ok = await push(docs);
      if (ok) {
        _dirty = false;
        _lastSha = cur.sha;
        _lastPlaying = player.playing;
        if (docs.length > 1) _lastQueue = queueKey;
      } else {
        _dirty = true;
      }
    } finally {
      _sending = false;
    }
  }
}
