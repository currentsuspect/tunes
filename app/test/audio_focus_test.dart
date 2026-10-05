import 'package:audio_session/audio_session.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/audio/audio_focus.dart';
import 'package:tunes/core/audio/tune_player.dart';
import 'package:tunes/domain/manifest.dart';

class _Player extends TunePlayer {
  ManifestTrack? _current;
  Duration _position = Duration.zero;
  bool _playing = false;

  void loadTrack(ManifestTrack t) {
    _current = t;
    _position = Duration.zero;
    _playing = true;
    notifyListeners();
  }

  /// Advances as playback would: many small steps, which is what the recorder
  /// actually sees.
  void listenFor(Duration total, {Duration step = const Duration(seconds: 1)}) {
    var left = total;
    while (left > Duration.zero) {
      final chunk = left < step ? left : step;
      _position += chunk;
      left -= chunk;
      notifyListeners();
    }
  }

  void seekTo(Duration to) {
    _position = to;
    notifyListeners();
  }

  void endTrack() {
    _current = null;
    _playing = false;
    notifyListeners();
  }

  @override
  List<ManifestTrack> get queue => const [];
  @override
  int get index => 0;
  @override
  bool get playing => _playing;
  @override
  Duration get position => _position;
  @override
  Duration get duration => Duration(milliseconds: _current?.durationMs ?? 0);
  @override
  ManifestTrack? get current => _current;
  @override
  PlaybackRepeat get repeat => PlaybackRepeat.off;
  @override
  bool get shuffle => false;
  @override
  void playQueue(List<ManifestTrack> tracks, int startIndex) {}
  final volumes = <double>[];
  @override
  void setVolume(double level) => volumes.add(level);
  int plays = 0;
  int pauses = 0;
  @override
  void play() {
    plays++;
    _playing = true;
    notifyListeners();
  }

  @override
  void pause() {
    pauses++;
    _playing = false;
    notifyListeners();
  }

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
  size: 0,
  codec: 'flac',
  sampleRate: 44100,
  channels: 2,
  bitrate: 900000,
  durationMs: 180000,
  title: 'T',
  artist: 'A',
  album: 'Al',
  year: null,
  artSha: null,
  releaseId: null,
  trackNumber: null,
  discNumber: null,
);

final _lost = AudioInterruptionEvent(true, AudioInterruptionType.unknown);
final _transient = AudioInterruptionEvent(true, AudioInterruptionType.pause);
final _back = AudioInterruptionEvent(false, AudioInterruptionType.pause);

/// A scripted "is another app playing", one answer per poll.
class _Other {
  _Other(this.busy);
  bool busy;
  Future<bool> call() async => busy;
}

