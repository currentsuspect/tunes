import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import 'tune_player.dart';

class TuneAudioHandler extends BaseAudioHandler with SeekHandler {
  TuneAudioHandler(this.player, {this.artBase = '', this.stopOnTaskRemoved}) {
    player.addListener(_sync);
    _sync();
  }

  final TunePlayer player;
  final String artBase;

  /// Read at the moment the app is closed rather than captured at startup, so
  /// changing the setting takes effect without a restart.
  final bool Function()? stopOnTaskRemoved;

  void _sync() {
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
        artUri: current.artSha != null
            ? Uri.parse('$artBase/art/${current.artSha}')
            : null,
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

  /// The app was swiped out of the recents list.
  ///
  /// Without this the foreground service kept the process alive and the audio
  /// simply carried on: no mini player to stop it, and reopening the app and
  /// pressing play started a *second* stream over the first. Stopping here
  /// makes closing the app mean what it looks like it means.
  @override
  Future<void> onTaskRemoved() async {
    if (stopOnTaskRemoved?.call() ?? true) await stop();
    await super.onTaskRemoved();
  }

  /// The user dismissed the notification, which is the other way of saying
  /// "I am done listening".
  @override
  Future<void> onNotificationDeleted() async {
    await stop();
    await super.onNotificationDeleted();
  }
}
