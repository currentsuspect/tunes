import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../../domain/manifest.dart';
import 'transport_rules.dart';

enum PlaybackRepeat { off, all, one }

abstract class TunePlayer extends ChangeNotifier {
  List<ManifestTrack> get queue;
  int get index;
  bool get playing;
  Duration get position;
  Duration get duration;
  ManifestTrack? get current;
  PlaybackRepeat get repeat;
  bool get shuffle;

  void playQueue(List<ManifestTrack> tracks, int startIndex);
  void play();
  void pause();
  void toggle();
  void next();
  void previous();
  void playAt(int index);
  void seek(Duration target);
  void stop();
  void setRepeat(PlaybackRepeat mode);
  void setShuffle(bool on);

  /// Join tracks without the gap the decoder would otherwise leave.
  ///
  /// A no-op on players that cannot do it, so callers do not have to ask
  /// what backend they are talking to.
  Future<void> setGapless(bool on) async {}

  /// Loads a queue without playing it, so a relaunch can put the listener back
  /// where they were.
  ///
  /// Concrete rather than abstract: restoring is optional behaviour, and the
  /// test fakes throughout the suite have no playlist to restore into.
  void restoreQueue(
    List<ManifestTrack> tracks,
    int startIndex, {
    Duration at = Duration.zero,
  }) {}
}

class MediaKitTunePlayer extends TunePlayer {
  MediaKitTunePlayer({required this.trackUriFor, this.onQueuePlayed});

  final String Function(ManifestTrack track) trackUriFor;
  Future<void> Function()? onFirstPlay;

  /// Optional side-effect hook fired after [playQueue] applies the new
  /// queue. Receives the list of tracks as supplied. Used by the app
  /// to mirror the player's queue into the persistent [QueueStore] so
  /// it survives restarts and the queue sheet reflects what's playing.
  void Function(List<ManifestTrack> tracks)? onQueuePlayed;

  bool _firstPlayDone = false;

  Player? _player;

  /// Applied to the mpv instance on creation as well, since the player is
  /// built lazily on first play and a setting chosen before then would
  /// otherwise be forgotten.
  bool _gapless = false;
  List<ManifestTrack> _queue = const [];
  int _index = -1;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _lastNotifiedPosition = Duration.zero;

  /// When "previous" last restarted the current track, so the press after it
  /// can step back instead of restarting again. Cleared by anything that
  /// changes what is playing.
  DateTime? _restartedAt;
  PlaybackRepeat _repeat = PlaybackRepeat.off;
  bool _shuffle = false;

  @override
  List<ManifestTrack> get queue => _queue;

  @override
  int get index => _index;

  @override
  bool get playing => _playing;

  @override
  Duration get position => _position;

  @override
  Duration get duration => _duration;

  @override
  ManifestTrack? get current =>
      (_index >= 0 && _index < _queue.length) ? _queue[_index] : null;

  @override
  PlaybackRepeat get repeat => _repeat;

  @override
  bool get shuffle => _shuffle;

  @override
  /// Loads a queue without playing it.
  ///
  /// The queue was already written to the database on every play and never
  /// read back, so closing the app lost what was playing: on relaunch the
  /// player held nothing and the mini-player — which only exists when there is
  /// a current track — simply was not there. The listener's place in an album
  /// disappeared because nothing ever asked for it.
  ///
  /// Deliberately paused, and deliberately silent about it: no notification,
  /// no audio-service init, no onQueuePlayed write-back. Restoring is not
  /// playing, and an app that resumes audio on its own launch is worse than
  /// one that forgets.
  void restoreQueue(
    List<ManifestTrack> tracks,
    int startIndex, {
    Duration at = Duration.zero,
  }) {
    if (tracks.isEmpty) return;
    final safeStart = startIndex.clamp(0, tracks.length - 1).toInt();
    _queue = List<ManifestTrack>.of(tracks);
    _index = safeStart;
    _playing = false;
    // Reported straight away so the mini-player shows the right elapsed time
    // rather than 0:00 until the seek lands.
    _position = at;
    _duration = Duration.zero;
    _lastNotifiedPosition = at;
    notifyListeners();

    final created = _player == null;
    final player = _player ??= Player();
    if (created) unawaited(_applyGapless(player));
    unawaited(
      player.open(
        Playlist(
          _queue.map((t) => Media(trackUriFor(t))).toList(),
          index: _index,
        ),
        play: false,
      ),
    );
    // Seek after opening rather than before: there is nothing to seek within
    // until the media is loaded. If the player is not ready to take it the
    // seek is dropped and playback starts at zero, which is exactly the
    // behaviour this replaces -- so the failure mode is the old behaviour
    // rather than a broken one.
    if (at > Duration.zero) unawaited(player.seek(at));
    _applyPlaylistMode(player);
    _attachStreams(player);
  }

