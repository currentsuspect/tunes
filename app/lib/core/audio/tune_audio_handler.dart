import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import 'tune_player.dart';

class TuneAudioHandler extends BaseAudioHandler with SeekHandler {
  TuneAudioHandler(this.player) {
    player.addListener(_sync);
    _sync();
  }

  final TunePlayer player;

  void _sync() {
    debugPrint(
      'handler sync: playing=${player.playing} current=${player.current?.title}',
    );
    final controls = [
      MediaControl.skipToPrevious,
      if (player.playing) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
      MediaControl.stop,
    ];
    final systemActions = const {
      MediaAction.seek,
      MediaAction.seekForward,
      MediaAction.seekBackward,
    };
    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: systemActions,
        playing: player.playing,
        processingState: player.current == null
            ? AudioProcessingState.idle
            : AudioProcessingState.ready,
        updatePosition: player.position,
        bufferedPosition: player.duration,
        speed: 1.0,
      ),
    );

    final current = player.current;
    if (current == null) {
      if (mediaItem.valueOrNull?.id != null) mediaItem.add(null);
      return;
    }
    mediaItem.add(
      MediaItem(
        id: current.sha,
        title: current.title,
        artist: current.artist,
        album: current.album,
        duration: current.durationMs != null
            ? Duration(milliseconds: current.durationMs!)
            : null,
      ),
    );

    final queueItems = player.queue
        .map(
          (t) => MediaItem(
            id: t.sha,
            title: t.title,
            artist: t.artist,
            album: t.album,
            duration: t.durationMs != null
                ? Duration(milliseconds: t.durationMs!)
                : null,
          ),
        )
        .toList();
    if (!listEquals(queueItems, queue.valueOrNull)) {
      queue.add(queueItems);
    }
  }

  @override
  Future<void> play() async => player.play();

  @override
  Future<void> pause() async => player.pause();

  @override
  Future<void> stop() async => player.stop();

  @override
  Future<void> skipToNext() async => player.next();

  @override
  Future<void> skipToPrevious() async => player.previous();

  @override
  Future<void> seek(Duration position) async => player.seek(position);

  @override
  Future<void> seekForward(bool begin) async {
    if (!begin) player.seek(player.position + const Duration(seconds: 10));
  }

  @override
  Future<void> seekBackward(bool begin) async {
    if (!begin) player.seek(player.position - const Duration(seconds: 10));
  }
}
