import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../../domain/manifest.dart';
import '../platform/diag_log.dart';
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

  /// Supplies the next track when the queue runs out with repeat off.
  ///
  /// Called with the track that just ended, both when it ends on its own and
  /// when the listener skips past it. Return null to let the queue end, which
  /// keeps the player's standalone behaviour exactly as before. The app wires
  /// this to the radio engine, so the music keeps going after an album stops;
  /// a returned pick is appended to the queue, never spliced into it, so an
  /// explicit queue is never reordered -- only continued.
  Future<ManifestTrack?> Function(ManifestTrack lastPlayed)? onQueueEnded;

  /// Halts audio but keeps the queue, the place in it, and the resume state.
  ///
  /// This is what closing the app means: the sound stops, and reopening puts
  /// the listener back where they were, paused. [stop] is the destructive
  /// sibling -- it also abandons the queue, so the next launch finds nothing.
  ///
  /// Concrete with a [pause] default: a player without a decoder to shut down
  /// already halts by pausing. Backends that hold one override this to shut
  /// it down without touching the queue or the persisted resume state.
  void halt() {
    pause();
  }

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
  MediaKitTunePlayer({
    required this.trackUriFor,
    this.prepareQueue,
    this.onQueuePlayed,
  });

  final String Function(ManifestTrack track) trackUriFor;

  /// Awaited before a queue is opened, so [trackUriFor] can answer
  /// synchronously afterwards.
  ///
  /// Media bytes need a signed capability per object, and minting one is a
  /// network call -- but `player.open(Playlist(...))` needs a URL for every
  /// entry at once, and `trackUriFor` is called inside that map. Rather than
  /// make the whole call chain async, the async part happens here, once, for
  /// the whole queue.
  ///
  /// Failure is deliberately not fatal: if grants cannot be minted the queue
  /// still opens, with unsigned URLs that the edge will refuse. A visible 403
  /// beats a queue that silently refuses to start.
  Future<void> Function(List<ManifestTrack> tracks)? prepareQueue;

  Future<void> Function()? onFirstPlay;

  /// Optional side-effect hook fired after [playQueue] applies the new
  /// queue. Receives the list of tracks as supplied. Used by the app
  /// to mirror the player's queue into the persistent [QueueStore] so
  /// it survives restarts and the queue sheet reflects what's playing.
  void Function(List<ManifestTrack> tracks)? onQueuePlayed;

  bool _firstPlayDone = false;

  Player? _player;

  /// The single mpv peer for this process.
  ///
  /// Backing out finishes the activity but the OS keeps the process cached,
  /// so a relaunch runs main() again and builds a second Dart player while
  /// the first one's native peer is still alive. Minting a second mpv core
  /// beside it segfaults -- observed on device as SIGSEGV in mpv/mpv core
  /// seconds after reopen. Every wrapper therefore adopts the process peer
  /// instead of creating its own; at most one mpv core ever exists here.
  static Player? _processPeer;

  /// Returns the process peer, creating it on the first call in this process.
  ///
  /// Stopped or playing, it is reused as-is: halt() stops the decoder without
  /// destroying it, so a relaunch adopts a quiet peer and restores onto it.
  /// A relaunch while audio is still going (stopOnClose off) adopts the live
  /// one, which is also what keeps the reopened UI showing what is actually
  /// playing rather than a stale bar.
  Player _adoptPeer() {
    final existing = _processPeer;
    if (existing != null) {
      DiagLog.log('player: adopting process peer');
      _player = existing;
      _attachStreams(existing);
      return existing;
    }
    DiagLog.log('player: creating process peer');
    final created = Player();
    _processPeer = created;
    _player = created;
    unawaited(_applyGapless(created));
    _attachStreams(created);
    return created;
  }

  /// Applied to the mpv instance on creation as well, since the player is
  /// built lazily on first play and a setting chosen before then would
  /// otherwise be forgotten.
  bool _gapless = false;

  /// A restore-issued seek that has not landed yet.
  ///
  /// Opening a playlist reports position zero until the seek lands, and a
  /// seek issued before the decoder is ready is dropped outright -- either
  /// way the UI would show the restored spot for a frame and then fall back
  /// to zero (seen on device: opens on the right spot, then resets). While
  /// set, stale low reports are ignored and the seek is re-issued until the
  /// position approaches it. Cleared by anything the listener does, which
  /// always supersedes a restore.
  Duration? _pendingSeek;
  DateTime? _pendingSeekSince;
  DateTime? _lastSeekRetry;
  int _seekRetries = 0;

  void _clearPendingSeek() {
    _pendingSeek = null;
    _pendingSeekSince = null;
    _lastSeekRetry = null;
    _seekRetries = 0;
  }

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

    final player = _player ?? _adoptPeer();
    DiagLog.log('player: restore ${_queue.length} at $at index $_index');
    unawaited(_openQueue(player, _queue, _index, play: false));
    // Seek after opening rather than before: there is nothing to seek within
    // until the media is loaded. Tracked until it lands (see _pendingSeek):
    // the open reports zero meanwhile, and a seek issued before the decoder
    // is ready is dropped -- both used to read as a reset to the start.
    _clearPendingSeek();
    if (at > Duration.zero) {
      _pendingSeek = at;
      _pendingSeekSince = DateTime.now();
      unawaited(player.seek(at));
    }
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
    _clearPendingSeek();
    onQueuePlayed?.call(ordered);
    notifyListeners();

    final player = _player ?? _adoptPeer();
    unawaited(_openQueue(player, ordered, _index, play: true));
    _applyPlaylistMode(player);
    _attachStreams(player);
  }

  /// Mints whatever the queue needs, then opens it.
  ///
  /// The prepare step is awaited but its failure is swallowed: a queue that
  /// opens with unsigned URLs fails loudly at the edge, which is far easier to
  /// diagnose than a play button that does nothing.
  Future<void> _openQueue(
    Player player,
    List<ManifestTrack> tracks,
    int index, {
    required bool play,
  }) async {
    try {
      await prepareQueue?.call(tracks);
    } catch (_) {
      // Fall through and open anyway.
    }
    await player.open(
      Playlist(tracks.map((t) => Media(trackUriFor(t))).toList(), index: index),
      play: play,
    );
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
    _clearPendingSeek();
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
      // Past the end with repeat off: the queue is spent. Radio may continue
      // it (appended, never reordered); otherwise it ends as before.
      final seed = current;
      if (seed != null && onQueueEnded != null) {
        unawaited(_continueAfterEnd(seed));
        return;
      }
      stop();
      return;
    }
    player.next();
  }

  /// The decoder reached the end of the media on its own.
  ///
  /// Mid-queue this never fires -- mpv walks the playlist itself and only
  /// reports completion at the very end. Repeat modes are the decoder's own
  /// business. So by the time this runs with repeat off at the last index,
  /// the queue has genuinely run out, exactly like a manual next past the end.
  void _onNaturalEnd() {
    if (_repeat != PlaybackRepeat.off) return;
    if (_queue.isEmpty || _index < _queue.length - 1) return;
    final seed = current;
    if (seed == null || onQueueEnded == null) {
      stop();
      return;
    }
    unawaited(_continueAfterEnd(seed));
  }

  /// Guards [_continueAfterEnd]: two rapid ends (a manual next landing just as
  /// the decoder reports completion) must produce one pick, not two.
  bool _extending = false;

  /// Grows the queue by one radio pick and keeps playing.
  ///
  /// The pick lands at the end, so everything already queued -- including the
  /// album that just finished -- stays skippable-back-to. The grown queue is
  /// persisted through the same hook as any other play, so a close mid-radio
  /// restores into the radio queue rather than forgetting it.
  Future<void> _continueAfterEnd(ManifestTrack seed) async {
    if (_extending) return;
    _extending = true;
    try {
      final pick = await onQueueEnded?.call(seed);
      if (pick == null) {
        stop();
        return;
      }
      final grown = [..._queue, pick];
      _queue = grown;
      _index = grown.length - 1;
      _playing = true;
      _position = Duration.zero;
      _duration = Duration.zero;
      _lastNotifiedPosition = Duration.zero;
      _clearPendingSeek();
      onQueuePlayed?.call(grown);
      notifyListeners();
      // The peer always exists here: anything that ends had a decoder, and
      // adoption guarantees one per process. No null branch, no second peer.
      await _openQueue(_player ?? _adoptPeer(), grown, _index, play: true);
    } finally {
      _extending = false;
    }
  }

  @override
  void previous() {
    final player = _player;
    if (player == null) return;
    if (_queue.isEmpty) return;
    _clearPendingSeek();
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
    _clearPendingSeek();
    player.jump(index);
    _index = index;
    notifyListeners();
  }

  @override
  void seek(Duration target) {
    // Scrubbing is a fresh decision about where to be, so the press that
    // follows is a first press again, not the second of a pair.
    _restartedAt = null;
    _clearPendingSeek();
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
    _clearPendingSeek();
    onQueuePlayed?.call(const []);
    notifyListeners();
  }

  /// Stops the decoder and goes quiet, but the queue, the index, and the
  /// persisted resume state all survive.
  ///
  /// [stop] above used to serve both "I am done listening" and "the app is
  /// going away", and the second meaning kept destroying the first launch's
  /// restore: it cleared the in-memory queue and, through [onQueuePlayed],
  /// wiped the stored one too, so closing the app forgot what was playing and
  /// reopening showed a bar for a track with no queue behind it. Closing now
  /// halts; only an explicit stop abandons.
  @override
  void halt() {
    final player = _player;
    if (player == null) {
      _playing = false;
      notifyListeners();
      return;
    }
    DiagLog.log('player: halt, keeping ${_queue.length} queued');
    player.stop();
    _playing = false;
    _clearPendingSeek();
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
  /// `prefetch-playlist` rides on the same toggle: gapless joining still
  /// stalls when the next entry's bytes only start arriving at the boundary,
  /// and every track here is a fresh HTTPS stream. Preloading the next entry
  /// while the current one plays is what actually removes the silence; the
  /// join flag alone only removes the decoder gap.
  ///
  /// Reached dynamically because `NativePlayer`, which owns `setProperty`, is
  /// not exported from media_kit's public entry point -- and importing its
  /// `src/` path would tie us to a file that is free to move. The call is
  /// guarded, so a backend without the method simply does not get gapless.
  Future<void> _applyGapless(Player player) async {
    try {
      final platform = player.platform as dynamic;
      await platform.setProperty('gapless-audio', _gapless ? 'yes' : 'weak');
      await platform.setProperty('prefetch-playlist', _gapless ? 'yes' : 'no');
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

  /// Decides whether a position report predates a restore seek that is still
  /// in flight. Returns true when the report was swallowed.
  ///
  /// A report counts as landed once it reaches the seek's neighbourhood; the
  /// whole thing expires after ten seconds or five retries, at which point
  /// the live reports win no matter what -- a guard that never clears would
  /// freeze the playhead worse than the reset it prevents.
  bool _swallowStaleRestoreReport(Player player, Duration p) {
    final target = _pendingSeek;
    if (target == null) return false;
    final since = _pendingSeekSince ?? DateTime.now();
    if (p >= target - const Duration(seconds: 2) ||
        DateTime.now().difference(since) > const Duration(seconds: 10) ||
        _seekRetries >= 5) {
      _clearPendingSeek();
      return false;
    }
    // Still waiting: hold the restored spot on screen and nudge the decoder
    // again, at most once a second -- the reports arrive four times that, and
    // one seek per report would be a hot loop against a decoder that is still
    // loading.
    final last = _lastSeekRetry;
    if (last == null ||
        DateTime.now().difference(last) > const Duration(seconds: 1)) {
      _lastSeekRetry = DateTime.now();
      _seekRetries += 1;
      unawaited(player.seek(target));
    }
    return true;
  }

  void _attachStreams(Player player) {
    if (_subscribed) return;
    _subscribed = true;
    player.stream.playing.listen((p) {
      _playing = p;
      notifyListeners();
    });
    player.stream.position.listen((p) {
      if (_swallowStaleRestoreReport(player, p)) return;
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
    // The decoder finished the media by itself. With repeat off at the last
    // index the queue has run out; radio may continue it, otherwise it stops.
    player.stream.completed.listen((done) {
      if (done) _onNaturalEnd();
    });
  }

  bool _subscribed = false;

  @override
  void dispose() {
    // The native peer is process-lifetime (see _processPeer): a wrapper from
    // a previous activity generation may still be driving it through the
    // audio service, so destroying it here would pull the decoder out from
    // under live playback. This only detaches local interest; the OS reclaims
    // the peer with the process.
    _subscribed = true;
    _player = null;
    super.dispose();
  }
}
