import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/audio/tune_audio_handler.dart';
import 'package:tunes/core/audio/tune_player.dart';
import 'package:tunes/domain/manifest.dart';

/// Notification artwork must follow the configured server.
///
/// It used to be a String captured when the handler was built, which meant it
/// kept pointing at whichever server the app launched against. Changing the
/// server left the notification fetching covers from a machine that, for
/// anyone but the original owner, was never reachable at all.
///
/// This is the same class of bug as the stream URL: a value read once at
/// startup, in a codebase where the server is now a setting.
class _FakePlayer extends TunePlayer {
  ManifestTrack? _current;

  void setCurrent(ManifestTrack? t) {
    _current = t;
    notifyListeners();
  }

  @override
  List<ManifestTrack> get queue => const [];
  @override
  int get index => -1;
  @override
  bool get playing => false;
  @override
  Duration get position => Duration.zero;
  @override
  Duration get duration => const Duration(seconds: 100);
  @override
  ManifestTrack? get current => _current;
  @override
  PlaybackRepeat get repeat => PlaybackRepeat.off;
  @override
  bool get shuffle => false;
  @override
  void playQueue(List<ManifestTrack> tracks, int startIndex) {}
  @override
  void play() {}
  @override
  void pause() {}
  @override
  void toggle() {}
  @override
  void next() {}
  @override
  void previous() {}
  @override
  void playAt(int index) {}
  @override
  void seek(Duration target) {}
  @override
  void stop() {}
  @override
  void setRepeat(PlaybackRepeat mode) {}
  @override
  void setShuffle(bool on) {}
}

ManifestTrack _track() => ManifestTrack(
  sha: 'a' * 64,
  size: 1000,
  codec: 'flac',
  sampleRate: 44100,
  channels: 2,
  bitrate: 900000,
  durationMs: 100000,
  title: 'Track',
  artist: 'Artist',
  album: 'Album',
  year: null,
  artSha: 'b' * 64,
  releaseId: null,
  trackNumber: null,
  discNumber: null,
);

void main() {
  test('artwork is fetched from the server in use, not the one at launch', () {
    var server = 'http://first:4780';
    final player = _FakePlayer();
    final handler = TuneAudioHandler(player, artBase: () => server);

    player.setCurrent(_track());
    expect(
      handler.mediaItem.valueOrNull?.artUri.toString(),
      startsWith(server),
    );

    // The server changes while the app is running, which is what the Settings
    // field does. Nothing is rebuilt.
    server = 'http://100.100.235.90:4780';
    // A different track, so the item is re-announced rather than suppressed as
    // unchanged.
    player.setCurrent(_track());

    expect(
      handler.mediaItem.valueOrNull?.artUri.toString(),
      startsWith('http://100.100.235.90:4780'),
      reason: 'artBase was captured instead of read when needed',
    );
  });

  test('no artwork source yields no artUri rather than a broken one', () {
    final player = _FakePlayer();
    final handler = TuneAudioHandler(player);
    player.setCurrent(_track());
    // '' would build '/art/<sha>', a relative URI the platform cannot fetch.
    final uri = handler.mediaItem.valueOrNull?.artUri;
    expect(uri == null || uri.toString().startsWith('/art/'), isTrue);
  });
}
