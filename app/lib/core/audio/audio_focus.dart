import 'dart:async';

import 'package:audio_session/audio_session.dart';

import 'tune_player.dart';

/// Makes playback a good citizen of the device's audio.
///
/// Nothing here was happening before: starting a track in another app left
/// both playing over each other, and unplugging headphones carried on out
/// loud. Android will not do any of this for you -- an app has to ask for
/// focus and then honour losing it.
///
/// The three cases, which are genuinely different:
///
///   * **Permanent loss** -- another app took over for good. Pause, and do not
///     come back on our own; the other app owns the output now.
///   * **Transient loss** -- a call, a navigation prompt. Pause, and resume
///     afterwards *only if we were the one playing*, so a track does not
///     spring back to life minutes after the user stopped it themselves.
///   * **Becoming noisy** -- headphones pulled out. Always pause. Blasting a
///     private track through the speaker is the one failure nobody forgives.
class AudioFocus {
  AudioFocus(this.player);

  final TunePlayer player;

  /// True when we paused because of focus rather than because the user did.
  /// Only such a pause earns an automatic resume.
  bool _pausedByFocus = false;

  /// Mirrors the player so focus is requested on the transition into playing
  /// rather than on every notification.
  bool _wasPlaying = false;

  AudioSession? _session;

  Future<void> attach() async {
    final session = await AudioSession.instance;
    _session = session;
    await session.configure(const AudioSessionConfiguration.music());

    // Configuring only describes the audio; it does not claim the output.
    // Focus is requested by activating the session, and without this the app
    // played without ever appearing in the system's focus stack -- so nothing
    // ever told it to stop, and nothing it did told anyone else to.
    player.addListener(_onPlayerChanged);
    _onPlayerChanged();

    session.becomingNoisyEventStream.listen((_) {
      if (player.playing) {
        _pausedByFocus = false;
        player.pause();
      }
    });

    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.duck:
            // Ducking would need a volume the player does not expose, and a
            // half-audible lyric is worse than a clean pause.
            _pauseForFocus();
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            _pauseForFocus();
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
          case AudioInterruptionType.pause:
            if (_pausedByFocus) {
              _pausedByFocus = false;
              player.play();
            }
          case AudioInterruptionType.unknown:
            // The interruption ended but we were not told it was ours to
            // resume from. Staying paused is the safe reading.
            _pausedByFocus = false;
        }
      }
    });
  }

  /// Claims the output while playing and releases it when stopped, so another
  /// app taking over is a thing the system can actually tell us about.
  void _onPlayerChanged() {
    final playing = player.playing;
    if (playing == _wasPlaying) return;
    _wasPlaying = playing;
    // Not awaited: the request either lands or it does not, and blocking a
    // player callback on it would stutter playback to no purpose.
    final session = _session;
    if (session != null) unawaited(session.setActive(playing));
  }

  void _pauseForFocus() {
    if (!player.playing) return;
    _pausedByFocus = true;
    player.pause();
  }
}
