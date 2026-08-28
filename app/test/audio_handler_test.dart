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
  final Duration _position = Duration.zero;

  @override
  Duration get duration => _duration;
  final Duration _duration = const Duration(seconds: 125);

  @override
  ManifestTrack? get current => _queue.isEmpty ? null : _queue[_index];

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
    final withArt = TuneAudioHandler(player, artBase: 'http://box:4780');
    expect(withArt.mediaItem.valueOrNull?.artUri, isNull);

    player.playQueue([_track('Art', artSha: 'a' * 64)], 0);
    expect(
      withArt.mediaItem.valueOrNull?.artUri?.toString(),
      'http://box:4780/art/${'a' * 64}',
    );
  });
}
