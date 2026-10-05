import 'dart:async';

/// Puts a restored song back where it was once it actually starts.
///
/// The app remembers where a song was and, on relaunch, opens it paused. A seek
/// issued then is dropped, particularly for a streamed song that has not
/// loaded, so pressing play started the song from the beginning while the
/// screen still said 0:41. The playhead was then saved as 0:00 and the place
/// was gone for good.
///
/// This holds the intent until it lands: from the moment play is pressed it
/// asks the engine where it is, and seeks again each beat once the song has
/// loaded, until the engine is back at the spot (or too long has passed).
class RestoreSeek {
  RestoreSeek({
    required this.target,
    required this.enginePosition,
    required this.engineDuration,
    required this.seek,
    this.onDone,
    this.every = const Duration(milliseconds: 300),
    this.giveUpAfter = const Duration(seconds: 20),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration target;

  /// Where the engine really is, not where the screen says.
  final Duration Function() enginePosition;
  final Duration Function() engineDuration;
  final void Function(Duration to) seek;
  final void Function()? onDone;
  final Duration every;
  final Duration giveUpAfter;
  final DateTime Function() _now;

  Timer? _timer;
  DateTime? _started;

  bool get active => _timer != null;

  void start() {
    cancel();
    _started = _now();
    _timer = Timer.periodic(every, (_) => _tick());
    _tick();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void _tick() {
    if (_timer == null) return;
    // Back at the spot, give or take a moment of playing on.
    if (enginePosition() >= target - const Duration(seconds: 2)) {
      cancel();
      onDone?.call();
      return;
    }
    final started = _started;
    if (started != null && _now().difference(started) > giveUpAfter) {
      cancel();
      return;
    }
    // Only once the song has loaded: before that the seek is thrown away.
    if (engineDuration() > Duration.zero) seek(target);
  }
}
