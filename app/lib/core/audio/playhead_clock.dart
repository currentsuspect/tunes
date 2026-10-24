import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'playhead.dart';
import 'tune_player.dart';

/// A smooth playhead: the one clock everything that shows progress reads.
///
/// The player notifies at most four times a second. That is too coarse to
/// sweep a highlight across a word, and it is why a progress bar reading
/// `player.position` steps rather than moves. This takes each report as a fix
/// and projects between them on a ticker, so only the widgets that listen
/// here repaint at frame rate -- the list behind them does not.
///
/// Built for the lyric view and now shared by the mini-player and the
/// scrubber, so every surface showing where playback is derives it from the
/// same place rather than each sampling the player on its own schedule.
///
/// The ticker only runs while something is playing, so a paused sheet costs
/// nothing.
class PlayheadClock extends ValueNotifier<Duration> {
  PlayheadClock({required this.player, required TickerProvider vsync})
    : super(player.position) {
    _ticker = vsync.createTicker(_onTick);
    player.addListener(_onPlayerChanged);
    _onPlayerChanged();
  }

  final TunePlayer player;
  late final Ticker _ticker;
  Duration _reported = Duration.zero;
  DateTime _reportedAt = DateTime.now();

  /// Turns the frame-rate ticking off for widget tests.
  ///
  /// `pumpAndSettle` pumps until no frame is scheduled, and a clock that
  /// projects the playhead every frame always schedules the next one -- so a
  /// test that starts playback could never settle. Off, the clock still
  /// reports every position the player gives it; it just stops interpolating
  /// between them, which is exactly the part a test cannot observe anyway.
  ///
  /// A seam rather than a guess: nothing infers "am I under test" at runtime.
  static bool ticking = true;

  void _onPlayerChanged() {
    _reported = player.position;
    _reportedAt = DateTime.now();
    if (!ticking) {
      value = _reported;
      return;
    }
    if (player.playing && !_ticker.isActive) {
      _ticker.start();
    } else if (!player.playing && _ticker.isActive) {
      _ticker.stop();
    }
    if (!player.playing) value = _reported;
  }

  void _onTick(Duration _) {
    value = projectPosition(
      reported: _reported,
      reportedAt: _reportedAt,
      now: DateTime.now(),
      playing: player.playing,
      duration: player.duration,
      rate: player.rate,
    );
  }

  @override
  void dispose() {
    player.removeListener(_onPlayerChanged);
    _ticker.dispose();
    super.dispose();
  }
}
