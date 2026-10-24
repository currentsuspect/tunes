import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/audio/tune_player.dart';
import 'package:tunes/domain/manifest.dart';
import 'package:tunes/features/lyrics/lyrics_sheet.dart';

class _StubPlayer extends TunePlayer {
  @override
  List<ManifestTrack> get queue => const [];
  @override
  int get index => -1;
  @override
  bool get playing => false;
  @override
  Duration get position => Duration.zero;
  @override
  Duration get duration => const Duration(minutes: 3);
  @override
  ManifestTrack? get current => null;
  @override
  PlaybackRepeat get repeat => PlaybackRepeat.off;
  @override
  bool get shuffle => false;

  Duration? sought;

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
  void seek(Duration target) => sought = target;
  @override
  void stop() {}
  @override
  void setRepeat(PlaybackRepeat mode) {}
  @override
  void setShuffle(bool on) {}
}

ManifestTrack _track({String? lyrics}) => ManifestTrack(
  sha: 'a' * 64,
  size: 1000,
  codec: 'flac',
  sampleRate: 44100,
  channels: 2,
  bitrate: 900000,
  durationMs: 180000,
  title: 'THAT GUY',
  artist: 'Tyler, The Creator',
  album: 'CHERRY BOMB',
  year: null,
  artSha: null,
  releaseId: null,
  trackNumber: null,
  discNumber: null,
  lyrics: lyrics,
);

