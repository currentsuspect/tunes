import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/ui/shelf_widgets.dart';
import 'package:tunes/domain/collection_gaps.dart';
import 'package:tunes/domain/discography.dart';
import 'package:tunes/domain/manifest.dart';
import 'package:tunes/domain/threads.dart';
import 'package:tunes/features/discover/discover_view.dart';

MissingRelease _missing(
  String artist,
  String title, {
  int artistTracks = 10,
  int? owned,
  int? total,
}) => MissingRelease(
  id: '$artist-$title',
  title: title,
  artist: artist,
  type: 'Album',
  year: '2024',
  artistTracks: artistTracks,
  artistOwnedReleases: owned,
  artistTotalReleases: total,
);

void main() {
  Future<void> pump(
    WidgetTester tester,
    List<MissingRelease> missing, {
    Map<String, int> plays = const {},
    bool offline = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DiscoverView(
          gaps: collectionGaps(missing: missing, plays: plays),
          threads: const [],
          offline: offline,
          artUrlFor: (sha) => 'http://example.invalid/art/$sha',
          onArtistTap: (_) {},
          onPlay: (_, _) {},
          hasHistory: plays.isNotEmpty,
        ),
      ),
    ),
  );

  testWidgets('states the size of the gap in the header', (tester) async {
    await pump(tester, [
      _missing('Yeat', 'Lyfë'),
      _missing('Yeat', '2093'),
      _missing('Nemzzz', 'Verses'),
    ]);
    expect(find.text('Complete your collection'), findsOneWidget);
    expect(find.textContaining('3 releases by 2 artists'), findsOneWidget);
  });

  testWidgets('shows completion only when the daemon reported it', (
    tester,
  ) async {
    await pump(tester, [_missing('Yeat', 'Lyfë', owned: 5, total: 18)]);
    expect(find.textContaining('5 of 18 releases'), findsOneWidget);
    expect(find.byType(ProgressRing), findsOneWidget);
  });

  testWidgets('draws no progress ring when completion is unknown', (
    tester,
  ) async {
    // An older daemon sends no counts. A ring at zero would claim the library
    // holds none of this act, which is a different statement from silence.
    await pump(tester, [_missing('Yeat', 'Lyfë')]);
    expect(find.byType(ProgressRing), findsNothing);
    // The whole subtitle, not a fragment of it: the point is that no
    // "0 of something" clause was invented to fill the space.
    expect(find.text('1 missing'), findsOneWidget);
  });

  testWidgets('says plays only once something has been played', (tester) async {
    await pump(tester, [_missing('Yeat', 'Lyfë')]);
    expect(find.textContaining('play'), findsNothing);

    await pump(tester, [_missing('Yeat', 'Lyfë')], plays: {'Yeat': 7});
    expect(find.textContaining('7 plays'), findsOneWidget);
    expect(
      find.textContaining('Ordered by what you actually play'),
      findsOneWidget,
    );
  });

  testWidgets('offline says why it is empty rather than nothing', (
    tester,
  ) async {
    await pump(tester, const [], offline: true);
    expect(find.text('Nothing to compare against'), findsOneWidget);
  });

  testWidgets('an empty list online reads as not yet, not as none', (
    tester,
  ) async {
    await pump(tester, const []);
    expect(find.text('Nothing missing yet'), findsOneWidget);
  });

  ManifestTrack track(
    String sha, {
    String artist = 'Yeat',
    String title = 'x',
    List<String> featured = const [],
  }) => ManifestTrack(
    sha: sha,
    size: 1,
    codec: 'flac',
    sampleRate: 44100,
    channels: 2,
    bitrate: 1000,
    durationMs: 180000,
    title: title,
    artist: artist,
    album: 'album',
    year: null,
    artSha: null,
    releaseId: null,
    trackNumber: null,
    discNumber: null,
    primaryArtist: artist,
    featured: featured,
  );

  testWidgets('thread rails render above the gaps and play from a tap', (
    tester,
  ) async {
    final library = [
      track('y1', title: 'One'),
      track('y2', title: 'Two', featured: ['Ken']),
      track('y3', title: 'Three'),
      track('k1', artist: 'Ken', title: 'Four', featured: ['Yeat']),
      track('k2', artist: 'Ken', title: 'Five', featured: ['Yeat']),
    ];
    final threads = followThreads(library: library, plays: {'y1': 5});
    expect(threads, isNotEmpty);
    var playedFrom = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiscoverView(
            gaps: const [],
            threads: threads,
            offline: false,
            artUrlFor: (sha) => 'http://example.invalid/art/$sha',
            onArtistTap: (_) {},
            onPlay: (_, i) => playedFrom = i,
            hasHistory: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Follow the thread'), findsOneWidget);
    // The shelf's Play sits beside its heading now, so the card sits a
    // little lower than the 600 px test screen shows.
    await tester.ensureVisible(find.text('Two').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Two').first);
    await tester.pumpAndSettle();
    expect(playedFrom, greaterThanOrEqualTo(0));
  });
}
