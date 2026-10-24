import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/audio/tune_player.dart';
import 'package:tunes/core/platform/mpris.dart';
import 'package:tunes/domain/manifest.dart';

ManifestTrack _t(String sha, String title) => ManifestTrack(
  sha: sha * 64,
  size: 1,
  codec: 'flac',
  sampleRate: 44100,
  channels: 2,
  bitrate: 1,
  durationMs: 157000,
  title: title,
  artist: 'Yeat',
  album: 'ADL',
  year: null,
  artSha: 'b' * 64,
  releaseId: null,
  trackNumber: null,
  discNumber: null,
);

class _P extends TunePlayer {
  _P(this.queue);
  @override
  final List<ManifestTrack> queue;
  @override
  int index = 0;
  @override
  bool playing = true;
  @override
  Duration position = const Duration(seconds: 67);
  @override
  Duration get duration => const Duration(seconds: 157);
  @override
  ManifestTrack? get current => queue.isEmpty ? null : queue[index];
  @override
  PlaybackRepeat repeat = PlaybackRepeat.off;
  @override
  bool shuffle = false;
  final calls = <String>[];
  @override
  void playQueue(List<ManifestTrack> tracks, int startIndex) {}
  @override
  void play() => calls.add('play');
  @override
  void pause() => calls.add('pause');
  @override
  void toggle() => calls.add('toggle');
  @override
  void next() => calls.add('next');
  @override
  void previous() => calls.add('previous');
  @override
  void playAt(int index) {}
  @override
  void seek(Duration target) => calls.add('seek ${target.inSeconds}');
  @override
  void stop() {}
  @override
  void setRepeat(PlaybackRepeat mode) => calls.add('repeat ${mode.name}');
  @override
  void setShuffle(bool on) => calls.add('shuffle $on');
}

void main() {
  test('tells the desktop what is playing, with the saved cover', () {
    final p = _P([_t('a', 'Griddlë'), _t('c', 'MARCHING')]);
    final r = mprisReport(p, artPathFor: (_) => '/art/b');
    expect(r['status'], 'Playing');
    expect(r['title'], 'Griddlë');
    expect(r['artist'], 'Yeat');
    expect(r['artUrl'], 'file:///art/b');
    expect(r['lengthUs'], 157000000);
    expect(r['positionUs'], 67000000);
    expect(r['canNext'], isTrue);
  });

  test('the last song has no next unless it repeats; nothing is Stopped', () {
    final p = _P([_t('a', 'Griddlë')]);
    expect(mprisReport(p)['canNext'], isFalse);
    p.repeat = PlaybackRepeat.all;
    expect(mprisReport(p)['canNext'], isTrue);
    expect(mprisReport(p)['loop'], 'Playlist');
    expect(mprisReport(_P([]))['status'], 'Stopped');
    expect(mprisReport(_P([]))['trackId'], '');
  });

  test('carries out the desktop\'s commands', () {
    final p = _P([_t('a', 'Griddlë')]);
    for (final (name, value) in [
      ('playPause', null),
      ('next', null),
      ('seek', 60000000),
      ('shuffle', true),
      ('loop', 'Track'),
      ('nonsense', null),
    ]) {
      mprisCommand(p, name, value);
    }
    expect(p.calls, [
      'toggle',
      'next',
      'seek 60',
      'shuffle true',
      'repeat one',
    ]);
  });
}
