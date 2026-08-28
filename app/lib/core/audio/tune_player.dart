import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../../domain/manifest.dart';

abstract class TunePlayer extends ChangeNotifier {
  List<ManifestTrack> get queue;
  int get index;
  bool get playing;
  Duration get position;
  Duration get duration;
  ManifestTrack? get current;

  void playQueue(List<ManifestTrack> tracks, int startIndex);
  void play();
  void pause();
  void toggle();
  void next();
  void previous();
  void playAt(int index);
  void seek(Duration target);
  void stop();
}

class MediaKitTunePlayer extends TunePlayer {
  MediaKitTunePlayer({required this.trackUriFor});

  final String Function(ManifestTrack track) trackUriFor;
  Future<void> Function()? onFirstPlay;

  bool _firstPlayDone = false;

  Player? _player;
  List<ManifestTrack> _queue = const [];
  int _index = -1;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _lastNotifiedPosition = Duration.zero;

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
  void playQueue(List<ManifestTrack> tracks, int startIndex) {
    if (tracks.isEmpty) return;
    if (!_firstPlayDone && onFirstPlay != null) {
      _firstPlayDone = true;
      unawaited(onFirstPlay!());
    }
    _queue = List.of(tracks);
    _index = startIndex.clamp(0, tracks.length - 1);
    _playing = true;
    _position = Duration.zero;
    _duration = Duration.zero;
    _lastNotifiedPosition = Duration.zero;
    notifyListeners();

    final player = _player ??= Player();
    unawaited(
      player.open(
        Playlist(
          tracks.map((t) => Media(trackUriFor(t))).toList(),
          index: _index,
        ),
        play: true,
      ),
    );
    _attachStreams(player);
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
    if (_index >= _queue.length - 1) {
      stop();
      return;
    }
    player.next();
  }

  @override
  void previous() {
    final player = _player;
    if (player == null) return;
    if (_index <= 0) {
      player.seek(Duration.zero);
      return;
    }
    player.previous();
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
