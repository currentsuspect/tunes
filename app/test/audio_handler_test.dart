import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/audio/tune_audio_handler.dart';
import 'package:tunes/core/audio/tune_player.dart';
import 'package:tunes/domain/manifest.dart';

class _FakePlayer extends TunePlayer {
  @override
  List<ManifestTrack> get queue => _queue;
  List<ManifestTrack> _queue = const [];

  @override
  int get index => _index;
  int _index = 0;

  @override
  bool get playing => _playing;
  bool _playing = false;

  @override
  Duration get position => _position;
  Duration _position = Duration.zero;

  /// Advances playback the way the real player reports it: a small step,
  /// four times a second, each one notifying listeners.
  void tick([Duration by = const Duration(milliseconds: 250)]) {
    _position += by;
    notifyListeners();
  }

  /// A jump, as a seek or a stall produces.
  void jumpTo(Duration to) {
    _position = to;
    notifyListeners();
  }

  void setPlaying(bool v) {
    _playing = v;
    notifyListeners();
  }

  @override
  Duration get duration => _duration;
  final Duration _duration = const Duration(seconds: 125);

  @override
  ManifestTrack? get current => _queue.isEmpty ? null : _queue[_index];

  @override
  PlaybackRepeat get repeat => PlaybackRepeat.off;

  @override
  bool get shuffle => false;

  int playCalls = 0;
  int pauseCalls = 0;
  int nextCalls = 0;
  int previousCalls = 0;
  int seekCalls = 0;
  int stopCalls = 0;

  @override
  void play() => playCalls += 1;

  @override
  void pause() => pauseCalls += 1;

  @override
  void next() => nextCalls += 1;

  @override
  void previous() => previousCalls += 1;

  @override
  void playAt(int index) {}

  @override
  void playQueue(List<ManifestTrack> tracks, int startIndex) {
    _queue = List.of(tracks);
    _index = startIndex;
    _playing = true;
    notifyListeners();
  }

  @override
  void seek(Duration target) => seekCalls += 1;

  @override
  void stop() => stopCalls += 1;

  @override
  void toggle() => _playing = !_playing;

  @override
  void setRepeat(PlaybackRepeat mode) {}

  @override
  void setShuffle(bool on) {}
}

ManifestTrack _track(String title, {String? artSha}) => ManifestTrack(
  sha: 'b' * 64,
  size: 10,
  codec: 'flac',
  sampleRate: 44100,
  channels: 2,
  bitrate: 950000,
  durationMs: 125000,
  title: title,
  artist: 'Artist',
  album: 'Album',
  year: null,
  artSha: artSha,
  releaseId: 'rel-1',
  trackNumber: null,
  discNumber: null,
);

void main() {
  late _FakePlayer player;
  late TuneAudioHandler handler;

  setUp(() {
    player = _FakePlayer();
    player.playQueue([_track('One'), _track('Two')], 0);
    handler = TuneAudioHandler(player);
  });

  test('notification controls reach the player', () async {
    await handler.play();
    expect(player.playCalls, 1);

    await handler.pause();
    expect(player.pauseCalls, 1);

    await handler.skipToNext();
    expect(player.nextCalls, 1);

    await handler.skipToPrevious();
    expect(player.previousCalls, 1);

    await handler.seek(const Duration(seconds: 30));
    expect(player.seekCalls, 1);

    await handler.stop();
    expect(player.stopCalls, 1);
  });

  test('playback state mirrors the player', () {
    player._playing = true;
    player.notifyListeners();
    final state = handler.playbackState.valueOrNull;
    expect(state?.playing, true);
    expect(state?.controls, contains(MediaControl.pause));
    expect(state?.processingState, AudioProcessingState.ready);

    player._playing = false;
    player.notifyListeners();
    final paused = handler.playbackState.valueOrNull;
    expect(paused?.playing, false);
    expect(paused?.controls, contains(MediaControl.play));
  });

  test('media item and queue track the library', () {
    final item = handler.mediaItem.valueOrNull;
    expect(item?.title, 'One');
    expect(item?.artist, 'Artist');
    expect(handler.queue.valueOrNull?.length, 2);
  });

  test('media item carries the track artwork for the notification', () {
    // A resolver now: the handler asks for a full artwork URL rather than
    // building one from a base, so a signed capability can be attached
    // without the notification loader knowing anything about it.
    final withArt = TuneAudioHandler(
      player,
      artUriFor: (sha) => 'http://box:4780/art/$sha',
    );
    expect(withArt.mediaItem.valueOrNull?.artUri, isNull);

    player.playQueue([_track('Art', artSha: 'a' * 64)], 0);
    expect(
      withArt.mediaItem.valueOrNull?.artUri?.toString(),
      'http://box:4780/art/${'a' * 64}',
    );
  });

  group('notification updates', () {
    test('a position tick does not repost the notification', () async {
      // The system is given a position and a speed and extrapolates the rest
      // itself, so a new state every quarter second tells it nothing -- and
      // costs a notification post each time. The app was making 75,000 of
      // them a day and had been demoted by the ranker for it.
      // Time advances with playback, as it does on a device: the position
      // the system extrapolates and the position reported stay together, so
      // there is nothing to correct.
      var now = DateTime(2026);
      final p = _FakePlayer();
      final h = TuneAudioHandler(p, clock: () => now);
      p.playQueue([_track('One'), _track('Two')], 0);
      var posts = 0;
      final sub = h.playbackState.skip(1).listen((_) => posts += 1);

      for (var i = 0; i < 40; i++) {
        now = now.add(const Duration(milliseconds: 250));
        p.tick();
      }
      await Future<void>.delayed(Duration.zero);

      expect(posts, 0);
      await sub.cancel();
    });

    test('play and pause do repost', () async {
      player.playQueue([_track('One')], 0);
      var posts = 0;
      final sub = handler.playbackState.skip(1).listen((_) => posts += 1);

      player.setPlaying(false);
      player.setPlaying(true);
      await Future<void>.delayed(Duration.zero);

      expect(posts, 2);
      await sub.cancel();
    });

    test('a seek reposts, because the extrapolation is now wrong', () async {
      player.playQueue([_track('One')], 0);
      var posts = 0;
      final sub = handler.playbackState.skip(1).listen((_) => posts += 1);

      player.jumpTo(const Duration(minutes: 1));
      await Future<void>.delayed(Duration.zero);

      expect(posts, 1);
      await sub.cancel();
    });

    test('the same track is not announced twice', () async {
      // Re-announcing a media item rebuilds the notification and sends the
      // platform to fetch the artwork again.
      var now = DateTime(2026);
      final p = _FakePlayer();
      final h = TuneAudioHandler(p, clock: () => now);
      p.playQueue([_track('One')], 0);
      var items = 0;
      final sub = h.mediaItem.skip(1).listen((_) => items += 1);

      for (var i = 0; i < 20; i++) {
        now = now.add(const Duration(milliseconds: 250));
        p.tick();
      }
      await Future<void>.delayed(Duration.zero);

      expect(items, 0);
      await sub.cancel();
    });
  });
}
