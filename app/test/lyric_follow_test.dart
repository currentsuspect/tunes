import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/audio/playhead_clock.dart';
import 'package:tunes/core/audio/tune_player.dart';
import 'package:tunes/core/lyrics/lrc_parser.dart';
import 'package:tunes/domain/manifest.dart';
import 'package:tunes/features/lyrics/lyric_follow.dart';
import 'package:tunes/features/lyrics/lyrics_sheet.dart';
import 'package:tunes/features/now_playing/lyric_preview.dart';

/// Minimal fake: only position matters for follow behavior.
class _FakePlayer extends TunePlayer {
  Duration _position = Duration.zero;
  int seekCalls = 0;

  void setPosition(Duration d) {
    _position = d;
    notifyListeners();
  }

  @override
  List<ManifestTrack> get queue => const [];

  @override
  int get index => -1;

  @override
  bool get playing => true;

  @override
  Duration get position => _position;

  @override
  Duration get duration => const Duration(seconds: 120);

  @override
  ManifestTrack? get current => null;

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
  void seek(Duration target) {
    seekCalls += 1;
    setPosition(target);
  }

  @override
  void stop() {}

  @override
  void setRepeat(PlaybackRepeat mode) {}

  @override
  void setShuffle(bool on) {}
}

ManifestTrack _trackWithLyrics(String lyrics) => ManifestTrack(
  sha: 'l' * 64,
  size: 1000,
  codec: 'flac',
  sampleRate: 44100,
  channels: 2,
  bitrate: 950000,
  durationMs: 120000,
  title: 'Follow Test',
  artist: 'Artist',
  album: 'Album',
  year: null,
  artSha: null,
  releaseId: null,
  trackNumber: null,
  discNumber: null,
  lyrics: lyrics,
);

const _previewLrc =
    '[00:00.00]Alpha\n'
    '[00:10.00]Bravo\n'
    '[00:20.00]Charlie\n'
    '[00:30.00]Delta\n'
    '[00:40.00]Echo';

String _longLrc(int n) => List.generate(n, (i) {
  final s = i * 5;
  final mm = (s ~/ 60).toString().padLeft(2, '0');
  final ss = (s % 60).toString().padLeft(2, '0');
  return '[$mm:$ss.00]Line $i';
}).join('\n');

