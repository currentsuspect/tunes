import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'tune_player.dart';

class TuneAudioHandler extends BaseAudioHandler with SeekHandler {
  TuneAudioHandler(
    this.player, {
    this.artUriFor,
    this.stopOnTaskRemoved,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    player.addListener(_sync);
    _sync();
  }

  /// Injectable because the throttle below is a statement about wall clock,
  /// and a test that advances playback without advancing time would be
  /// measuring a drift that never happens on a device.
  final DateTime Function() _clock;

  static const _tileChannel = MethodChannel('tunes/tile');

  final TunePlayer player;

  /// Where notification artwork is fetched from, read at the moment it is
  /// needed rather than captured at startup — same reason as
  /// [stopOnTaskRemoved]. Captured, it kept pointing at whichever server the
  /// app launched against, so changing the server left the notification
  /// loading covers from a machine no longer in reach.
  /// Builds a full, signed artwork URL for a sha.
  final String Function(String sha)? artUriFor;

  /// Full artwork URI, or null.
  ///
  /// Resolved through the same signed-capability path as the rest of the UI:
  /// Android's notification loader fetches this itself, outside the app's HTTP
  /// client, which is exactly why the grant has to travel in the URL rather
  /// than a header.
  ///
  /// Null rather than a relative or empty URI when there is no resolver or it
  /// has nothing to give. An empty artUri is not "no artwork" to the platform,
  /// it is a fetch that fails.
  Uri? _artUri(String? sha) {
    if (sha == null || sha.isEmpty) return null;
    final url = artUriFor?.call(sha);
    if (url == null || url.isEmpty) return null;
    final parsed = Uri.tryParse(url);
    return (parsed != null && parsed.hasScheme) ? parsed : null;
  }

  /// Read at the moment the app is closed rather than captured at startup, so
  /// changing the setting takes effect without a restart.
  final bool Function()? stopOnTaskRemoved;

  /// The last state actually handed to audio_service, and when.
  ///
  /// Kept so [_sync] can tell a real change from the four-times-a-second
  /// position report that prompted it.
  PlaybackState? _pushed;
  late DateTime _pushedAt = _clock();
  MediaItem? _pushedItem;

  /// How far playback may drift from what the system would work out for
  /// itself before it is worth correcting. Two seconds is longer than any
  /// rounding and shorter than any seek.
  static const _drift = Duration(seconds: 2);

  /// Whether this state says anything the last one did not.
  ///
  /// The notification carries a position, but it is not a number the system
  /// re-reads -- it is given `updatePosition` and a speed and extrapolates
  /// the rest itself. Pushing a new one every tick tells it nothing it did
  /// not already know, and costs a full notification post each time.
  bool _worthPushing(PlaybackState next) {
    final prev = _pushed;
    if (prev == null) return true;
    if (prev.playing != next.playing) return true;
    if (prev.processingState != next.processingState) return true;
    if (prev.controls.length != next.controls.length) return true;
    for (var i = 0; i < prev.controls.length; i++) {
      if (prev.controls[i].action != next.controls[i].action) return true;
    }
    // A seek, a stall, or a track change: reality has left the line the
    // system was drawing, so it needs a new fix.
    final elapsed = _clock().difference(_pushedAt);
    final expected = prev.playing
        ? prev.updatePosition + elapsed
        : prev.updatePosition;
    return (next.updatePosition - expected).abs() > _drift;
  }

  /// Tells the Quick Settings tile what to draw.
  ///
  /// Best effort by design: the tile may not be added to Quick Settings at
  /// all, and the channel is absent on every platform but Android. Neither is
  /// a failure worth surfacing, and neither may take playback with it.
  void _publishTile() {
    final current = player.current;
    unawaited(
      _tileChannel
          .invokeMethod<void>('publish', {
            'playing': player.playing,
            'title': current == null
                ? null
                : '${current.title} — ${current.artist}',
          })
          .catchError((_) {}),
    );
  }

  static bool _sameItem(MediaItem? a, MediaItem? b) {
    if (a == null || b == null) return a == b;
    return a.id == b.id &&
        a.title == b.title &&
        a.artist == b.artist &&
        a.album == b.album &&
        a.artUri == b.artUri &&
        a.duration == b.duration;
  }

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
    final next = PlaybackState(
      controls: controls,
      systemActions: systemActions,
      // Which of those controls MediaStyle draws in the collapsed
      // notification -- previous, play/pause, next. Without this the platform
      // is told to show none, and a notification with four perfectly good
      // actions on it renders as artwork and two lines of text. It is the
      // whole reason the transport never appeared.
      androidCompactActionIndices: const [0, 1, 2],
      playing: player.playing,
      processingState: player.current == null
          ? AudioProcessingState.idle
          : AudioProcessingState.ready,
      updatePosition: player.position,
      bufferedPosition: player.duration,
      speed: 1.0,
    );
    if (_worthPushing(next)) {
      _pushed = next;
      _pushedAt = _clock();
      playbackState.add(next);
      // Same moment, same throttle: the Quick Settings tile is told what is
      // playing only when the notification is, so it costs nothing extra.
      _publishTile();
    }

    final current = player.current;
    if (current == null) {
      // Clear the cache with it, so the same track played again is announced
      // rather than suppressed as unchanged.
      if (mediaItem.valueOrNull?.id != null) {
        _pushedItem = null;
        mediaItem.add(null);
      }
      return;
    }
    final item = MediaItem(
      id: current.sha,
      title: current.title,
      artist: current.artist,
      album: current.album,
      artUri: _artUri(current.artSha),
      duration: current.durationMs != null
          ? Duration(milliseconds: current.durationMs!)
          : null,
    );
    // Only when the track actually changes. Re-announcing the same item is
    // the most expensive thing here: it rebuilds the notification and sends
    // the platform off to fetch the artwork again.
    if (!_sameItem(_pushedItem, item)) {
      _pushedItem = item;
      mediaItem.add(item);
    }

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

  /// The app was swiped out of the recents list, or backed out of.
  ///
  /// Halts rather than stops: the audio goes away, which is what closing the
  /// app looks like it means, but the queue and the resume point survive so
  /// reopening lands back where the listener was. [stop] used to run here and
  /// wiped the persisted queue with it, so every close forgot the session.
  Future<void> halt() async => player.halt();

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
  /// pressing play started a *second* stream over the first. Halting here
  /// makes closing the app mean what it looks like it means, while keeping
  /// the queue so the next launch resumes instead of forgetting.
  @override
  Future<void> onTaskRemoved() async {
    if (stopOnTaskRemoved?.call() ?? true) await halt();
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
