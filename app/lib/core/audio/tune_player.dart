import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../../domain/manifest.dart';

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
  List<ManifestTrack> _queue = const [];
  int _index = -1;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _lastNotifiedPosition = Duration.zero;
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

    final player = _player ??= Player();
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
    if (_index > 0) {
      player.previous();
      return;
    }
    // At first track: wrap to last when repeat-all, else restart.
    if (_repeat == PlaybackRepeat.all && _queue.length > 1) {
      player.jump(_queue.length - 1);
      _index = _queue.length - 1;
      notifyListeners();
      return;
    }
    player.seek(Duration.zero);
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
