import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/audio/tune_player.dart';
import 'package:tunes/core/data/database.dart';
import 'package:tunes/core/data/play_history.dart';
import 'package:tunes/domain/manifest.dart';

/// A player we can drive frame by frame, so a listen can be simulated without
/// waiting out a real track.
class _FakePlayer extends TunePlayer {
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

ManifestTrack _track(String sha, {int durationMs = 180000}) => ManifestTrack(
  sha: sha,
  size: 0,
  codec: 'flac',
  sampleRate: 44100,
  channels: 2,
  bitrate: 900000,
  durationMs: durationMs,
  title: 'T $sha',
  artist: 'A',
  album: 'Al',
  year: null,
  artSha: null,
  releaseId: null,
  trackNumber: null,
  discNumber: null,
);

void main() {
  late TunesDatabase db;
  late _FakePlayer player;
  late PlayHistory history;

  setUp(() {
    db = TunesDatabase.forTesting(NativeDatabase.memory());
    player = _FakePlayer();
    history = PlayHistory(db, player);
  });

  tearDown(() async {
    history.dispose();
    await db.close();
  });

  Future<List<PlayEvent>> events() => db.select(db.playEvents).get();

  test('half a track counts as a play', () async {
    player.loadTrack(_track('a', durationMs: 120000));
    player.listenFor(const Duration(seconds: 61));
    history.flush();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final rows = await events();
    expect(rows, hasLength(1));
    expect(rows.single.completed, isTrue);
    expect(rows.single.sha, 'a');
  });

  test('abandoning early is a skip, and is still recorded', () async {
    // A skip is a signal, not an absence. Dropping it would make "never
    // played" and "started and hated" look identical.
    player.loadTrack(_track('b', durationMs: 120000));
    player.listenFor(const Duration(seconds: 20));
    history.flush();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final rows = await events();
    expect(rows, hasLength(1));
    expect(rows.single.completed, isFalse);
    expect(await history.skipCounts(), {'b': 1});
    expect(await history.playCounts(), isEmpty);
  });

  test('four minutes of a long track counts even below half', () async {
    player.loadTrack(_track('c', durationMs: 1800000));
    player.listenFor(const Duration(minutes: 4, seconds: 1));
    history.flush();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect((await events()).single.completed, isTrue);
  });

  test('seeking to the end is not listening', () async {
    // The whole reason listened time is accumulated rather than read off the
    // final position: a jump to the last second is not a play.
    player.loadTrack(_track('d', durationMs: 120000));
    player.listenFor(const Duration(seconds: 5));
    player.seekTo(const Duration(seconds: 119));
    history.flush();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final rows = await events();
    expect(rows.single.completed, isFalse);
    expect(rows.single.listenedMs, lessThan(10000));
  });

  test('a mis-tap is not recorded at all', () async {
    player.loadTrack(_track('e'));
    player.listenFor(const Duration(milliseconds: 400));
    history.flush();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(await events(), isEmpty);
  });

  test('changing track settles the one before it', () async {
    player.loadTrack(_track('f', durationMs: 60000));
    player.listenFor(const Duration(seconds: 40));
    player.loadTrack(_track('g', durationMs: 60000));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final rows = await events();
    expect(rows, hasLength(1));
    expect(rows.single.sha, 'f');
    expect(rows.single.completed, isTrue);
  });

  /// Plays [sha] through [times] times, settling each one.
  Future<void> playThrough(String sha, int times) async {
    for (var i = 0; i < times; i++) {
      player.loadTrack(_track(sha, durationMs: 60000));
      player.listenFor(const Duration(seconds: 40));
      history.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  group('on repeat', () {
    test('ranks by how often, heaviest first', () async {
      await playThrough('a', 2);
      await playThrough('b', 5);
      await playThrough('c', 3);

      expect(await history.topShas(), ['b', 'c', 'a']);
    });

    test('a track played once is not "most played"', () async {
      // Otherwise the section is an arbitrary order wearing the word "most".
      await playThrough('once', 1);
      await playThrough('twice', 2);

      expect(await history.topShas(), ['twice']);
    });

    test('skips do not count towards it', () async {
      player.loadTrack(_track('skipped', durationMs: 120000));
      player.listenFor(const Duration(seconds: 10));
      history.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await playThrough('skipped', 1);

      // One real play out of two starts is not two plays.
      expect(await history.topShas(minPlays: 2), isEmpty);
    });
  });

  group('listen again', () {
    test('offers what is not in the current rotation', () async {
      await playThrough('old', 4);
      await playThrough('older', 2);
      await playThrough('now1', 1);
      await playThrough('now2', 1);

      // The two most recently played are current rotation, not a suggestion.
      expect(await history.listenAgainShas(skipRecent: 2), ['old', 'older']);
    });

    test('ranks the rest by how much they were played', () async {
      await playThrough('light', 1);
      await playThrough('heavy', 6);
      await playThrough('recent', 1);

      expect(await history.listenAgainShas(skipRecent: 1), ['heavy', 'light']);
    });

    test('is empty when everything played is still in rotation', () async {
      // A fresh install must not be offered its own last three tracks back.
      await playThrough('a', 1);
      await playThrough('b', 1);

      expect(await history.listenAgainShas(skipRecent: 10), isEmpty);
    });
  });

  test('recents are distinct and newest first', () async {
    for (final sha in ['x', 'y', 'x']) {
      player.loadTrack(_track(sha, durationMs: 60000));
      player.listenFor(const Duration(seconds: 40));
    }
    history.flush();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // x played twice is one thing you were listening to, not two rows.
    //
    // All three listens are recorded within the same millisecond, so this
    // also pins the tie-break: with timestamps equal, the order has to come
    // from which row was written last, not from whatever the database
    // happens to return.
    expect(await history.recentShas(), ['x', 'y']);
    expect(await history.playCounts(), {'x': 2, 'y': 1});
  });
}
