import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/data/database.dart';
import 'package:tunes/core/data/download_store.dart';
import 'package:tunes/core/data/manifest_store.dart';
import 'package:tunes/core/nav/nav_controller.dart';
import 'package:tunes/domain/manifest.dart';
import 'package:tunes/features/now_playing/now_playing_page.dart';

import 'widget_test.dart' show FakeTunePlayer;

// 25 Oct: the shell keeps Now Playing for the whole session, built with the
// library as it was when it first opened. A song got since (Vax's B4VXN) was
// not in that copy, so its album could not be found and the tap did nothing,
// and its artist showed 0 songs. The page now asks for the library as it is.

final _trinity = ManifestTrack(
  sha: 't' * 64,
  size: 1,
  codec: 'flac',
  sampleRate: 44100,
  channels: 2,
  bitrate: 1000,
  durationMs: 179000,
  title: 'Trinity',
  artist: 'Vax',
  album: 'B4VXN',
  year: '2026',
  artSha: null,
  releaseId: 'rel-b4vxn',
  trackNumber: 6,
  discNumber: 1,
  primaryArtist: 'Vax',
  featured: const [],
);

const _b4vxn = ManifestRelease(
  id: 'rel-b4vxn',
  title: 'B4VXN',
  artist: 'Vax',
  year: '2026',
  artSha: null,
  type: 'album',
  totalTracks: 6,
  trackShas: [],
);

void main() {
  late Directory tmp;
  late DownloadStore store;
  late TunesDatabase db;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nowplaying');
    store = DownloadStore(tmp);
    db = TunesDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  testWidgets('the album opens from Now Playing though it arrived after the '
      'page was built', (tester) async {
    final nav = NavController();
    final player = FakeTunePlayer()..playQueue([_trinity], 0);
    // What the page was built with: the library before B4VXN was got.
    const before = TunesManifest(tracks: [], releases: []);
    final now = TunesManifest(tracks: [_trinity], releases: const [_b4vxn]);
    await tester.pumpWidget(
      MaterialApp(
        home: NavScope(
          controller: nav,
          child: NowPlayingPage(
            player: player,
            manifest: before,
            libraryNow: () => now,
            store: store,
            downloading: const {},
            onDownload: (_) {},
            offline: false,
            artUrlFor: (s) => 'http://test/art/$s',
            manifestStore: ManifestStore(db),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // The album's name under the artist opens it, as the artist's opens theirs.
    await tester.tap(find.text('B4VXN').first);
    await tester.pump();
    expect(nav.current.key, TunesPanels.album('rel-b4vxn'));
  });
}
