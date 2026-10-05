import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';

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
///   * **Permanent loss** -- another app took the output without saying when it
///     would give it back: a video in a chat app, a status, a clip. Pause, then
///     wait. Android never says "you may have it back" after this kind of loss,
///     so the app asks whether anything else is still playing, and carries on
///     once it has been quiet for a few seconds (a gap between two clips does
///     not count). If the listener presses play or stops in the meantime, the
///     wait is over.
///   * **Transient loss** -- a call, a navigation prompt. Pause, and resume
///     afterwards *only if we were the one playing*, so a track does not
///     spring back to life minutes after the user stopped it themselves.
///   * **Becoming noisy** -- headphones pulled out. Always pause. Blasting a
///     private track through the speaker is the one failure nobody forgives.
class AudioFocus {
  AudioFocus(
    this.player, {
    Future<bool> Function()? otherAudioActive,
    this.pollEvery = const Duration(milliseconds: 250),
    this.quietFor = const Duration(milliseconds: 700),
    this.giveUpAfter = const Duration(minutes: 30),
    this.fadeIn = const Duration(milliseconds: 1400),
    DateTime Function()? now,
  }) : _otherAudioActive = otherAudioActive ?? _askPlatform,
       _now = now ?? DateTime.now;

  final TunePlayer player;

  /// Whether some other app is playing audio right now.
  final Future<bool> Function() _otherAudioActive;
  final DateTime Function() _now;

  /// How often to ask while waiting.
  final Duration pollEvery;

  /// How long the output has to stay quiet before carrying on. About the gap
  /// between two clips: short enough that music comes back as the other app
  /// ends, long enough that most swipes between clips do not start it.
  final Duration quietFor;

  /// How long the music takes to come back up. When it does start in a gap
  /// that turns out to be a pause, it is barely there before it is gone.
  final Duration fadeIn;

  /// A wait that has gone on this long is not a wait any more.
  final Duration giveUpAfter;

  static const _channel = MethodChannel('tunes/audio');

  static Future<bool> _askPlatform() async {
    try {
      return await _channel.invokeMethod<bool>('otherAudioActive') ?? false;
    } catch (_) {
      // Cannot tell, so say it is busy: staying paused is the safe reading.
      return true;
    }
  }

  Timer? _waiter;
  Timer? _fader;
  DateTime? _waitStarted;
  DateTime? _quietSince;
  bool _checking = false;

  /// Whether the player is paused and waiting for another app to finish.
  bool get waiting => _waiter != null;

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

    session.interruptionEventStream.listen(handleInterruption);
  }

  /// What to do when the system says another app wants the output, or has
  /// finished with it. Public so the three cases can be tested without a phone.
  void handleInterruption(AudioInterruptionEvent event) {
    if (event.begin) {
      switch (event.type) {
        case AudioInterruptionType.duck:
          // Ducking would need a volume the player does not expose, and a
          // half-audible lyric is worse than a clean pause.
          _pauseForFocus();
        case AudioInterruptionType.pause:
          _pauseForFocus();
        case AudioInterruptionType.unknown:
          // Permanent loss. Nobody will tell us when it is over.
          if (player.playing) {
            _pausedByFocus = false;
            player.pause();
            _restoreLevel();
            _startWaiting();
          }
      }
    } else {
      switch (event.type) {
        case AudioInterruptionType.duck:
        case AudioInterruptionType.pause:
          if (_pausedByFocus) {
            _pausedByFocus = false;
            _stopWaiting();
            _resume();
          }
        case AudioInterruptionType.unknown:
          // The interruption ended but we were not told it was ours to
          // resume from. Staying paused is the safe reading.
          _pausedByFocus = false;
      }
    }
  }

  /// Brings the music back up from silence rather than at full level.
  void _resume() {
    _fader?.cancel();
    player.setVolume(0);
    player.play();
    final start = _now();
    _fader = Timer.periodic(const Duration(milliseconds: 60), (t) {
      final f = fadeIn == Duration.zero
          ? 1.0
          : (_now().difference(start).inMilliseconds / fadeIn.inMilliseconds)
                .clamp(0.0, 1.0);
      // Smooth at both ends: a straight ramp is heard as a start and a stop.
      player.setVolume(f * f * (3 - 2 * f));
      if (f >= 1) {
        t.cancel();
        _fader = null;
      }
    });
  }

  /// Whatever interrupted a fade, the next play starts at full level.
  void _restoreLevel() {
    _fader?.cancel();
    _fader = null;
    player.setVolume(1);
  }

  void _startWaiting() {
    _stopWaiting();
    _waitStarted = _now();
    _quietSince = null;
    _waiter = Timer.periodic(pollEvery, (_) => unawaited(_check()));
  }

  void _stopWaiting() {
    _waiter?.cancel();
    _waiter = null;
    _waitStarted = null;
    _quietSince = null;
  }

  Future<void> _check() async {
    if (_waiter == null || _checking) return;
    // The listener took over: pressed play, or stopped and cleared the queue.
    if (player.playing || player.current == null) {
      _stopWaiting();
      return;
    }
    final started = _waitStarted;
    if (started != null && _now().difference(started) > giveUpAfter) {
      _stopWaiting();
      return;
    }
    _checking = true;
    final busy = await _otherAudioActive();
    _checking = false;
    if (_waiter == null) return;
    if (busy) {
      _quietSince = null;
      return;
    }
    final since = _quietSince ??= _now();
    if (_now().difference(since) >= quietFor) {
      _stopWaiting();
      _pausedByFocus = false;
      _resume();
    }
  }

  /// Claims the output while playing and releases it when stopped, so another
  /// app taking over is a thing the system can actually tell us about.
  void _onPlayerChanged() {
    final playing = player.playing;
    if (playing == _wasPlaying) return;
    _wasPlaying = playing;
    // Paused part-way through a fade-in: the next play must not start quiet.
    if (!playing && _fader != null) _restoreLevel();
    // Not awaited: the request either lands or it does not, and blocking a
    // player callback on it would stutter playback to no purpose.
    final session = _session;
    if (session != null) unawaited(session.setActive(playing));
  }

  void _pauseForFocus() {
    if (!player.playing) return;
    _pausedByFocus = true;
    player.pause();
    _restoreLevel();
    // The system promises to say when a transient loss is over, and some apps
    // never let go cleanly, so the wait is the backup: if the output goes
    // quiet and no signal came, carry on anyway.
    _startWaiting();
  }
}
