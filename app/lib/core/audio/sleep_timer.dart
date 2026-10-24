import 'dart:async';

import 'package:flutter/widgets.dart';

import 'tune_player.dart';

/// When the music stops on its own (design approved 24 Oct).
enum SleepMode { off, timed, endOfSong, endOfAlbum }

/// Stops the music after a while, or at the end of this song or album, and
/// lets it fade over the last minute instead of cutting out mid-line.
///
/// It pauses rather than stops: the queue and the place in it stay, so the
/// morning starts where the night ended.
class SleepTimer extends ChangeNotifier {
  SleepTimer({
    required this.player,
    this.restoreLevel = _full,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final TunePlayer player;

  /// The player's level to go back to after a fade: the desktop has its own
  /// volume slider, the phone plays at full and leaves loudness to the phone.
  final double Function() restoreLevel;
  final DateTime Function() _now;

  static double _full() => 1;

  static const fadeOver = Duration(seconds: 60);

  SleepMode _mode = SleepMode.off;
  DateTime? _endsAt;
  String? _songSha;
  String? _releaseId;
  bool _fade = true;
  bool _faded = false;
  Timer? _tick;

  SleepMode get mode => _mode;
  bool get active => _mode != SleepMode.off;
  bool get fade => _fade;

  /// Time left on a timed sleep; null for the end-of modes and when off.
  Duration? get remaining {
    final end = _endsAt;
    if (_mode != SleepMode.timed || end == null) return null;
    final left = end.difference(_now());
    return left.isNegative ? Duration.zero : left;
  }

  set fade(bool on) {
    _fade = on;
    if (!on) _unfade();
    notifyListeners();
  }

  void start(Duration after) {
    _begin(SleepMode.timed);
    _endsAt = _now().add(after);
    notifyListeners();
  }

  void endOfSong() {
    _begin(SleepMode.endOfSong);
    notifyListeners();
  }

  void endOfAlbum() {
    _begin(SleepMode.endOfAlbum);
    notifyListeners();
  }

  /// Ten more minutes, from now or from when it was due, whichever is later.
  void extend([Duration by = const Duration(minutes: 10)]) {
    if (_mode != SleepMode.timed) {
      start(by);
      return;
    }
    final base = _endsAt!.isAfter(_now()) ? _endsAt! : _now();
    _endsAt = base.add(by);
    _unfade();
    notifyListeners();
  }

  void cancel() {
    _tick?.cancel();
    _tick = null;
    _unfade();
    _mode = SleepMode.off;
    _endsAt = null;
    player.removeListener(_onPlayer);
    notifyListeners();
  }

  void _begin(SleepMode mode) {
    cancel();
    _mode = mode;
    final cur = player.current;
    _songSha = cur?.sha;
    _releaseId = cur?.releaseId;
    player.addListener(_onPlayer);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _check());
  }

  /// The end-of modes watch the track change: a new song, or a song from
  /// another record, means it is time.
  void _onPlayer() {
    final cur = player.current;
    switch (_mode) {
      case SleepMode.endOfSong:
        if (cur?.sha != _songSha) _sleep(rewind: true);
      case SleepMode.endOfAlbum:
        if (cur == null || _releaseId == null || cur.releaseId != _releaseId) {
          _sleep(rewind: true);
        }
      case SleepMode.timed || SleepMode.off:
        break;
    }
  }

  void _check() {
    switch (_mode) {
      case SleepMode.timed:
        final left = remaining ?? Duration.zero;
        if (left <= Duration.zero) {
          _sleep();
          return;
        }
        if (_fade && left <= fadeOver) _fadeTo(left);
        notifyListeners();
      case SleepMode.endOfSong || SleepMode.endOfAlbum:
        // The last song's own end, for the fade.
        if (!_fade) return;
        final last = _mode == SleepMode.endOfSong || _lastOfRelease();
        if (!last) return;
        final left = player.duration - player.position;
        if (player.duration > Duration.zero && left <= fadeOver) {
          _fadeTo(left);
        }
      case SleepMode.off:
        break;
    }
  }

  bool _lastOfRelease() {
    final q = player.queue;
    final i = player.index;
    if (i + 1 >= q.length) return true;
    return q[i + 1].releaseId != _releaseId;
  }

  void _fadeTo(Duration left) {
    final share = left.inMilliseconds / fadeOver.inMilliseconds;
    player.setVolume(restoreLevel() * share.clamp(0.0, 1.0));
    _faded = true;
  }

  void _unfade() {
    if (_faded) player.setVolume(restoreLevel());
    _faded = false;
  }

  void _sleep({bool rewind = false}) {
    // Off first: pausing tells the player's listeners, this one among them,
    // and a timer still on would answer its own pause again.
    _tick?.cancel();
    _tick = null;
    player.removeListener(_onPlayer);
    _mode = SleepMode.off;
    _endsAt = null;
    player.pause();
    // The next song had already started: put it back to its start, so
    // pressing play tomorrow plays it whole.
    if (rewind) player.seek(Duration.zero);
    // The level back only once it is quiet, or the last second is a blast.
    _unfade();
    notifyListeners();
  }

  @override
  void dispose() {
    _tick?.cancel();
    player.removeListener(_onPlayer);
    super.dispose();
  }
}

class SleepScope extends InheritedNotifier<SleepTimer> {
  const SleepScope({super.key, required SleepTimer sleep, required super.child})
    : super(notifier: sleep);

  static SleepTimer? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SleepScope>()?.notifier;
}

/// "28:41", "1:05:00".
String sleepClock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}
