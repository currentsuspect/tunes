import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../audio/tune_player.dart';
import '../../domain/manifest.dart';
import 'now_sync.dart';
import 'sync_models.dart';

/// The player the screens talk to.
///
/// Usually it is this device's own player and does nothing but pass through.
/// When music is playing on another device of the same account and this one is
/// silent, it becomes a window onto that: [current], [position] and [playing]
/// are the other device's, kept moving between reports, and the transport
/// buttons send commands to it instead of making sound here. Playing something
/// on this device ends that and takes the music over.
///
/// Everything that must describe *this device's* listening (history, the radio,
/// where to resume after a relaunch, the notification) is attached to the local
/// player underneath, not to this.
class ConnectPlayer extends TunePlayer {
  ConnectPlayer({
    required this.local,
    required this.remote,
    required this.resolve,
    required this.serverNow,
    required this.send,
  }) {
    local.addListener(_onLocal);
    remote.addListener(_onRemote);
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_live() && remote.playing) notifyListeners();
      _recompute();
    });
  }

  final TunePlayer local;
  final RemoteNow remote;

  /// A track by its sha, from the library. Null when it is not in it.
  final ManifestTrack? Function(String sha) resolve;

  /// The server's clock in ms as far as this device can tell.
  final int Function() serverNow;

  /// Sends a command to the device that is playing. True when it was handed on.
  final Future<bool> Function(SyncDoc command) send;

  Timer? _timer;
  bool _announced = false;

  /// When this device last *chose* to play (server ms). Another device's
  /// session only counts if it *started* after that.
  ///
  /// By start, not by latest report: the playing device reports every few
  /// seconds, so comparing reports let its next heartbeat win the moment this
  /// device's own audio had a gap (loading a track, a brief pause), and the
  /// screen flipped back to the other device's music under a tap -- the "dip in
  /// dip out" of a phone that would not let you play on it.
  int _localSince = 0;
  int _lastLocalPlayingAt = 0;

  /// What the buttons just did, shown at once while the other device catches up.
  bool? _optimisticPlaying;
  int _optimisticUntil = 0;

  bool get isRemote => _live();

  /// When a command was last sent, until the other device answers by
  /// reporting. Null when nothing is waiting.
  int? _waitingSince;

  /// The device was told something and has not reported back for a few
  /// seconds: it may have been closed. The pill then offers to play here.
  @override
  bool get remoteStalled {
    final w = _waitingSince;
    return isRemote && w != null && serverNow() - w > 5000;
  }

  @override
  String? get remoteDeviceLabel => isRemote ? remote.deviceLabel : null;

  void _onLocal() {
    if (local.playing) {
      final now = serverNow();
      // A gap of a couple of seconds is the same stretch of playing (a track
      // loading), not a new choice.
      if (now - _lastLocalPlayingAt > 4000) _localSince = now;
      _lastLocalPlayingAt = now;
    }
    _recompute();
    notifyListeners();
  }

  void _onRemote() {
    _optimisticPlaying = null;
    _waitingSince = null;
    _recompute();
    notifyListeners();
  }

  /// Whether this is showing another device's music, worked out from the
  /// clock every time it is asked: a session lapses by the time passing, with
  /// no event to say so, and a screen reading a stale answer would sit on a
  /// session that has ended.
  bool _live() =>
      !local.playing &&
      remote.sessionOpen(serverNow()) &&
      remote.since > _localSince;

  /// Wakes the screens when the answer changes.
  void _recompute() {
    final should = _live();
    if (should != _announced) {
      _announced = should;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    local.removeListener(_onLocal);
    remote.removeListener(_onRemote);
    super.dispose();
  }

  // --- what the screens read ------------------------------------------------

  List<ManifestTrack> _remoteQueue() => [
    for (final sha in remote.queueToContinue)
      if (resolve(sha) != null) resolve(sha)!,
  ];

  @override
  List<ManifestTrack> get queue => isRemote ? _remoteQueue() : local.queue;

  @override
  int get index {
    if (!isRemote) return local.index;
    final i = _remoteQueue().indexWhere((t) => t.sha == remote.sha);
    return i < 0 ? 0 : i;
  }

  @override
  ManifestTrack? get current =>
      isRemote ? resolve(remote.sha ?? '') : local.current;

  @override
  bool get playing {
    if (!isRemote) return local.playing;
    final o = _optimisticPlaying;
    if (o != null && serverNow() < _optimisticUntil) return o;
    return remote.playing;
  }

  @override
  Duration get position =>
      isRemote ? remote.estimatedPosition(serverNow()) : local.position;

  @override
  Duration get duration {
    if (!isRemote) return local.duration;
    final ms = current?.durationMs;
    return ms == null ? Duration.zero : Duration(milliseconds: ms);
  }

  @override
  PlaybackRepeat get repeat => local.repeat;
  @override
  bool get shuffle => local.shuffle;

  // --- what the buttons do --------------------------------------------------

  static final _rng = Random.secure();

  Future<void> _command(
    String action, {
    int? positionMs,
    int? at,
    bool? optimisticPlaying,
  }) async {
    final to = remote.deviceId;
    if (to == null) return;
    if (optimisticPlaying != null) {
      _optimisticPlaying = optimisticPlaying;
      _optimisticUntil = serverNow() + 4000;
      notifyListeners();
    }
    _waitingSince ??= serverNow();
    final id = _rng.nextInt(1 << 31).toRadixString(36);
    await send(
      SyncDoc(
        key: 'cmd',
        value: jsonEncode({
          'id': id,
          'to': to,
          'action': action,
          'positionMs': ?positionMs,
          'index': ?at,
        }),
        updatedAt: serverNow(),
      ),
    );
  }

  @override
  void play() => isRemote
      ? unawaited(_command('play', optimisticPlaying: true))
      : local.play();

  @override
  void pause() => isRemote
      ? unawaited(_command('pause', optimisticPlaying: false))
      : local.pause();

  @override
  void toggle() => isRemote ? (playing ? pause() : play()) : local.toggle();

  @override
  void next() => isRemote ? unawaited(_command('next')) : local.next();

  @override
  void previous() =>
      isRemote ? unawaited(_command('previous')) : local.previous();

  @override
  void playAt(int i) =>
      isRemote ? unawaited(_command('playAt', at: i)) : local.playAt(i);

  @override
  void seek(Duration target) => isRemote
      ? unawaited(_command('seek', positionMs: target.inMilliseconds))
      : local.seek(target);

  @override
  void stop() => isRemote ? pause() : local.stop();

  @override
  void playQueue(List<ManifestTrack> tracks, int startIndex) {
    // Choosing music on this device is choosing to play it here.
    _endRemote();
    local.playQueue(tracks, startIndex);
  }

  @override
  Future<void> playHere() async {
    if (!isRemote) return;
    final tracks = _remoteQueue();
    if (tracks.isEmpty) return;
    var i = tracks.indexWhere((t) => t.sha == remote.sha);
    if (i < 0) i = 0;
    final at = remote.estimatedPosition(serverNow());
    unawaited(_command('pause', optimisticPlaying: false));
    _endRemote();
    local.restoreQueue(tracks, i, at: at);
    local.play();
  }

  void _endRemote() {
    _localSince = serverNow();
    _lastLocalPlayingAt = _localSince;
    _recompute();
  }

  @override
  void setRepeat(PlaybackRepeat mode) => local.setRepeat(mode);
  @override
  void setShuffle(bool on) => local.setShuffle(on);

  // --- things that are only ever about this device ---------------------------

  @override
  void setVolume(double level) => local.setVolume(level);
  @override
  Future<void> setGapless(bool on) => local.setGapless(on);
  @override
  void halt() => local.halt();
  @override
  void restoreQueue(
    List<ManifestTrack> tracks,
    int startIndex, {
    Duration at = Duration.zero,
  }) {
    _endRemote();
    local.restoreQueue(tracks, startIndex, at: at);
  }

  @override
  void refreshTracks(Map<String, ManifestTrack> fresh) =>
      local.refreshTracks(fresh);

  @override
  void refreshSources({bool touchCurrent = false}) =>
      local.refreshSources(touchCurrent: touchCurrent);

  @override
  void networkReturned() => local.networkReturned();

  @override
  Future<ManifestTrack?> Function(ManifestTrack lastPlayed)? get onQueueEnded =>
      local.onQueueEnded;
  @override
  set onQueueEnded(Future<ManifestTrack?> Function(ManifestTrack)? v) =>
      local.onQueueEnded = v;
  @override
  Future<void> Function()? get onRestored => local.onRestored;
  @override
  set onRestored(Future<void> Function()? v) => local.onRestored = v;
}

/// The library by sha, kept current by whoever loads it, so another device's
/// music can be named without a database read on every frame.
class LibraryIndex {
  Map<String, ManifestTrack> _by = const {};

  void update(List<ManifestTrack> tracks) {
    _by = {for (final t in tracks) t.sha: t};
  }

  ManifestTrack? bySha(String sha) => _by[sha];
}
