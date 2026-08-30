import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/audio/tune_player.dart';
import 'package:tunes/domain/manifest.dart';

class _PlayerUnderTest extends TunePlayer {
  List<ManifestTrack> _queue = const [];
  int _index = -1;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
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
  void playQueue(List<ManifestTrack> tracks, int startIndex) {
    if (tracks.isEmpty) return;
    final safeStart = startIndex.clamp(0, tracks.length - 1).toInt();
    if (_shuffle && tracks.length > 1) {
      // Mirror MediaKitTunePlayer: pin the start track first, Fisher-Yates
      // the remainder.
      final out = List<ManifestTrack>.of(tracks);
      final pinned = out.removeAt(safeStart);
      out.shuffle();
      _queue = [pinned, ...out];
      _index = 0;
    } else {
      _queue = List.of(tracks);
      _index = safeStart;
    }
    _playing = true;
    _position = Duration.zero;
    final ms = _queue[_index].durationMs;
    _duration = ms != null ? Duration(milliseconds: ms) : Duration.zero;
    notifyListeners();
  }

  @override
  void play() {
    _playing = true;
    notifyListeners();
  }

  @override
  void pause() {
    _playing = false;
    notifyListeners();
  }

  @override
  void toggle() {
    _playing = !_playing;
    notifyListeners();
  }

  @override
  void next() {
    if (_queue.isEmpty) return;
    if (_repeat == PlaybackRepeat.one) {
      _position = Duration.zero;
      _playing = true;
      notifyListeners();
      return;
    }
    if (_index >= _queue.length - 1) {
      if (_repeat == PlaybackRepeat.all && _queue.length > 1) {
        _index = 0;
        _position = Duration.zero;
        notifyListeners();
        return;
      }
      _queue = const [];
      _index = -1;
      _playing = false;
      _position = Duration.zero;
      notifyListeners();
      return;
    }
    _index += 1;
    _position = Duration.zero;
    notifyListeners();
  }

  @override
  void previous() {
    if (_queue.isEmpty) return;
    if (_index > 0) {
      _index -= 1;
      _position = Duration.zero;
      notifyListeners();
      return;
    }
    if (_repeat == PlaybackRepeat.all && _queue.length > 1) {
      _index = _queue.length - 1;
      _position = Duration.zero;
      notifyListeners();
      return;
    }
    _position = Duration.zero;
    notifyListeners();
  }

  @override
  void playAt(int index) {
    if (index < 0 || index >= _queue.length) return;
    _index = index;
    _playing = true;
    notifyListeners();
  }

  @override
  void seek(Duration target) {
    _position = target;
    notifyListeners();
  }

  @override
  void stop() {
    _queue = const [];
    _index = -1;
    _playing = false;
    _position = Duration.zero;
    notifyListeners();
  }

  @override
  void setRepeat(PlaybackRepeat mode) {
    if (_repeat == mode) return;
    _repeat = mode;
    notifyListeners();
  }

  @override
  void setShuffle(bool on) {
    if (_shuffle == on) return;
    _shuffle = on;
    notifyListeners();
  }
}

ManifestTrack _t(String title) => ManifestTrack(
  sha: '$title sha'.padRight(64, 'x'),
  size: 1,
  codec: 'flac',
  sampleRate: 44100,
  channels: 2,
  bitrate: 950000,
  durationMs: 1000,
  title: title,
  artist: 'Artist',
  album: 'Album',
  year: null,
  artSha: null,
  releaseId: null,
  trackNumber: null,
  discNumber: null,
);

void main() {
  group('TunePlayer repeat modes', () {
    late _PlayerUnderTest p;

    setUp(() {
      p = _PlayerUnderTest();
      p.playQueue([_t('a'), _t('b'), _t('c')], 0);
    });

    test('off: next at end stops playback', () {
      p.setRepeat(PlaybackRepeat.off);
      p.playQueue([_t('a'), _t('b'), _t('c')], 2);
      p.next();
      expect(p.queue, isEmpty);
      expect(p.playing, isFalse);
    });

    test('all: next at end wraps to first', () {
      p.setRepeat(PlaybackRepeat.all);
      p.playQueue([_t('a'), _t('b'), _t('c')], 2);
      p.next();
      expect(p.current?.title, 'a');
      expect(p.index, 0);
    });

    test('one: next at end restarts current track', () {
      p.setRepeat(PlaybackRepeat.one);
      p.playQueue([_t('a'), _t('b'), _t('c')], 1);
      p.next();
      // Did not advance; position reset; still playing.
      expect(p.index, 1);
      expect(p.playing, isTrue);
      expect(p.position, Duration.zero);
    });

    test('previous at first track with repeat-all wraps to last', () {
      p.setRepeat(PlaybackRepeat.all);
      p.playQueue([_t('a'), _t('b'), _t('c')], 0);
      p.previous();
      expect(p.current?.title, 'c');
      expect(p.index, 2);
    });

    test('previous at first track with repeat-off restarts current', () {
      p.setRepeat(PlaybackRepeat.off);
      p.playQueue([_t('a'), _t('b'), _t('c')], 0);
      p.previous();
      expect(p.index, 0);
      expect(p.position, Duration.zero);
    });

    test('setRepeat notifies listeners exactly once per change', () {
      var notified = 0;
      p.addListener(() => notified += 1);
      p.setRepeat(PlaybackRepeat.all);
      p.setRepeat(PlaybackRepeat.all); // no-op
      p.setRepeat(PlaybackRepeat.one);
      expect(notified, 2);
    });
  });

  group('TunePlayer shuffle', () {
    late _PlayerUnderTest p;

    setUp(() {
      p = _PlayerUnderTest();
    });

    test('setShuffle toggles state', () {
      expect(p.shuffle, isFalse);
      p.setShuffle(true);
      expect(p.shuffle, isTrue);
      p.setShuffle(false);
      expect(p.shuffle, isFalse);
    });

    test('playQueue without shuffle preserves caller startIndex', () {
      p.playQueue([_t('a'), _t('b'), _t('c')], 2);
      expect(p.current?.title, 'c');
      expect(p.index, 2);
    });

    test('playQueue with shuffle places start track at index 0 (ordering tested in MediaKitTunePlayer)', () {
      p.setShuffle(true);
      p.playQueue([_t('a'), _t('b'), _t('c'), _t('d')], 1);
      expect(p.index, 0);
    });

    test(
      'setShuffle is a no-op when value is unchanged (no listener notify)',
      () {
        var notified = 0;
        p.addListener(() => notified += 1);
        p.setShuffle(true);
        p.setShuffle(true);
        expect(notified, 1);
      },
    );
  });
}
