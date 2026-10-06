import 'dart:async';
import 'dart:convert';

import '../audio/tune_player.dart';
import 'sync_engine.dart';
import 'sync_models.dart';

/// What makes two devices behave as one listener.
///
///  * **Commands**: another device of the account can pause, play, seek or skip
///    this one. Only commands addressed to this device, newer than a few
///    seconds, and not already run are obeyed.
///  * **One at a time**: if another device starts playing after this one did,
///    this one stops, so a phone and a computer never play at once. The later
///    start wins, by the start times each device reports, which both sides read
///    the same way.
///  * **The fast lane**: while there is any music in play, asks the server every
///    second or two for where it is and what it was told to do, otherwise every
///    few seconds, so a change on one device shows on the other almost at once.
class ConnectControl {
  ConnectControl({
    required this.local,
    required this.engine,
    required this.serverNow,
    required this.isBusy,
  });

  final TunePlayer local;
  final SyncEngine engine;
  final int Function() serverNow;

  /// True while this device is playing or showing another's music: the cue to
  /// poll quickly.
  final bool Function() isBusy;

  static const _stale = Duration(seconds: 20);
  static const _quick = Duration(milliseconds: 1000);
  static const _idle = Duration(seconds: 5);

  Timer? _timer;
  bool _foreground = true;
  bool _polling = false;
  bool _disposed = false;
  String? _lastCommand;
  int _since = 0;
  bool _wasPlaying = false;
  int _lastPlayingAt = 0;
  DateTime? _lastPlayedWall;

  /// Keep listening after the app leaves the screen for this long after the
  /// last time it played, so a phone in a pocket can still be paused.
  static const _grace = Duration(minutes: 15);

  bool get _awake {
    if (_foreground || local.playing) return true;
    final last = _lastPlayedWall;
    return last != null && DateTime.now().difference(last) < _grace;
  }

  void start() {
    local.addListener(_onLocal);
    _schedule();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    local.removeListener(_onLocal);
  }

  void setForeground(bool v) {
    _foreground = v;
    if (v) _schedule(now: true);
  }

  void _onLocal() {
    if (local.playing) {
      final now = serverNow();
      // Same rule as the published start time: a gap of a couple of seconds is
      // the same stretch of playing.
      if (!_wasPlaying && now - _lastPlayingAt > 4000) _since = now;
      _lastPlayingAt = now;
      _lastPlayedWall = DateTime.now();
    }
    _wasPlaying = local.playing;
  }

  void _schedule({bool now = false}) {
    _timer?.cancel();
    if (_disposed) return;
    _timer = Timer(now ? Duration.zero : (isBusy() ? _quick : _idle), () async {
      if (_awake && !_polling) {
        _polling = true;
        try {
          await engine.pollLive();
        } catch (_) {
          // Offline is ordinary; the next beat tries again.
        } finally {
          _polling = false;
        }
      }
      _schedule();
    });
  }

  /// A `now`, `queue` or `cmd` document from the server.
  void onDoc(SyncDoc doc, String? me) {
    if (doc.value == null || me == null) return;
    try {
      if (doc.key == 'cmd') {
        _command(doc, me);
      } else if (doc.key == 'now' && doc.deviceId != me) {
        _takeover(doc);
      }
    } catch (_) {
      // A document this build cannot read is not worth a crash.
    }
  }

  void _command(SyncDoc doc, String me) {
    final j = jsonDecode(doc.value!);
    if (j is! Map || j['to'] != me) return;
    final id = j['id'] as String?;
    if (id == null || id == _lastCommand) return;
    if (serverNow() - doc.updatedAt > _stale.inMilliseconds) return;
    _lastCommand = id;
    switch (j['action']) {
      case 'play':
        local.play();
      case 'pause':
        local.pause();
      case 'next':
        local.next();
      case 'previous':
        local.previous();
      case 'seek':
        final ms = (j['positionMs'] as num?)?.toInt();
        if (ms != null) local.seek(Duration(milliseconds: ms));
      case 'playAt':
        final i = (j['index'] as num?)?.toInt();
        if (i != null) local.playAt(i);
    }
  }

  void _takeover(SyncDoc doc) {
    if (!local.playing) return;
    final j = jsonDecode(doc.value!);
    if (j is! Map || j['playing'] != true) return;
    final theirs = (j['since'] as num?)?.toInt() ?? 0;
    // They started after we did: the music is theirs now.
    if (theirs > _since) local.pause();
  }
}