  @override
  void playQueue(List<ManifestTrack> tracks, int startIndex) {
    if (tracks.isEmpty) return;
    if (!_firstPlayDone && onFirstPlay != null) {
      _firstPlayDone = true;
      unawaited(onFirstPlay!());
    }
    // Honour shuffle by reordering input. Pin the start track first,
    // Fisher–Yates the remainder. Repeat: caller passes the canonical
    // order; we don't reorder for repeat.
    final safeStart = startIndex.clamp(0, tracks.length - 1).toInt();
    final shuffled = _shuffle && tracks.length > 1;
    final ordered = shuffled
        ? _shuffledWithStart(tracks, safeStart)
        : List<ManifestTrack>.of(tracks);
    _queue = ordered;
    // After reordering (when shuffled), the pinned start is always at
    // index 0. When not shuffled, the queue matches the input order,
    // so we use the caller's index directly.
    _index = shuffled ? 0 : safeStart;
    _playing = true;
    _position = Duration.zero;
    _duration = Duration.zero;
    _lastNotifiedPosition = Duration.zero;
    onQueuePlayed?.call(ordered);
    notifyListeners();

    final created = _player == null;
    final player = _player ??= Player();
    if (created) unawaited(_applyGapless(player));
    unawaited(
      player.open(
        Playlist(
          ordered.map((t) => Media(trackUriFor(t))).toList(),
          index: _index,
        ),
        play: true,
      ),
    );
    _applyPlaylistMode(player);
    _attachStreams(player);
  }

  List<ManifestTrack> _shuffledWithStart(
    List<ManifestTrack> input,
    int startIndex,
  ) {
    final seed = Random();
    final out = List<ManifestTrack>.of(input);
    final pinned = out.removeAt(startIndex);
    out.shuffle(seed);
    return [pinned, ...out];
  }

  Future<void> _applyPlaylistMode(Player player) async {
    final mode = switch (_repeat) {
      PlaybackRepeat.off => PlaylistMode.none,
      PlaybackRepeat.all => PlaylistMode.loop,
      PlaybackRepeat.one => PlaylistMode.single,
    };
    try {
      await player.setPlaylistMode(mode);
    } catch (_) {
      // media_kit platform implementations differ; not all support
      // setPlaylistMode at every lifecycle point. Silently no-op so
      // the rest of the engine keeps working.
    }
  }

  @override
  void toggle() {
    final player = _player;
    if (player == null) return;
    if (_playing) {
      player.pause();
    } else {
      player.play();
    }
  }

  @override
  void play() {
    final player = _player;
    if (player == null) return;
    if (_queue.isEmpty) return;
    player.play();
  }

  @override
  void pause() {
    _player?.pause();
  }

  @override
  void next() {
    final player = _player;
    if (player == null) return;
    if (_queue.isEmpty) return;
    if (_repeat == PlaybackRepeat.one) {
      // Repeat-one restarts the current track from the top.
      player.seek(Duration.zero);
      player.play();
      return;
    }
    if (_index >= _queue.length - 1) {
      if (_repeat == PlaybackRepeat.all) {
        player.jump(0);
        _index = 0;
        notifyListeners();
        return;
      }
      stop();
      return;
    }
    player.next();
  }

