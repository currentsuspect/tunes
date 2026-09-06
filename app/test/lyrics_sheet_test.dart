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
  required Future<void> Function(String) onSave,
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

void main() {
  testWidgets('plain text lyrics are shown, not a blank sheet', (tester) async {
    // The regression: the view read `lrc.lines`, which holds only *timed*
    // lines, so plain lyrics parsed into `untimed` and rendered as nothing.
    await _pump(
      tester,
      lyrics: 'first line\nsecond line',
      onSave: (_) async {},
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
    await _pump(tester, onSave: (_) async {});
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
      onSave: (s) async => saved.add(s),
    );

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'replacement words');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'replacement words');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, ['replacement words', 'replacement words']);
  });

  testWidgets('cancel leaves the stored lyrics alone', (tester) async {
    final saved = <String>[];
    await _pump(tester, lyrics: 'keep me', onSave: (s) async => saved.add(s));

    await tester.tap(find.text('Edit'));
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
    await _pump(tester, onSave: (_) async => throw StateError('disk full'));
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
    await _pump(tester, lyrics: 'no timestamps here', onSave: (_) async {});
    expect(find.text('Plain text'), findsOneWidget);
    expect(find.text('Synced'), findsNothing);
  });

  testWidgets('timed lyrics are marked synced and seek on tap', (tester) async {
    final player = _StubPlayer();
    await _pump(
      tester,
      lyrics: '[00:10.00]ten seconds in\n[00:20.00]twenty seconds in',
      onSave: (_) async {},
      player: player,
    );
    expect(find.text('Synced'), findsOneWidget);

    await tester.tap(find.text('twenty seconds in'));
    await tester.pumpAndSettle();
    expect(player.sought, const Duration(seconds: 20));
  });

  testWidgets('saving trims stray whitespace rather than storing it', (
    tester,
  ) async {
    final saved = <String>[];
    await _pump(tester, onSave: (s) async => saved.add(s));
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
      onSave: (_) async {},
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
      onSave: (_) async {},
    );
    expect(find.text('Synced'), findsOneWidget);
  });
}