void main() {
  _Player playing() => _Player()..loadTrack(_track());

  test('a permanent loss pauses, then carries on once the output is quiet', () {
    fakeAsync((async) {
      final p = playing();
      final other = _Other(true);
      final focus = AudioFocus(
        p,
        now: async.getClock(DateTime(2026)).now,
        otherAudioActive: other.call,
      );
      focus.handleInterruption(_lost);
      expect(p.playing, isFalse);
      expect(focus.waiting, isTrue);

      // The other app is still playing: nothing happens, however long.
      async.elapse(const Duration(minutes: 2));
      expect(p.playing, isFalse);

      // It stops. Not yet: quiet has to last a moment.
      other.busy = false;
      async.elapse(const Duration(milliseconds: 400));
      expect(p.playing, isFalse);
      async.elapse(const Duration(seconds: 1));
      expect(p.playing, isTrue);
      expect(focus.waiting, isFalse);
    });
  });

  test('a gap between two clips does not start the music', () {
    fakeAsync((async) {
      final p = playing();
      final other = _Other(true);
      final focus = AudioFocus(
        p,
        now: async.getClock(DateTime(2026)).now,
        otherAudioActive: other.call,
      );
      focus.handleInterruption(_lost);

      other.busy = false;
      async.elapse(const Duration(milliseconds: 400));
      // The next clip starts before the quiet is long enough.
      other.busy = true;
      async.elapse(const Duration(seconds: 2));
      other.busy = false;
      async.elapse(const Duration(milliseconds: 400));
      expect(p.playing, isFalse);
      expect(p.plays, 0);
    });
  });

  test('pressing play ends the wait', () {
    fakeAsync((async) {
      final p = playing();
      final focus = AudioFocus(
        p,
        now: async.getClock(DateTime(2026)).now,
        otherAudioActive: _Other(true).call,
      );
      focus.handleInterruption(_lost);
      p.play();
      async.elapse(const Duration(seconds: 3));
      expect(focus.waiting, isFalse);
    });
  });

  test('stopping the queue ends the wait and nothing resumes', () {
    fakeAsync((async) {
      final p = playing();
      final other = _Other(true);
      final focus = AudioFocus(
        p,
        now: async.getClock(DateTime(2026)).now,
        otherAudioActive: other.call,
      );
      focus.handleInterruption(_lost);
      p.endTrack();
      other.busy = false;
      async.elapse(const Duration(seconds: 30));
      expect(focus.waiting, isFalse);
      expect(p.plays, 0);
    });
  });

  test('a wait does not go on for ever', () {
    fakeAsync((async) {
      final p = playing();
      final focus = AudioFocus(
        p,
        now: async.getClock(DateTime(2026)).now,
        otherAudioActive: _Other(true).call,
        giveUpAfter: const Duration(minutes: 5),
      );
      focus.handleInterruption(_lost);
      async.elapse(const Duration(minutes: 6));
      expect(focus.waiting, isFalse);
      expect(p.playing, isFalse);
    });
  });

  test('nothing plays that was not playing', () {
    fakeAsync((async) {
      final p = _Player();
      final focus = AudioFocus(
        p,
        now: async.getClock(DateTime(2026)).now,
        otherAudioActive: _Other(false).call,
      );
      focus.handleInterruption(_lost);
      async.elapse(const Duration(seconds: 30));
      expect(focus.waiting, isFalse);
      expect(p.plays, 0);
    });
  });

  test('the music comes back up from silence, not at full level', () {
    fakeAsync((async) {
      final p = playing();
      final other = _Other(true);
      final focus = AudioFocus(
        p,
        now: async.getClock(DateTime(2026)).now,
        otherAudioActive: other.call,
      );
      focus.handleInterruption(_lost);
      p.volumes.clear();
      other.busy = false;
      async.elapse(const Duration(seconds: 1));
      expect(p.playing, isTrue);
      // Starts at nothing, climbs, and ends at full.
      expect(p.volumes.first, 0.0);
      async.elapse(const Duration(seconds: 3));
      expect(p.volumes.last, 1.0);
      for (var i = 1; i < p.volumes.length; i++) {
        expect(p.volumes[i], greaterThanOrEqualTo(p.volumes[i - 1]));
      }
    });
  });

  test('pausing mid-fade leaves the next play at full level', () {
    fakeAsync((async) {
      final p = playing();
      final other = _Other(true);
      final focus = AudioFocus(
        p,
        now: async.getClock(DateTime(2026)).now,
        otherAudioActive: other.call,
      );
      focus.handleInterruption(_lost);
      other.busy = false;
      async.elapse(const Duration(milliseconds: 1400));
      expect(p.playing, isTrue);
      // Mid-fade, the listener pauses.
      p.pause();
      focus.handleInterruption(_lost); // not playing: nothing
      async.elapse(const Duration(seconds: 3));
      // The level was put back, and the fade is not still running.
      expect(p.volumes.last, 1.0);
    });
  });

  test('a call still pauses and resumes by the system telling us', () {
    fakeAsync((async) {
      final p = playing();
      final focus = AudioFocus(
        p,
        now: async.getClock(DateTime(2026)).now,
        otherAudioActive: _Other(true).call,
      );
      focus.handleInterruption(_transient);
      expect(p.playing, isFalse);
      focus.handleInterruption(_back);
      expect(p.playing, isTrue);
      expect(focus.waiting, isFalse);
    });
  });

  test('a transient loss that never says it is over still ends when quiet', () {
    fakeAsync((async) {
      final p = playing();
      final other = _Other(true);
      final focus = AudioFocus(
        p,
        now: async.getClock(DateTime(2026)).now,
        otherAudioActive: other.call,
      );
      focus.handleInterruption(_transient);
      expect(p.playing, isFalse);
      async.elapse(const Duration(seconds: 20));
      expect(p.playing, isFalse);
      other.busy = false;
      async.elapse(const Duration(seconds: 8));
      expect(p.playing, isTrue);
    });
  });

  test('a pause the listener made is not undone by a call ending', () {
    fakeAsync((async) {
      final p = playing()..pause();
      final focus = AudioFocus(
        p,
        now: async.getClock(DateTime(2026)).now,
        otherAudioActive: _Other(true).call,
      );
      focus.handleInterruption(_transient);
      focus.handleInterruption(_back);
      expect(p.playing, isFalse);
    });
  });
}