  @override
  void previous() {
    final player = _player;
    if (player == null) return;
    if (_queue.isEmpty) return;
    final restartedAt = _restartedAt;
    final action = previousActionFor(
      position: _position,
      index: _index,
      queueLength: _queue.length,
      repeatAll: _repeat == PlaybackRepeat.all,
      sinceRestart: restartedAt == null
          ? null
          : DateTime.now().difference(restartedAt),
    );
    // Only a restart arms the double press. Anything else -- including the
    // step back it leads to -- disarms it, so three presses do not walk the
    // queue backwards on their own.
    _restartedAt = action == PreviousAction.restart ? DateTime.now() : null;
    switch (action) {
      case PreviousAction.previousTrack:
        player.previous();
      case PreviousAction.wrapToLast:
        player.jump(_queue.length - 1);
        _index = _queue.length - 1;
        notifyListeners();
      case PreviousAction.restart:
        // Position is reported by the decoder, so it does not reset until the
        // seek lands. Set it here too, so the screen agrees with the button
        // immediately rather than a frame or two later.
        player.seek(Duration.zero);
        _position = Duration.zero;
        notifyListeners();
    }
  }

  @override
  void playAt(int index) {
    final player = _player;
    if (player == null) return;
    if (index < 0 || index >= _queue.length) return;
    player.jump(index);
    _index = index;
    notifyListeners();
  }

  @override
  void seek(Duration target) {
    // Scrubbing is a fresh decision about where to be, so the press that
    // follows is a first press again, not the second of a pair.
    _restartedAt = null;
    _player?.seek(target);
  }

  @override
  void stop() {
    final player = _player;
    if (player == null) return;
    player.stop();
    _queue = const [];
    _index = -1;
    _playing = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    onQueuePlayed?.call(const []);
    notifyListeners();
  }

  @override
  void setRepeat(PlaybackRepeat mode) {
    if (_repeat == mode) return;
    _repeat = mode;
    final player = _player;
    if (player != null) _applyPlaylistMode(player);
    notifyListeners();
  }

  @override
  Future<void> setGapless(bool on) async {
    _gapless = on;
    final player = _player;
    if (player != null) await _applyGapless(player);
  }

  /// mpv's own default is `weak`: it only joins tracks whose formats already
  /// match, which across a mixed library means almost never. `yes` forces it.
  ///
  /// Reached dynamically because `NativePlayer`, which owns `setProperty`, is
  /// not exported from media_kit's public entry point -- and importing its
  /// `src/` path would tie us to a file that is free to move. The call is
  /// guarded, so a backend without the method simply does not get gapless.
  Future<void> _applyGapless(Player player) async {
    try {
      final platform = player.platform as dynamic;
      await platform.setProperty('gapless-audio', _gapless ? 'yes' : 'weak');
    } catch (_) {
      // An mpv that will not take the property is no reason to stop playing.
      // The gap is a nicety; the audio is not.
    }
  }

  @override
  void setShuffle(bool on) {
    if (_shuffle == on) return;
    _shuffle = on;
    // If shuffle turned ON mid-queue, reorder remaining tracks from the
    // current index (current stays pinned). If turned OFF, restore the
    // canonical order — but we don't track the original input list, so
    // the cleanest UX is "takes effect on next playQueue call". A
    // dedicated queue model would solve this cleanly; for now we keep
    // the visible ordering stable and document the limitation.
    notifyListeners();
  }

  void _attachStreams(Player player) {
    if (_subscribed) return;
    _subscribed = true;
    player.stream.playing.listen((p) {
      _playing = p;
      notifyListeners();
    });
    player.stream.position.listen((p) {
      _position = p;
      if ((p - _lastNotifiedPosition).abs() >=
          const Duration(milliseconds: 250)) {
        _lastNotifiedPosition = p;
        notifyListeners();
      }
    });
    player.stream.duration.listen((d) {
      _duration = d;
      notifyListeners();
    });
    player.stream.playlist.listen((pl) {
      if (pl.index >= 0) {
        if (pl.index != _index) {
          // A different track is playing -- skipped to, or arrived at on its
          // own. Either way the restart that armed the double press belongs
          // to a track that is no longer on.
          _restartedAt = null;
        }
        _index = pl.index;
        notifyListeners();
      }
    });
  }

  bool _subscribed = false;

  @override
  void dispose() {
    _subscribed = true;
    _player?.dispose();
    super.dispose();
  }
}