Future<void> _pump(
  WidgetTester tester, {
  String? lyrics,
  required Future<void> Function(ManifestTrack, String) onSave,
  _StubPlayer? player,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LyricsSheet(
          track: _track(lyrics: lyrics),
          player: player ?? _StubPlayer(),
          onSave: onSave,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The lyrics options live behind one menu rather than a row of buttons.
Future<void> _menu(WidgetTester tester, String item) async {
  await tester.tap(find.byTooltip('Lyrics options'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Lyrics options'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('plain text lyrics are shown, not a blank sheet', (tester) async {
    // The regression: the view read `lrc.lines`, which holds only *timed*
    // lines, so plain lyrics parsed into `untimed` and rendered as nothing.
    await _pump(
      tester,
      lyrics: 'first line\nsecond line',
      onSave: (_, _) async {},
    );
    expect(find.textContaining('first line'), findsOneWidget);
    expect(find.textContaining('second line'), findsOneWidget);
    expect(find.text('No lyrics yet'), findsNothing);
  });

  testWidgets('saved lyrics replace the empty state without reopening', (
    tester,
  ) async {
    // The regression: _lrc was parsed once in initState and never again, so
    // pasting lyrics into a track that had none left "No lyrics yet" up.
    await _pump(tester, onSave: (_, _) async {});
    expect(find.text('No lyrics yet'), findsOneWidget);

    await tester.tap(find.text('Add lyrics'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'a brand new line');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('No lyrics yet'), findsNothing);
    expect(find.textContaining('a brand new line'), findsOneWidget);
  });

  testWidgets('re-opening the editor shows the saved text, not the old one', (
    tester,
  ) async {
    // The data-loss regression: the editor reloaded from widget.track.lyrics,
    // which the parent never refreshes. Saving a second time wrote the
    // pre-edit text back over the user's work.
    final saved = <String>[];
    await _pump(
      tester,
      lyrics: 'original words',
      onSave: (_, s) async => saved.add(s),
    );

    await _menu(tester, 'Edit lyrics');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'replacement words');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    await _menu(tester, 'Edit lyrics');
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'replacement words');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, ['replacement words', 'replacement words']);
  });

  testWidgets('cancel leaves the stored lyrics alone', (tester) async {
    final saved = <String>[];
    await _pump(
      tester,
      lyrics: 'keep me',
      onSave: (_, s) async => saved.add(s),
    );

    await _menu(tester, 'Edit lyrics');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'discard me');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(saved, isEmpty);
    expect(find.textContaining('keep me'), findsOneWidget);
    expect(find.textContaining('discard me'), findsNothing);
  });

  testWidgets('a failed save keeps the editor open with the text intact', (
    tester,
  ) async {
    // Dropping back to the view would look identical to a successful save
    // while losing everything the user typed.
    await _pump(tester, onSave: (_, _) async => throw StateError('disk full'));
    await tester.tap(find.text('Add lyrics'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'hard-won words');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'hard-won words');
    expect(find.textContaining('Could not save'), findsOneWidget);
  });

  testWidgets('says whether the lyrics carry timing', (tester) async {
    await _pump(tester, lyrics: 'no timestamps here', onSave: (_, _) async {});
    await _openMenu(tester);
    expect(find.text('PLAIN TEXT'), findsOneWidget);
    expect(find.text('SYNCED'), findsNothing);
  });

  testWidgets('timed lyrics are marked synced and seek on tap', (tester) async {
    final player = _StubPlayer();
    await _pump(
      tester,
      lyrics: '[00:10.00]ten seconds in\n[00:20.00]twenty seconds in',
      onSave: (_, _) async {},
      player: player,
    );
    await _openMenu(tester);
    expect(find.text('SYNCED'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5)); // close the menu
    await tester.pumpAndSettle();

    await tester.tap(find.text('twenty seconds in'));
    await tester.pumpAndSettle();
    expect(player.sought, const Duration(seconds: 20));
  });

  testWidgets('saving trims stray whitespace rather than storing it', (
    tester,
  ) async {
    final saved = <String>[];
    await _pump(tester, onSave: (_, s) async => saved.add(s));
    await tester.tap(find.text('Add lyrics'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '\n\n  words  \n\n');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, ['words']);
  });

  testWidgets('a part-synced lyric still shows the lines that are not timed', (
    tester,
  ) async {
    // The regression: the view rendered lrc.lines only, so timing one line of
    // a forty-line lyric hid the other thirty-nine. The words were still
    // stored -- the screen just looked like the save had eaten them.
    await _pump(
      tester,
      lyrics: '[00:12.34]first line\nsecond line\nthird line',
      onSave: (_, _) async {},
    );
    expect(find.textContaining('first line'), findsOneWidget);
    expect(find.textContaining('second line'), findsOneWidget);
    expect(find.textContaining('third line'), findsOneWidget);
  });

  testWidgets('a part-synced lyric is still reported as synced', (
    tester,
  ) async {
    await _pump(
      tester,
      lyrics: '[00:12.34]first line\nsecond line',
      onSave: (_, _) async {},
    );
    await _openMenu(tester);
    expect(find.text('SYNCED'), findsOneWidget);
  });

  testWidgets('follows the player to the next song', (tester) async {
    final player = _MovingPlayer(_track(lyrics: 'first song words'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LyricsSheet(
            track: player.current!,
            player: player,
            onSave: (_, _) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('first song words'), findsOneWidget);

    player.moveTo(
      _track(lyrics: 'second song words')
          .copyWithTitle('NEXT ONE', sha: 'b' * 64),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('second song words'), findsOneWidget);
    expect(find.textContaining('first song words'), findsNothing);
    expect(find.text('NEXT ONE'), findsOneWidget);
  });

  testWidgets('a backing vocal sits on the right, the lead on the left', (
    tester,
  ) async {
    await _pump(
      tester,
      lyrics: '[00:10.00]lead line here\n[00:12.00](backing echo)',
      onSave: (_, _) async {},
    );
    final lead = tester.getTopLeft(find.text('lead line here')).dx;
    final echo = tester.getTopRight(find.text('(backing echo)')).dx;
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(lead, lessThan(width / 4));
    expect(echo, greaterThan(width * 3 / 4));
  });

  testWidgets(
    'a saved lyric shows at once, even if the player never refreshes',
    (tester) async {
      await _pump(tester, onSave: (_, _) async {});
      await tester.tap(find.text('Add lyrics'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'brand new words');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('brand new words'), findsOneWidget);
    },
  );

  testWidgets('a line is shared as its moment, first word to last', (
    tester,
  ) async {
    const lyrics =
        '[00:01.00]<00:01.00>hello <00:02.50>world<00:03.10>\n'
        '[00:08.00]<00:08.00>next <00:08.50>line';
    final cuts = <(Duration, Duration, bool)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LyricsSheet(
            track: _track(lyrics: lyrics),
            player: _StubPlayer(),
            onSave: (_, _) async {},
            clip: (sha, from, to, {card}) async {
              cuts.add((from, to, card != null));
              return null;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.text('hello '));
    await tester.pumpAndSettle();
    expect(find.text('Share this moment'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Share this moment'));
      // The card is drawn off screen and captured before the cut is asked for.
      for (var i = 0; i < 20 && cuts.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    // 200 ms before "hello", 400 ms after the end of "world" (3.10 s).
    expect(cuts.single.$1, const Duration(milliseconds: 800));
    expect(cuts.single.$2, const Duration(milliseconds: 3500));
    expect(cuts.single.$3, isTrue, reason: 'the lyric card goes with it');
  });

  group('word timing in the sheet', () {
    const lyrics =
        '[00:01.00]<00:01.00>hello <00:02.50>world<00:03.10>\n'
        '[00:08.00]<00:08.00>next <00:08.50>line';

    testWidgets('tapping a word jumps to that word', (tester) async {
      final player = _StubPlayer();
      await _pump(
        tester,
        lyrics: lyrics,
        onSave: (_, _) async {},
        player: player,
      );
      await tester.tap(find.text('world'));
      await tester.pump();
      expect(player.sought, const Duration(milliseconds: 2500));
    });

    testWidgets(
      'a line can be looped, start of its first word to end of its last',
      (tester) async {
        final player = _TimedPlayer();
        await _pump(
          tester,
          lyrics: lyrics,
          onSave: (_, _) async {},
          player: player,
        );
        await tester.longPress(find.text('hello '));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Loop this line'));
        await tester.pumpAndSettle();
        // 150 ms before "hello", so its first sound is heard whole.
        expect(player.sought, const Duration(milliseconds: 850));
        expect(find.text('Looping this line · Stop'), findsOneWidget);

        // Past the end of "world" (3.10 s, plus a breath): back to the start.
        player.sought = null;
        player.moveTo(const Duration(milliseconds: 3400));
        await tester.pump(const Duration(milliseconds: 50));
        expect(player.sought, const Duration(milliseconds: 850));

        await tester.tap(find.text('Looping this line · Stop'));
        await tester.pumpAndSettle();
        player.sought = null;
        player.moveTo(const Duration(milliseconds: 3400));
        await tester.pump(const Duration(milliseconds: 50));
        expect(player.sought, isNull);
      },
    );
  });
}

/// A player whose current track can be moved, as playing on does.
class _MovingPlayer extends _StubPlayer {
  _MovingPlayer(this._now);
  ManifestTrack _now;
  @override
  ManifestTrack? get current => _now;
  void moveTo(ManifestTrack t) {
    _now = t;
    notifyListeners();
  }
}

extension on ManifestTrack {
  ManifestTrack copyWithTitle(String title, {required String sha}) =>
      ManifestTrack(
        sha: sha,
        size: size,
        codec: codec,
        sampleRate: sampleRate,
        channels: channels,
        bitrate: bitrate,
        durationMs: durationMs,
        title: title,
        artist: artist,
        album: album,
        year: year,
        artSha: artSha,
        releaseId: releaseId,
        trackNumber: trackNumber,
        discNumber: discNumber,
        lyrics: lyrics,
      );
}

class _TimedPlayer extends _StubPlayer {
  Duration _pos = Duration.zero;

  @override
  Duration get position => _pos;

  @override
  void seek(Duration target) {
    super.seek(target);
    _pos = target;
    notifyListeners();
  }

  void moveTo(Duration to) {
    _pos = to;
    notifyListeners();
  }
}
