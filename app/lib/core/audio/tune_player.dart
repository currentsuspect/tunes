import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'offline_anchor.dart';
import 'queue_order.dart';
import 'restore_seek.dart';
import 'source_plan.dart';
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

  /// The name of the device that is playing, when what this one shows is
  /// another device's music and this one is only a remote for it. Null when the
  /// sound is this device's own, which is every player but the connected one.
  String? get remoteDeviceLabel => null;

  /// True when this is a remote for another device that was told something and
  /// has not answered, so it may not be running.
  bool get remoteStalled => false;

  /// Take the music over from the device that is playing it: carry on here, at
  /// the same place. A no-op when nothing is playing elsewhere.
  Future<void> playHere() async {}

  /// Plays [tracks] in a random order, starting from a random one, with shuffle
  /// mode on so the player shows it and a later toggle behaves.
  ///
  /// What the Shuffle buttons call. They used to shuffle the list themselves
  /// and play it from the top, which left the shuffle switch off and the first
  /// song a coin flip nobody could repeat.
  void shufflePlay(List<ManifestTrack> tracks) {
    if (tracks.isEmpty) return;
    setShuffle(true);
    playQueue(tracks, Random().nextInt(tracks.length));
  }

  void play();
  void pause();

  /// The player's own level, 0 to 1, apart from the phone's volume. Used to
  /// ease music back in after another app has had the output. A no-op where a
  /// player has no such control.
  void setVolume(double level) {}

  /// Playback speed, 1 normal. The lyric maker slows a song down so a word
  /// can be caught; nothing else changes it. A no-op where a player cannot.
  double get rate => 1;
  void setRate(double rate) {}
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

  /// Fired after [restoreQueue] loads a queue without playing it.
  ///
  /// The app binds the audio service here: a relaunch that restores paused
  /// audio is exactly when the notification must start following the new
  /// generation rather than the halted one. Concrete nullable like the other
  /// hooks, so fakes ignore it.
  Future<void> Function()? onRestored;

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

  /// An mpv audio filter chain (`af`), for the headphone EQ; empty is none.
  /// A no-op on players that cannot filter.
  Future<void> setAudioFilter(String af, {double preampDb = 0}) async {}

  /// Called when mpv refused the EQ chain and the player dropped it to keep
  /// playing; the app turns the EQ setting off.
  void Function()? onAudioFilterFailed;

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

  /// Swaps in newer copies of tracks already in the queue, matched by sha,
  /// without touching what is playing.
  ///
  /// The queue holds the track as it was when it was queued, so a lyric saved
  /// afterwards, or one the daemon sent since, never reached the screens that
  /// read `current` until the app was closed and reopened. Only the metadata
  /// changes: order, position and the decoder are left exactly as they are.
  /// A no-op where a player holds no queue of its own.
  void refreshTracks(Map<String, ManifestTrack> fresh) {}

  /// Points queued songs at their copy on the phone where one has landed since
  /// the queue opened. The song playing is only reopened when [touchCurrent]:
  /// offline its stream is about to fail, online it is left to finish. A no-op
  /// where a player holds no queue of its own.
  void refreshSources({bool touchCurrent = false}) {}

  /// The connection is back. A song held while offline picks up where it
  /// stopped. A no-op where a player holds no queue of its own.
  void networkReturned() {}
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

  /// Whether the app has decided it is offline. Signing a queue is a network
  /// round trip that cannot succeed then, and waiting it out held every tap
  /// silent for the length of a timeout.
  bool Function()? isOffline;

  /// Asks, now, whether the server can be reached. Called when a stream fails:
  /// the heartbeat needs three missed checks ten seconds apart to say offline,
  /// and in that gap every failure read as a bad file, so the queue was
  /// skipped through song by song until it ran out.
  Future<bool> Function()? checkOnline;

  /// The song last heard playing, how far in, and when. mpv moves on to the
  /// next entry by itself when one fails to load, so by the time an error
  /// arrives the index can already be a song that never made a sound.
  int _heardIndex = -1;
  String? _heardSha;
  Duration _heardAt = Duration.zero;
  final OfflineAnchor _anchor = OfflineAnchor();
  DateTime? _heardWhen;

  /// Offline with nothing on the phone to play: paused on the song that was
  /// playing, at its spot, until the connection is back or play is pressed.
  /// The decoder's own reports are ignored meanwhile, since it keeps failing
  /// and moving on underneath.
  bool _heldForNetwork = false;

  /// Songs given up on in a row, online. Reset once a song plays. A run of
  /// them means something other than the songs is wrong, and skipping on
  /// would only fail through the whole queue.
  int _skipsInRow = 0;

  /// The address each decoder entry was opened with, in decoder order. Kept so
  /// an entry whose song has reached the phone since can be found and moved
  /// onto the copy (see [planSources]).
  List<String> _opened = const [];

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

  /// The wrapper currently allowed to publish: at most one per process.
  ///
  /// A relaunch builds a second Dart wrapper around the same mpv peer. Both
  /// attach to its streams, and both feed listeners -- the audio service
  /// among them. The superseded generation must go quiet, or the
  /// notification follows a wrapper whose queue froze at close time while
  /// the mini-player follows the live one.
  static MediaKitTunePlayer? _liveWrapper;

  /// Stream subscriptions onto the peer. Kept so supersede/dispose can
  /// cancel them: a detached wrapper must not hear the peer anymore.
  final List<StreamSubscription> _peerSubs = [];

  /// Claims the live generation for this wrapper, detaching whoever held
  /// it. Called whenever this wrapper is about to drive: construction is
  /// too eager (a restored-then-never-played wrapper must not silence the
  /// one still playing), and the first drive is exactly when publication
  /// must move over.
  void _claimLive() {
    final live = _liveWrapper;
    if (identical(live, this)) return;
    live?.detach();
    _liveWrapper = this;
  }

  /// Yields publication to the next generation. Cancels every peer
  /// subscription, so this wrapper's listeners (the old audio handler
  /// included) never publish again. Audio is untouched: detaching is about
  /// who may speak, never about the decoder.
  void detach() {
    for (final s in _peerSubs) {
      s.cancel();
    }
    _peerSubs.clear();
    _subscribed = true;
  }

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
    unawaited(_applyFilter(created));
    if (_preampFactor != 1) setVolume(_volumeLevel);
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

  /// Where the song was when the app last closed, until it has been put back.
  /// Outlives the on-screen guard above (which gives up after ten seconds):
  /// play is what finally makes the engine able to seek, and it can be pressed
  /// long after the restore.
  Duration? _restoreAt;
  RestoreSeek? _restoreSeek;

  /// [keepRestore] is for the guard expiring on its own. Anything the listener
  /// does (a new queue, a seek, next) is a decision about where to be, so the
  /// remembered spot is dropped with it.
  void _clearPendingSeek({bool keepRestore = false}) {
    _pendingSeek = null;
    _pendingSeekSince = null;
    _lastSeekRetry = null;
    _seekRetries = 0;
    if (!keepRestore) {
      _restoreAt = null;
      _restoreSeek?.cancel();
      _restoreSeek = null;
    }
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

  /// The queue in the order it was supplied: what "in order" means.
  ///
  /// Kept beside the order that is playing so shuffle can be turned off, or on,
  /// at any moment and still know where the list was.
  List<ManifestTrack> _canonical = const [];

  @override
  List<ManifestTrack> get queue => _queue;

  @override
  void refreshTracks(Map<String, ManifestTrack> fresh) {
    if (fresh.isEmpty) return;
    var changed = false;
    ManifestTrack pick(ManifestTrack t) {
      final n = fresh[t.sha];
      if (n == null) return t;
      // Rebuilt from the database every time, so identity says nothing; only a
      // difference a screen could show is worth waking them for.
      if (n.lyrics == t.lyrics &&
          n.lyricsSource == t.lyricsSource &&
          n.title == t.title &&
          n.artist == t.artist &&
          n.album == t.album) {
        return t;
      }
      changed = true;
      return n;
    }

    _queue = [for (final t in _queue) pick(t)];
    _canonical = [for (final t in _canonical) pick(t)];
    if (changed) notifyListeners();
  }

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
    _canonical = List.of(_queue);
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
      _restoreAt = at;
      unawaited(player.seek(at));
    }
    _applyPlaylistMode(player);
    _attachStreams(player);
    if (onRestored != null) unawaited(onRestored!());
  }

  @override
  void playQueue(List<ManifestTrack> tracks, int startIndex) {
    _heldForNetwork = false;
    _heardWhen = null;
    _anchor.clear();
    if (tracks.isEmpty) return;
    _claimLive();
    if (!_firstPlayDone && onFirstPlay != null) {
      _firstPlayDone = true;
      unawaited(onFirstPlay!());
    }
    // Honour shuffle by reordering input. Pin the start track first,
    // Fisher–Yates the remainder. Repeat: caller passes the canonical
    // order; we don't reorder for repeat.
    final safeStart = startIndex.clamp(0, tracks.length - 1).toInt();
    _canonical = List.of(tracks);
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
  ///
  /// It is only awaited when the first song has to stream. One that is on the
  /// phone starts at once and the rest are signed behind it; offline nothing
  /// is signed at all, since the round trip can only time out.
  Future<void> _openQueue(
    Player player,
    List<ManifestTrack> tracks,
    int index, {
    required bool play,
  }) async {
    final offline = isOffline?.call() ?? false;
    final startsLocal =
        index >= 0 &&
        index < tracks.length &&
        isLocalUri(trackUriFor(tracks[index]));
    final prepare = prepareQueue;
    if (prepare != null && !offline) {
      if (startsLocal) {
        unawaited(
          prepare(tracks).then((_) => refreshSources(), onError: (_) {}),
        );
      } else {
        try {
          await prepare(tracks);
        } catch (_) {
          // Fall through and open anyway.
        }
      }
    }
    final uris = [for (final t in tracks) trackUriFor(t)];
    _opened = uris;
    await player.open(
      Playlist([for (final u in uris) Media(u)], index: index),
      play: play,
    );
  }

  @override
  void refreshSources({bool touchCurrent = false}) {
    final player = _player;
    if (player == null || _queue.isEmpty) return;
    final plan = planSources(
      opened: _opened,
      resolved: [for (final t in _queue) trackUriFor(t)],
      index: _index,
      touchCurrent: touchCurrent,
    );
    if (plan.reopenCurrent) {
      DiagLog.log('player: reopening ${_queue[_index].sha} from the phone');
      // Reopening rebuilds every entry, so the tail is covered too.
      unawaited(_reopenHere(player, _position));
      return;
    }
    if (plan.rebuildTail) _rebuildTail(_queue);
  }

  /// Opens the queue again where it is, picking up each song's best address,
  /// and returns to [at] in the song on. Used when that song's stream is gone
  /// but its bytes are on the phone.
  ///
  /// [play] defaults to whatever the decoder last said; after a failure that
  /// can read as paused, so the retry paths pass true.
  Future<void> _reopenHere(Player player, Duration at, {bool? play}) async {
    final resume = at > const Duration(seconds: 2);
    if (resume) {
      _pendingSeek = at;
      _pendingSeekSince = DateTime.now();
      _lastSeekRetry = null;
      _seekRetries = 0;
    }
    await _openQueue(player, _queue, _index, play: play ?? _playing);
    if (resume) unawaited(player.seek(at));
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
    _claimLive();
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
    _claimLive();
    if (_heldForNetwork) {
      // Tried again by hand: reopen where it stopped. Still offline, it
      // fails and holds again.
      _heldForNetwork = false;
      unawaited(_reopenHere(player, _position, play: true));
      return;
    }
    player.play();
    final target = _restoreAt;
    if (target != null) {
      _restoreSeek?.cancel();
      _restoreSeek = RestoreSeek(
        target: target,
        enginePosition: () => player.state.position,
        engineDuration: () => player.state.duration,
        seek: (to) => unawaited(player.seek(to)),
        onDone: () => _restoreAt = null,
      )..start();
    }
  }

  @override
  void pause() {
    if (_queue.isEmpty) return;
    _claimLive();
    _player?.pause();
  }

  double _rate = 1;

  @override
  double get rate => _rate;

  @override
  void setRate(double rate) {
    _rate = rate.clamp(0.25, 2.0);
    // mpv keeps the pitch (scaletempo) by default, so slowed words still
    // sound like themselves.
    unawaited(_player?.setRate(_rate) ?? Future.value());
    notifyListeners();
  }

  @override
  void setVolume(double level) {
    _volumeLevel = level.clamp(0.0, 1.0);
    // mpv takes 0 to 100; the EQ's preamp rides on top (see _preampFactor).
    unawaited(
      _player?.setVolume(_volumeLevel * _preampFactor * 100) ?? Future.value(),
    );
  }

  @override
  void next() {
    _heldForNetwork = false;
    _heardWhen = null;
    _anchor.clear();
    final player = _player;
    if (player == null) return;
    if (_queue.isEmpty) return;
    _claimLive();
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
      _canonical = [..._canonical, pick];
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
    _heldForNetwork = false;
    _heardWhen = null;
    _anchor.clear();
    final player = _player;
    if (player == null) return;
    if (_queue.isEmpty) return;
    _claimLive();
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
    _heldForNetwork = false;
    _heardWhen = null;
    _anchor.clear();
    final player = _player;
    if (player == null) return;
    if (index < 0 || index >= _queue.length) return;
    _claimLive();
    _clearPendingSeek();
    player.jump(index);
    _index = index;
    notifyListeners();
  }

  @override
  void seek(Duration target) {
    _claimLive();
    // Scrubbing is a fresh decision about where to be, so the press that
    // follows is a first press again, not the second of a pair.
    _restartedAt = null;
    _clearPendingSeek();
    _heardWhen = null;
    _anchor.clear();
    if (_heldForNetwork) {
      // Nothing is loaded to seek in: move the spot it will resume from.
      _position = target;
      notifyListeners();
      return;
    }
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
  String _af = '';

  /// The EQ's preamp where the chain cannot carry it (Android), as a factor on
  /// mpv's volume. mpv applies volume on a cubic curve, so -4.8 dB is
  /// (10^(-4.8/20))^(1/3) = 0.83 of the slider.
  double _preampFactor = 1;

  /// The last level asked for (focus fades and the desktop slider), so a new
  /// preamp can be applied on top of it.
  double _volumeLevel = 1;

  @override
  Future<void> setAudioFilter(String af, {double preampDb = 0}) async {
    _af = af;
    _preampFactor = pow(10, preampDb / 60).toDouble();
    final player = _player;
    if (player == null) return;
    await _applyFilter(player);
    setVolume(_volumeLevel);
  }

  /// The headphone EQ (domain/eq.dart), set the same guarded way as
  /// gapless. A chain mpv refuses is dropped rather than left half-applied,
  /// so a bad profile never silences playback.
  Future<void> _applyFilter(Player player) async {
    try {
      final platform = player.platform as dynamic;
      await platform.setProperty('af', _af);
    } catch (_) {
      _dropFilter(player);
    }
  }

  /// mpv refused the chain (on 17 Oct, Android's cut-down ffmpeg had no
  /// `lowshelf`, and every song failed to open and was skipped). Play on
  /// without it, from where we were, and say so.
  void _dropFilter(Player player) {
    if (_af.isEmpty) return;
    DiagLog.log('player: EQ chain refused, playing without it');
    _af = '';
    _preampFactor = 1;
    try {
      unawaited((player.platform as dynamic).setProperty('af', '') as Future);
    } catch (_) {}
    setVolume(_volumeLevel);
    onAudioFilterFailed?.call();
  }

  /// mpv's words when an audio filter chain cannot be built.
  static bool _isFilterError(String message) => RegExp(
    r'filter|lavfi|audio chain',
    caseSensitive: false,
  ).hasMatch(message);

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
    // Applied to the queue now, not at the next playQueue. Turning shuffle on
    // puts what is still to come in a random order; turning it off continues
    // from the song on in the order the list was given. What was played and
    // what is playing never move. This used to wait for the next playQueue, so
    // the switch changed nothing about what played next.
    _reorderFuture(
      on
          ? shuffleAfter(_queue, _index, Random())
          : inOrderAfter(_queue, _canonical, _index),
    );
    notifyListeners();
  }

  /// Plays [tracks] shuffled without first reordering a queue that is about to
  /// be replaced.
  @override
  void shufflePlay(List<ManifestTrack> tracks) {
    if (tracks.isEmpty) return;
    _shuffle = true;
    playQueue(tracks, Random().nextInt(tracks.length));
  }

  /// Serialises reorders, so two quick toggles apply in the order they were
  /// made and never interleave their edits to the decoder's playlist.
  Future<void> _reorderFlight = Future<void>.value();

  /// Makes the queue after the current song [next], in the decoder as well as
  /// here. The song on is never touched, so there is no gap and no restart.
  void _reorderFuture(List<ManifestTrack> next) {
    if (_queue.isEmpty) return;
    if (sameFuture(_queue, next, _index)) {
      _queue = next;
      return;
    }
    _queue = next;
    onQueuePlayed?.call(next);
    _rebuildTail(next);
  }

  /// Replaces every decoder entry after the song on with [next]'s, each at its
  /// best address now. The song on is never touched.
  void _rebuildTail(List<ManifestTrack> next) {
    final player = _player;
    if (player == null) return;
    _reorderFlight = _reorderFlight.then((_) async {
      // Read when the edit runs, not when it was asked for: an earlier edit in
      // the flight may have moved on.
      final keep = _index + 1;
      final before = _opened.length;
      if (keep > next.length || keep > before) return;
      try {
        final tail = next.sublist(keep);
        if (!(isOffline?.call() ?? false)) {
          await prepareQueue?.call(tail);
        }
        final uris = [for (final t in tail) trackUriFor(t)];
        // From the back, so no removal shifts the index of one still to go.
        for (var i = before - 1; i >= keep; i--) {
          await player.remove(i);
        }
        for (final u in uris) {
          await player.add(Media(u));
        }
        _opened = [..._opened.take(keep), ...uris];
      } catch (_) {
        // The decoder refusing an edit is no reason to stop the music: the
        // current song keeps playing and the next play rebuilds the queue.
      }
    });
  }

  /// Decides whether a position report predates a restore seek that is still
  /// in flight. Returns true when the report was swallowed.
  ///
  /// A report counts as landed once it reaches the seek's neighbourhood; the
  /// whole thing expires after ten seconds or five retries, at which point
  /// the live reports win no matter what -- a guard that never clears would
  /// freeze the playhead worse than the reset it prevents.
  bool _swallowStaleRestoreReport(Player player, Duration p) {
    // Play has been pressed and the restore seek is still being applied: the
    // engine is reporting the start of the song, which is not where the
    // listener is. Hold the screen on the spot until the seek lands.
    final saved = _restoreAt;
    if (saved != null &&
        (_restoreSeek?.active ?? false) &&
        p < saved - const Duration(seconds: 2)) {
      return true;
    }
    final target = _pendingSeek;
    if (target == null) return false;
    final since = _pendingSeekSince ?? DateTime.now();
    final landed = p >= target - const Duration(seconds: 2);
    if (landed ||
        DateTime.now().difference(since) > const Duration(seconds: 10) ||
        _seekRetries >= 5) {
      // Giving up on the guard is not giving up on the spot: play still
      // applies it (see [_restoreAt]).
      _clearPendingSeek(keepRestore: !landed);
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
    _peerSubs.add(
      player.stream.playing.listen((p) {
        _playing = p;
        notifyListeners();
      }),
    );
    _peerSubs.add(
      player.stream.position.listen((p) {
        if (_heldForNetwork) return;
        if (_swallowStaleRestoreReport(player, p)) return;
        _position = p;
        if (_playing &&
            p > Duration.zero &&
            _index >= 0 &&
            _index < _queue.length) {
          _heardIndex = _index;
          _heardSha = _queue[_index].sha;
          _heardAt = p;
          _heardWhen = DateTime.now();
          _anchor.heard(_heardSha!);
          if (p > const Duration(seconds: 5)) _skipsInRow = 0;
        }
        if ((p - _lastNotifiedPosition).abs() >=
            const Duration(milliseconds: 250)) {
          _lastNotifiedPosition = p;
          notifyListeners();
        }
      }),
    );
    _peerSubs.add(
      player.stream.duration.listen((d) {
        _duration = d;
        notifyListeners();
      }),
    );
    _peerSubs.add(
      player.stream.playlist.listen((pl) {
        // An emptied playlist echoing back from an earlier stop is not a track
        // change: media_kit clears the native playlist on stop() and that echo
        // can land after a later open, which used to slam the index (and with
        // it the mini-player) back to the start. Only a populated playlist may
        // move the index; our own stop()/halt() manage _queue themselves.
        if (pl.medias.isEmpty) return;
        if (_heldForNetwork) return;
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
      }),
    );
    // A stream that fails to open is retried, twice and a little later each
    // time, before the track is given up on and the next one played. A cold
    // track can fail its first open while the server is still fetching it.
    _peerSubs.add(
      player.stream.error.listen((message) {
        // A refused EQ chain fails every song the same way; retrying or
        // skipping cannot help. Drop the EQ and play the song again.
        if (_af.isNotEmpty && _isFilterError(message)) {
          _dropFilter(player);
          if (_index >= 0 && _index < _queue.length) {
            unawaited(_resumeAt(player, _index, _position));
          }
          return;
        }
        _retryOpen(player);
      }),
    );
    // The decoder finished the media by itself. With repeat off at the last
    // index the queue has run out; radio may continue it, otherwise it stops.
    _peerSubs.add(
      player.stream.completed.listen((done) {
        if (done && !_heldForNetwork) _onNaturalEnd();
      }),
    );
  }

  bool _subscribed = false;

  String? _retrySha;
  int _retries = 0;
  bool _retryWaiting = false;
  Duration _retryFrom = Duration.zero;

  void _retryOpen(Player player) {
    // Errors while held are the decoder failing on, offline; already handled.
    if (_heldForNetwork) return;
    if (_index < 0 || _index >= _queue.length) return;
    // One failure can report several errors; only the first is handled.
    if (_retryWaiting) return;
    _retryWaiting = true;
    unawaited(
      _onStreamFailed(player).whenComplete(() => _retryWaiting = false),
    );
  }

  Future<void> _onStreamFailed(Player player) async {
    var index = _index;
    var from = _position;
    final sha = _queue[index].sha;
    var resolved = [for (final t in _queue) trackUriFor(t)];
    // The song's bytes are on the phone now: play those, from the same spot,
    // instead of asking the server again.
    if (isLocalUri(resolved[index])) {
      DiagLog.log('player: stream dropped, song is on the phone');
      await _resumeAt(player, index, from);
      return;
    }
    final online =
        await (checkOnline?.call() ??
            Future<bool>.value(!(isOffline?.call() ?? false)));
    if (!online) {
      // Where the listener actually was. Offline, mpv moves on to the next
      // entry by itself when one fails, without a sound; the song heard last,
      // a few seconds ago at or before the current index, is the one to come
      // back to. Only offline, and never past an explicit move (next, back, a
      // tap, a seek clear it): online it threw the listener back to the song
      // they had just skipped, over and over.
      final heard = _heardWhen;
      if (heard != null &&
          DateTime.now().difference(heard) < const Duration(seconds: 15) &&
          _heardIndex >= 0 &&
          _heardIndex <= _index &&
          _heardIndex < _queue.length &&
          _queue[_heardIndex].sha == _heardSha) {
        // Once per song: with the server down and some songs still playing,
        // going back every time the next one failed replayed the same song
        // over and over. A second time, carry on forward from here instead.
        if (_anchor.take(_heardSha!)) {
          index = _heardIndex;
          from = _heardAt;
        } else {
          DiagLog.log('player: offline, already went back to this song');
        }
      }
      // A song that has to stream cannot play offline however often it is
      // retried, and skipping through the queue only fails song after song.
      // Go to the next song on the phone; with none, stay on this one.
      resolved = [for (final t in _queue) trackUriFor(t)];
      if (index < resolved.length && isLocalUri(resolved[index])) {
        await _resumeAt(player, index, from);
        return;
      }
      final to = nextLocalAfter(resolved, index);
      if (to != null) {
        DiagLog.log('player: offline, skipping to $to (on the phone)');
        await _resumeAt(player, to, Duration.zero);
        return;
      }
      DiagLog.log('player: offline, holding at $index');
      _holdForNetwork(player, index, from);
      return;
    }
    // Online: the song itself failed. Retry it twice, a little later each
    // time, then move on. A cold track can fail its first open while the
    // server is still fetching it. Only the song on now: if the listener
    // moved while the check ran, the failure is not theirs any more.
    if (_index != index || index >= _queue.length) return;
    if (_queue[index].sha != sha) return;
    if (sha != _retrySha) {
      _retrySha = sha;
      _retries = 0;
    }
    // A drop well after the last one is a new problem, not the same one again.
    if (_retries > 0 && from > _retryFrom + const Duration(seconds: 15)) {
      _retries = 0;
    }
    if (_retries >= 2) {
      _retries = 0;
      _skipsInRow += 1;
      if (_skipsInRow >= 3) {
        // Three songs in a row would not play though the server answers:
        // stop here rather than fail through everything. Play tries again.
        DiagLog.log('player: three songs failed in a row, holding');
        _skipsInRow = 0;
        _holdForNetwork(player, index, from);
        return;
      }
      next();
      return;
    }
    final wait = Duration(seconds: _retries == 0 ? 1 : 3);
    _retries += 1;
    _retryFrom = from;
    await Future<void>.delayed(wait);
    // Only if the listener has not moved on in the meantime.
    if (_index != index || index >= _queue.length) return;
    if (_queue[index].sha != sha) return;
    // Pick up where it dropped: starting the song over, up to three times,
    // read as the track repeating before it was skipped.
    await _reopenHere(player, _retryFrom, play: true);
  }

  /// Puts the listener on [index] at [at] and plays it from its best address.
  Future<void> _resumeAt(Player player, int index, Duration at) async {
    _clearPendingSeek();
    _index = index;
    _position = at;
    notifyListeners();
    await _reopenHere(player, at, play: true);
  }

  void _holdForNetwork(Player player, int index, Duration at) {
    _heldForNetwork = true;
    _clearPendingSeek();
    _index = index;
    _position = at;
    _playing = false;
    unawaited(player.pause());
    notifyListeners();
  }

  @override
  void networkReturned() {
    final player = _player;
    if (!_heldForNetwork || player == null) return;
    DiagLog.log('player: connection back, resuming');
    _heldForNetwork = false;
    unawaited(_reopenHere(player, _position, play: true));
  }

  @override
  void dispose() {
    // The native peer is process-lifetime (see _processPeer): destroying it
    // here would pull the decoder out from under live playback owned by a
    // newer generation. Detach instead: cancel our subscriptions so we never
    // publish again, yield liveness, and let the OS reclaim the peer with
    // the process.
    if (identical(_liveWrapper, this)) _liveWrapper = null;
    detach();
    _player = null;
    super.dispose();
  }
}
