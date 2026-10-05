import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
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

  /// A completed play of [sha] that started [ago] ago, written straight to the
  /// table so a test can put history in the past without waiting for it.
  Future<void> playedAgo(String sha, Duration ago, {int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await db
          .into(db.playEvents)
          .insert(
            PlayEventsCompanion.insert(
              sha: sha,
              startedAt: DateTime.now()
                  .subtract(ago)
                  .subtract(Duration(minutes: i))
                  .millisecondsSinceEpoch,
              listenedMs: 40000,
              durationMs: const Value(60000),
              completed: const Value(true),
            ),
          );
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

    test('is what is on today, not what has been played all year', () async {
      // Fifty plays last month, three this morning. The long history must not
      // outrank, or even appear beside, what is actually looping now.
      await playedAgo(
        'last-months-favourite',
        const Duration(days: 30),
        times: 50,
      );
      await playedAgo('this-morning', const Duration(hours: 3), times: 3);
      await playedAgo('yesterday-ish', const Duration(hours: 30), times: 9);

      expect(await history.topShas(), ['this-morning']);
    });

    test('the window is a day by default and can be changed', () async {
      await playedAgo('two-days-ago', const Duration(days: 2), times: 4);

      expect(await history.topShas(), isEmpty);
      expect(await history.topShas(window: const Duration(days: 3)), [
        'two-days-ago',
      ]);
    });

    test(
      'plays just outside the window do not count towards the total',
      () async {
        await playedAgo('edge', const Duration(hours: 2), times: 1);
        await playedAgo('edge', const Duration(hours: 40), times: 5);

        // One play in the window is below the two it takes.
        expect(await history.topShas(), isEmpty);
      },
    );
  });

  group('listen again', () {
    test('is what you played a while back and have not played since', () async {
      await playedAgo('last-month', const Duration(days: 30), times: 4);
      await playedAgo('two-months', const Duration(days: 60), times: 2);

      expect(await history.listenAgainShas(), ['last-month', 'two-months']);
    });

    test('ranks the rest by how much they were played', () async {
      await playedAgo('light', const Duration(days: 20), times: 1);
      await playedAgo('heavy', const Duration(days: 40), times: 6);

      expect(await history.listenAgainShas(), ['heavy', 'light']);
    });

    test('leaves out anything played in the last couple of weeks', () async {
      await playedAgo('lately', const Duration(days: 5), times: 8);
      await playedAgo('this-morning', const Duration(hours: 2), times: 3);
      await playedAgo('forgotten', const Duration(days: 25), times: 2);

      expect(await history.listenAgainShas(), ['forgotten']);
    });

    test('leaves out what is so old it is another taste', () async {
      await playedAgo('ancient', const Duration(days: 400), times: 9);

      expect(await history.listenAgainShas(), isEmpty);
    });

    test('is empty on a fresh install rather than echoing it back', () async {
      // Everything played in the last hour is current, not something to go back
      // to: a new install must not be offered its own last tracks.
      await playThrough('a', 1);
      await playThrough('b', 1);

      expect(await history.listenAgainShas(), isEmpty);
    });

    test('never repeats what is on repeat', () async {
      // The exact complaint: the same favourites sitting in both rails.
      await playedAgo('favourite', const Duration(hours: 2), times: 5);
      await playedAgo('favourite', const Duration(days: 30), times: 20);
      await playedAgo('old-one', const Duration(days: 30), times: 3);

      final top = await history.topShas();
      final again = await history.listenAgainShas(exclude: top.toSet());

      expect(top, ['favourite']);
      expect(again, ['old-one']);
      expect(top.toSet().intersection(again.toSet()), isEmpty);
    });

    test('an excluded track stays out even when it is quiet', () async {
      await playedAgo('skip-me', const Duration(days: 30), times: 3);
      await playedAgo('keep-me', const Duration(days: 30), times: 2);

      expect(await history.listenAgainShas(exclude: {'skip-me'}), ['keep-me']);
    });
  });

  group('play stamps', () {
    test(
      'are finished plays with the time they started, newest first',
      () async {
        await playedAgo('old', const Duration(days: 20));
        await playedAgo('new', const Duration(hours: 2));

        final stamps = await history.playStamps();
        expect(stamps.map((s) => s.sha), ['new', 'old']);
        expect(
          DateTime.now().difference(stamps.first.at).inMinutes,
          inInclusiveRange(119, 121),
        );
      },
    );

    test('leave out skips', () async {
      player.loadTrack(_track('skipped', durationMs: 120000));
      player.listenFor(const Duration(seconds: 10));
      history.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await playedAgo('kept', const Duration(hours: 1));

      expect((await history.playStamps()).map((s) => s.sha), ['kept']);
    });

    test('stop at the window and the cap', () async {
      await playedAgo('recent', const Duration(days: 3));
      await playedAgo('ancient', const Duration(days: 500));
      expect((await history.playStamps()).map((s) => s.sha), ['recent']);
      expect(
        (await history.playStamps(within: const Duration(days: 900))).length,
        2,
      );

      await playedAgo('many', const Duration(hours: 5), times: 5);
      expect((await history.playStamps(limit: 3)).length, 3);
    });
  });

  test('clearing forgets every event, not just hides them', () async {
    // A history the user asked to be rid of that is still on disk is not
    // cleared, it is hidden.
    await playThrough('a', 3);
    expect(await events(), isNotEmpty);

    await history.clear();

    expect(await events(), isEmpty);
    expect(await history.playCounts(), isEmpty);
    expect(await history.recentShas(), isEmpty);
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