void main() {
  group('lyricActiveIndex', () {
    test('resolves positions to line indices', () {
      final lrc = LrcParser.parse('[00:05.00]A\n[00:10.00]B\n[00:15.00]C');
      expect(lyricActiveIndex(lrc, Duration.zero), isNull);
      expect(lyricActiveIndex(lrc, const Duration(seconds: 5)), 0);
      expect(lyricActiveIndex(lrc, const Duration(seconds: 12)), 1);
      expect(lyricActiveIndex(lrc, const Duration(seconds: 99)), 2);
    });

    test('null without timed lines', () {
      expect(
        lyricActiveIndex(LrcParser.parse(''), const Duration(seconds: 5)),
        isNull,
      );
      expect(
        lyricActiveIndex(
          LrcParser.parse('just some words'),
          const Duration(seconds: 5),
        ),
        isNull,
      );
    });
  });

  group('LyricFollowController', () {
    test('notifies only on active-index change, not every tick', () {
      final player = _FakePlayer();
      final lrc = LrcParser.parse('[00:05.00]A\n[00:10.00]B');
      final c = LyricFollowController(player: player, lrc: lrc);
      var calls = 0;
      c.addListener(() => calls += 1);

      player.setPosition(const Duration(seconds: 1));
      player.setPosition(const Duration(seconds: 2));
      expect(calls, 0);
      expect(c.activeIndex, isNull);

      player.setPosition(const Duration(seconds: 6));
      expect(calls, 1);
      expect(c.activeIndex, 0);

      player.setPosition(const Duration(seconds: 7));
      expect(calls, 1);

      player.setPosition(const Duration(seconds: 11));
      expect(calls, 2);
      expect(c.activeIndex, 1);

      c.dispose();
    });

    test('manual scroll pauses; new line or resume re-engages', () {
      final player = _FakePlayer();
      final lrc = LrcParser.parse('[00:05.00]A\n[00:10.00]B');
      player.setPosition(const Duration(seconds: 6));
      final c = LyricFollowController(player: player, lrc: lrc);
      expect(c.following, isTrue);

      c.userScrolled();
      expect(c.following, isFalse);
      // Same-line ticks do not resume.
      player.setPosition(const Duration(seconds: 7));
      expect(c.following, isFalse);

      // Playback reaching a new line resumes on its own.
      player.setPosition(const Duration(seconds: 11));
      expect(c.following, isTrue);

      c.userScrolled();
      c.resumeFollowing();
      expect(c.following, isTrue);

      c.dispose();
    });

    test('updateLyrics re-anchors and resumes', () {
      final player = _FakePlayer();
      player.setPosition(const Duration(seconds: 12));
      final c = LyricFollowController(
        player: player,
        lrc: LrcParser.parse('[00:05.00]A\n[00:10.00]B'),
      );
      expect(c.activeIndex, 1);
      c.userScrolled();
      c.updateLyrics(LrcParser.parse('[00:00.00]X\n[00:20.00]Y'));
      expect(c.following, isTrue);
      expect(c.activeIndex, 0);
      c.dispose();
    });
  });

  group('word-level lookup (guarded)', () {
    test('never throws; degrades to null without word timing', () {
      final plain = LrcParser.parse('[00:05.00]A\n[00:10.00]B');
      expect(lyricWordParts(plain, 0), isNull);
      expect(
        lyricActiveWordIndex(plain, 0, const Duration(seconds: 6)),
        isNull,
      );
      // Out-of-range indices are null, never an error.
      expect(
        lyricActiveWordIndex(plain, 99, const Duration(seconds: 6)),
        isNull,
      );
      expect(lyricWordParts(plain, -1), isNull);
    });

    test('tracks word starts when the parser provides word timing', () {
      final lrc = LrcParser.parse('[00:10.00]Hello [00:11.00]world');
      final parts = lyricWordParts(lrc, 0);
      if (parts == null) {
        // Line-level parser: graceful fallback.
        expect(
          lyricActiveWordIndex(
            lrc,
            0,
            const Duration(seconds: 10, milliseconds: 500),
          ),
          isNull,
        );
        return;
      }
      // Word timing present: active word follows the playhead.
      expect(lyricActiveWordIndex(lrc, 0, parts.first.start), 0);
      expect(lyricActiveWordIndex(lrc, 0, parts.last.start), parts.length - 1);
      expect(
        lyricActiveWordIndex(
          lrc,
          0,
          parts.first.start - const Duration(milliseconds: 1),
        ),
        isNull,
      );
    });
  });

  group('LyricPreview widget', () {
    testWidgets('a long lyric line is split in two, at a readable size', (
      tester,
    ) async {
      // Real line-synced lyrics are routinely wider than a phone --
      // "Number two (Hahahaha), only speak in glory (Yeah)" is an ordinary
      // line, not a pathological one. It used to arrive ellipsised, then
      // shrunk to an unreadable size (the FittedBox gave the text unbounded
      // width, so it never wrapped). It is now two lines of its own.
      const long =
          '[00:00.00]Number two (Hahahaha), only speak in glory (Yeah)\n'
          '[00:30.00]Leave your baggage at home (None of that deep shit)';
      final player = _FakePlayer();
      player.setPosition(Duration.zero);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: LyricPreview(lyrics: long, player: player, onOpen: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final active = tester.widget<Text>(find.text('Number two (Hahahaha),'));
      expect(active.maxLines, greaterThan(1));
      expect(active.overflow, isNot(TextOverflow.ellipsis));
      // The rest of the line is next, not squeezed into the same row.
      expect(find.text('only speak in glory (Yeah)'), findsOneWidget);
      // Drawn at its own size: the FittedBox above it does not scale it down.
      final fitted = tester.getSize(
        find.ancestor(
          of: find.text('Number two (Hahahaha),'),
          matching: find.byType(FittedBox),
        ),
      );
      final text = tester.getSize(find.text('Number two (Hahahaha),'));
      expect(text.width, lessThanOrEqualTo(fitted.width + 0.5));
      expect(
        tester.getRect(find.text('Number two (Hahahaha),')).height,
        greaterThan(18),
      );
    });

    testWidgets('follows the active line as playback advances', (tester) async {
      final player = _FakePlayer();
      player.setPosition(Duration.zero);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LyricPreview(
              lyrics: _previewLrc,
              player: player,
              onOpen: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Active Alpha: window shows Alpha + Bravo, not Delta.
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Bravo'), findsOneWidget);
      expect(find.text('Delta'), findsNothing);

      player.setPosition(const Duration(seconds: 31));
      await tester.pumpAndSettle();

      // Active Delta: window shows Charlie + Delta + Echo, not Alpha.
      expect(find.text('Delta'), findsOneWidget);
      expect(find.text('Charlie'), findsOneWidget);
      expect(find.text('Echo'), findsOneWidget);
      expect(find.text('Alpha'), findsNothing);
    });

    testWidgets('tap opens the full lyrics', (tester) async {
      var opened = false;
      final player = _FakePlayer();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LyricPreview(
              lyrics: _previewLrc,
              player: player,
              onOpen: () => opened = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      expect(opened, isTrue);
    });

    testWidgets('no-lyrics state invites adding', (tester) async {
      final player = _FakePlayer();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LyricPreview(lyrics: null, player: player, onOpen: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No lyrics yet. Tap to add them.'), findsOneWidget);
    });
  });

  group('LyricsSheet follow', () {
    // The sheet builds a PlayheadClock for the word sweep, and a ticking clock
    // schedules a frame every frame while playing -- so pumpAndSettle here
    // would never finish. Off, the clock still reports every position the
    // player gives it; it just stops interpolating between them, which is the
    // part these tests could not observe anyway.
    //
    // Only this group needs it: the preview group above builds a follow
    // controller without a clock.
    setUp(() => PlayheadClock.ticking = false);
    tearDown(() => PlayheadClock.ticking = true);

    Future<_FakePlayer> pumpSheet(
      WidgetTester tester, {
      Duration position = const Duration(seconds: 62),
    }) async {
      final player = _FakePlayer();
      player.setPosition(position); // Line 12 at 60s.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LyricsSheet(
              track: _trackWithLyrics(_longLrc(20)),
              player: player,
              onSave: (_, _) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return player;
    }

    double pixels(WidgetTester tester) => tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;

    void jumpTo(WidgetTester tester, double px) {
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(px);
    }

    /// A real user drag. On a mid-extent sheet the drag itself is
    /// absorbed expanding the sheet, but ScrollStart still carries drag
    /// details, which is what pauses following.
    Future<void> smallDrag(WidgetTester tester) async {
      final center = tester.getCenter(find.byType(ListView));
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pumpAndSettle();
    }

    int pillCount(WidgetTester tester) =>
        find.text('Back to current line').evaluate().length;

    testWidgets('manual drag pauses following and shows recenter pill', (
      tester,
    ) async {
      await pumpSheet(tester);
      expect(pillCount(tester), 0);

      // Park away from the active line first: programmatic jumps never
      // pause following, so the drag below is what pauses it.
      jumpTo(tester, 0);
      await tester.pumpAndSettle();
      expect(pillCount(tester), 0);

      await smallDrag(tester);
      expect(pixels(tester), 0);
      expect(pillCount(tester), 1);
    });

    testWidgets('scrolling back to the active line resumes following', (
      tester,
    ) async {
      await pumpSheet(tester);
      jumpTo(tester, 0);
      await tester.pumpAndSettle();
      await smallDrag(tester);
      expect(pillCount(tester), 1);

      jumpTo(tester, 300);
      await tester.pumpAndSettle();
      expect(pillCount(tester), 0);
    });

    testWidgets('playback reaching a new line resumes following', (
      tester,
    ) async {
      final player = await pumpSheet(tester);
      jumpTo(tester, 0);
      await tester.pumpAndSettle();
      await smallDrag(tester);
      expect(pillCount(tester), 1);

      player.setPosition(const Duration(seconds: 77)); // Line 15 at 75s.
      await tester.pumpAndSettle();
      expect(pillCount(tester), 0);
      expect(find.text('Line 15'), findsOneWidget);
      expect(pixels(tester), greaterThan(300));
    });

    testWidgets('opening late in a song lands on the line being sung', (
      tester,
    ) async {
      // Line 18 of 20 is nowhere near the first screenful, so the lazy list has
      // not built it when the sheet opens. It used to stay at the top, with
      // the music many lines ahead of the words.
      await pumpSheet(tester, position: const Duration(seconds: 92));
      expect(find.text('Line 18'), findsOneWidget);
      expect(pixels(tester), greaterThan(300));
    });

    testWidgets('recenter pill scrolls back to the active line', (
      tester,
    ) async {
      await pumpSheet(tester);
      jumpTo(tester, 0);
      await tester.pumpAndSettle();
      await smallDrag(tester);
      expect(pillCount(tester), 1);

      await tester.tap(find.text('Back to current line'));
      await tester.pumpAndSettle();
      expect(pillCount(tester), 0);
      expect(pixels(tester), greaterThan(200));
    });
  });
}
