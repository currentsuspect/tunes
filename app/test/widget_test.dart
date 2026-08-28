import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/audio/tune_player.dart';
import 'package:tunes/core/data/download_store.dart';
import 'package:tunes/core/data/reachability.dart';
import 'package:tunes/core/net/tunes_client.dart';
import 'package:tunes/domain/manifest.dart';
import 'package:tunes/domain/discography.dart';
import 'package:tunes/features/album/album_page.dart';
import 'package:tunes/features/player/mini_player_bar.dart';
import 'package:tunes/main.dart';

class _FakeClient implements TunesClient {
  _FakeClient(this.result, {this.onSearch, this.onDiscography});

  final Future<TunesManifest> Function() result;
  final Future<SearchResults> Function(String q)? onSearch;
  final Future<ArtistDiscography> Function(String artist)? onDiscography;

  @override
  String get baseUrl => 'http://fake:4780';

  @override
  Future<TunesManifest> fetchManifest() => result();

  @override
  Future<SearchResults> search(String q) {
    final custom = onSearch;
    if (custom != null) return custom(q);
    return result().then(
      (m) => SearchResults(
        tracks: m.tracks
            .where(
              (t) =>
                  t.title.toLowerCase().contains(q.toLowerCase()) ||
                  t.artist.toLowerCase().contains(q.toLowerCase()) ||
                  t.album.toLowerCase().contains(q.toLowerCase()),
            )
            .toList(),
        releases: m.releases,
        artists: m.artists,
      ),
    );
  }

  @override
  Future<ArtistDiscography> discography(String artist) =>
      onDiscography?.call(artist) ??
      Future.value(
        ArtistDiscography(
          artist: artist,
          mbid: null,
          fetchedAt: null,
          groups: const [],
        ),
      );

  @override
  Future<bool> ping() async => true;

  @override
  Future<void> downloadTrack(
    String sha,
    String path, {
    void Function(int received, int total)? onProgress,
  }) async {
    File(path).parent.createSync(recursive: true);
    File(path).writeAsBytesSync(List.filled(100, 1));
  }
}

class FakeTunePlayer extends TunePlayer {
  List<ManifestTrack> _queue = const [];
  int _index = -1;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

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

  int playQueueCalls = 0;
  int toggleCalls = 0;
  int seekCalls = 0;
  int nextCalls = 0;
  int previousCalls = 0;
  int playAtCalls = 0;
  int playCalls = 0;
  int pauseCalls = 0;

  @override
  void toggle() {
    toggleCalls += 1;
    _playing = !_playing;
    notifyListeners();
  }

  @override
  void play() {
    playCalls += 1;
    _playing = true;
    notifyListeners();
  }

  @override
  void pause() {
    pauseCalls += 1;
    _playing = false;
    notifyListeners();
  }

  @override
  void next() {
    nextCalls += 1;
    if (_index < _queue.length - 1) {
      _index += 1;
      notifyListeners();
    }
  }

  @override
  void previous() {
    previousCalls += 1;
    if (_index > 0) {
      _index -= 1;
      notifyListeners();
    }
  }

  @override
  void playAt(int index) {
    playAtCalls += 1;
    _index = index;
    _playing = true;
    notifyListeners();
  }

  @override
  void playQueue(List<ManifestTrack> tracks, int startIndex) {
    playQueueCalls += 1;
    _queue = List.of(tracks);
    _index = startIndex;
    _playing = true;
    _position = Duration.zero;
    final ms = tracks[startIndex].durationMs;
    _duration = ms != null ? Duration(milliseconds: ms) : Duration.zero;
    notifyListeners();
  }

  @override
  void seek(Duration target) {
    seekCalls += 1;
    _position = target;
    notifyListeners();
  }

  int stopCalls = 0;

  @override
  void stop() {
    stopCalls += 1;
    _queue = const [];
    _index = -1;
    _playing = false;
    notifyListeners();
  }
}

ManifestTrack _track(
  String title,
  String codec,
  int bitrate, {
  String artist = 'Artist',
  String album = 'Album',
  String? sha,
  String? releaseId,
}) => ManifestTrack(
  sha: sha ?? (title == 'Bassline' ? 'a' * 64 : 'b' * 64),
  size: 1000,
  codec: codec,
  sampleRate: 44100,
  channels: 2,
  bitrate: bitrate,
  durationMs: 125000,
  title: title,
  artist: artist,
  album: album,
  year: null,
  artSha: null,
  releaseId: releaseId ?? (title == 'Bassline' ? 'rel-1' : 'rel-2'),
  trackNumber: null,
  discNumber: null,
);

List<ManifestTrack> _library() => [
  _track('Bassline', 'flac', 950000),
  _track('Nightdrive', 'mp3', 320000),
];

TunesManifest _manifestOf(List<ManifestTrack> tracks) =>
    TunesManifest(tracks: tracks, releases: groupReleases(tracks));

void main() {
  late Directory tempDir;
  late DownloadStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tunes-test-');
    store = DownloadStore(tempDir);
    await store.load();
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpApp(
    WidgetTester tester,
    _FakeClient client,
    FakeTunePlayer player, {
    Reachability? reachability,
  }) async {
    await tester.pumpWidget(
      TunesApp(
        client: client,
        player: player,
        store: store,
        reachability: reachability ?? Reachability(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> goToLibrary(WidgetTester tester) async {
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
  }

  testWidgets('home renders dynamic stats from the manifest', (tester) async {
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf(_library())),
      FakeTunePlayer(),
    );

    expect(find.text('2 tracks · 1 artist · 2 releases'), findsOneWidget);
    expect(find.text('Artists'), findsOneWidget);
    expect(find.text('Albums'), findsOneWidget);
  });

  testWidgets('shows the honest error state when the daemon is unreachable', (
    tester,
  ) async {
    final client = _FakeClient(
      () async => throw TunesFetchException('unreachable'),
    );
    await pumpApp(tester, client, FakeTunePlayer());

    expect(find.text('No library yet'), findsOneWidget);
    expect(find.textContaining('tunesd is not answering'), findsOneWidget);
  });

  testWidgets('empty manifest shows the no-library home state', (tester) async {
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf([])),
      FakeTunePlayer(),
    );

    expect(
      find.textContaining('No library yet — channels are configured'),
      findsOneWidget,
    );
  });

  testWidgets('library tab lists tracks with quality badges', (tester) async {
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf(_library())),
      FakeTunePlayer(),
    );
    await goToLibrary(tester);

    expect(find.text('Bassline'), findsOneWidget);
    expect(find.text('FLAC 950k'), findsOneWidget);
    expect(find.text('MP3 320k'), findsOneWidget);
    expect(find.text('Tracks'), findsWidgets);
    expect(find.text('Albums'), findsWidgets);
  });

  testWidgets('tapping a library row starts playback on that track', (
    tester,
  ) async {
    final player = FakeTunePlayer();
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf(_library())),
      player,
    );
    await goToLibrary(tester);

    await tester.tap(find.text('Nightdrive'));
    await tester.pumpAndSettle();

    expect(player.playQueueCalls, 1);
    expect(player.index, 1);
    expect(player.current?.title, 'Nightdrive');
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
  });

  testWidgets('playing records recents on the home tab', (tester) async {
    final player = FakeTunePlayer();
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf(_library())),
      player,
    );
    await goToLibrary(tester);
    await tester.tap(find.text('Bassline'));
    await tester.pumpAndSettle();
    expect(player.playQueueCalls, 1);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Recently played'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Recently played'), findsOneWidget);
    expect(find.text('Bassline'), findsWidgets);
  });

  testWidgets('album page uses per-release positions for folded singles', (
    tester,
  ) async {
    final tracks = [
      _track(
        'BROTHER STONE',
        'flac',
        950000,
        artist: 'Don Toliver',
        album: 'BROTHER STONE',
        sha: 'a' * 64,
        releaseId: 'rel-single',
      ),
    ];
    final manifest = TunesManifest(
      tracks: tracks,
      releases: [
        ManifestRelease(
          id: 'rel-single',
          title: 'BROTHER STONE',
          artist: 'Don Toliver',
          year: '2024',
          artSha: null,
          type: 'single',
          totalTracks: 1,
          trackShas: ['a' * 64],
        ),
        ManifestRelease(
          id: 'rel-album',
          title: 'HARDSTONE PSYCHO',
          artist: 'Don Toliver',
          year: '2024',
          artSha: null,
          type: 'album',
          totalTracks: 19,
          trackShas: ['a' * 64],
          tracks: [
            ManifestReleaseTrack(sha: 'a' * 64, trackNumber: 9, discNumber: 1),
          ],
        ),
      ],
    );
    await pumpApp(tester, _FakeClient(() async => manifest), FakeTunePlayer());
    await tester.tap(find.text('HARDSTONE PSYCHO').first);
    await tester.pumpAndSettle();
    expect(find.text('09'), findsOneWidget);
    expect(find.textContaining('/19 tracks'), findsOneWidget);
  });

  testWidgets('search queries the database and surfaces albums and artists', (
    tester,
  ) async {
    final manifest = _manifestOf(_library());
    final client = _FakeClient(
      () async => manifest,
      onSearch: (q) async => SearchResults(
        tracks: const [],
        releases: [
          ManifestRelease(
            id: 'rel-x',
            title: 'Nightdrive (Remaster)',
            artist: 'Vax',
            year: '2026',
            artSha: null,
            type: 'album',
            totalTracks: 9,
            trackShas: const [],
          ),
        ],
        artists: const [ManifestArtist(name: 'Vax', artSha: null)],
      ),
    );
    await pumpApp(tester, client, FakeTunePlayer());

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'night');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('Artists'), findsOneWidget);
    expect(find.text('Nightdrive (Remaster)'), findsOneWidget);

    await tester.tap(find.text('Nightdrive (Remaster)'));
    await tester.pumpAndSettle();
    expect(find.text('Album'), findsWidgets);
  });

  testWidgets('search surfaces artists from MusicBrainz and opens their page', (
    tester,
  ) async {
    final manifest = _manifestOf(_library());
    final client = _FakeClient(
      () async => manifest,
      onSearch: (q) async => SearchResults(
        tracks: [],
        releases: [],
        artists: [],
        externalArtists: const [
          ExternalArtist(
            name: 'OCTANE',
            mbid: 'mbid-oct',
            type: 'Group',
            disambiguation: 'US rap duo',
            score: 95,
          ),
        ],
      ),
    );
    await pumpApp(tester, client, FakeTunePlayer());

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'octane');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Artists on MusicBrainz'), findsOneWidget);
    expect(find.text('Group · US rap duo'), findsOneWidget);

    await tester.tap(find.text('OCTANE'));
    await tester.pumpAndSettle();

    expect(find.text('Artist'), findsOneWidget);
    expect(find.text('OCTANE'), findsOneWidget);
  });

  testWidgets('artist page lists discography not in the library', (
    tester,
  ) async {
    final tracks = [
      _track(
        'KRYPTONITE',
        'flac',
        950000,
        artist: 'Don Toliver',
        album: 'HARDSTONE PSYCHO',
        sha: 'a' * 64,
        releaseId: 'rel-1',
      ),
    ];
    final manifest = TunesManifest(
      tracks: tracks,
      releases: [
        ManifestRelease(
          id: 'rel-1',
          title: 'HARDSTONE PSYCHO',
          artist: 'Don Toliver',
          year: '2024',
          artSha: null,
          type: 'album',
          totalTracks: 19,
          trackShas: ['a' * 64],
        ),
      ],
    );
    final client = _FakeClient(
      () async => manifest,
      onDiscography: (artist) async => ArtistDiscography(
        artist: artist,
        mbid: 'mbid-1',
        fetchedAt: 1,
        groups: [
          DiscographyGroup(
            id: 'g1',
            title: 'HARDSTONE PSYCHO',
            type: 'Album',
            year: '2024',
            date: '2024-08-09',
            owned: true,
            releaseId: 'rel-1',
            ownedTracks: 1,
            totalTracks: 19,
          ),
          DiscographyGroup(
            id: 'g2',
            title: 'OCTANE',
            type: 'Album',
            year: '2026',
            date: '2026-06-26',
            owned: false,
            releaseId: null,
            ownedTracks: 0,
            totalTracks: null,
          ),
          DiscographyGroup(
            id: 'g3',
            title: 'Love Sick',
            type: 'Album',
            year: '2023',
            date: '2023-02-24',
            owned: false,
            releaseId: null,
            ownedTracks: 0,
            totalTracks: null,
          ),
        ],
      ),
    );
    await pumpApp(tester, client, FakeTunePlayer());

    await tester.tap(find.text('Artists').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Don Toliver'));
    await tester.pumpAndSettle();

    expect(find.text('Discography · 1 of 3 in your library'), findsOneWidget);
    expect(find.text('OCTANE'), findsOneWidget);
    expect(find.text('Love Sick'), findsOneWidget);
    expect(find.text('not in library'), findsNWidgets(2));
  });

  testWidgets('home surfaces missing-from-collection and released-this-year', (
    tester,
  ) async {
    final tracks = [
      _track(
        'XSCAPE',
        'flac',
        950000,
        artist: 'Don Toliver',
        album: 'Life of a DON',
        sha: 'a' * 64,
        releaseId: 'rel-1',
      ),
    ];
    final manifest = TunesManifest(
      tracks: tracks,
      releases: [
        ManifestRelease(
          id: 'rel-1',
          title: 'Life of a DON',
          artist: 'Don Toliver',
          year: '2021',
          artSha: null,
          type: 'album',
          totalTracks: 19,
          trackShas: ['a' * 64],
        ),
        ManifestRelease(
          id: 'rel-2',
          title: 'HARDSTONE PSYCHO',
          artist: 'Don Toliver',
          year: '2026',
          artSha: null,
          type: 'album',
          totalTracks: 15,
          trackShas: ['a' * 64],
        ),
      ],
    );
    await pumpApp(tester, _FakeClient(() async => manifest), FakeTunePlayer());

    expect(find.text('Missing from your collection'), findsOneWidget);
    expect(find.textContaining('1/19'), findsOneWidget);
    expect(find.text('Released this year'), findsOneWidget);
    expect(find.textContaining('HARDSTONE PSYCHO'), findsWidgets);
  });

  testWidgets('artist circles render provider photos when available', (
    tester,
  ) async {
    final tracks = [_track('One', 'flac', 950000, artist: 'Vax')];
    final manifest = TunesManifest(
      tracks: tracks,
      releases: groupReleases(tracks),
      artists: [ManifestArtist(name: 'Vax', artSha: 'c' * 64)],
    );
    await pumpApp(tester, _FakeClient(() async => manifest), FakeTunePlayer());

    expect(find.byType(Image), findsOneWidget); // the photo widget is engaged

    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsWidgets); // photo on the artist page too
  });

  testWidgets('artist on home opens the artist page', (tester) async {
    await pumpApp(
      tester,
      _FakeClient(
        () async => _manifestOf([_track('One', 'flac', 950000, artist: 'Vax')]),
      ),
      FakeTunePlayer(),
    );

    await tester.tap(find.text('Vax').first);
    await tester.pumpAndSettle();

    expect(find.text('Artist'), findsOneWidget);
    expect(find.text('Play all'), findsOneWidget);
    expect(find.text('Vax'), findsOneWidget); // page title
  });

  testWidgets('search filters and plays results', (tester) async {
    final player = FakeTunePlayer();
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf(_library())),
      player,
    );

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'night');
    await tester.pumpAndSettle();

    expect(find.text('Nightdrive'), findsOneWidget);
    expect(find.text('Bassline'), findsNothing);

    await tester.tap(find.text('Nightdrive'));
    await tester.pumpAndSettle();
    expect(player.playQueueCalls, 1);
  });

  testWidgets('album card opens the album page with its tracklist', (
    tester,
  ) async {
    final player = FakeTunePlayer();
    final tracks = [
      _track(
        'MAFIA',
        'flac',
        950000,
        artist: 'Travis Scott',
        album: 'ESCAPE PLAN / MAFIA',
        sha: 'a' * 64,
        releaseId: 'rel-1',
      ),
      _track(
        'ESCAPE PLAN',
        'flac',
        950000,
        artist: 'Travis Scott',
        album: 'ESCAPE PLAN / MAFIA',
        sha: 'b' * 64,
        releaseId: 'rel-1',
      ),
    ];
    final manifest = TunesManifest(
      tracks: tracks,
      releases: [
        ManifestRelease(
          id: 'rel-1',
          title: 'ESCAPE PLAN / MAFIA',
          artist: 'Travis Scott',
          year: '2021',
          artSha: null,
          type: 'single',
          totalTracks: null,
          trackShas: ['a' * 64, 'b' * 64],
        ),
      ],
    );
    await pumpApp(tester, _FakeClient(() async => manifest), player);

    await tester.tap(find.text('ESCAPE PLAN / MAFIA').first);
    await tester.pumpAndSettle();

    expect(find.text('Album'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('MAFIA'), findsOneWidget);
    expect(find.text('ESCAPE PLAN'), findsOneWidget);

    await tester.tap(find.text('MAFIA'));
    await tester.pumpAndSettle();
    expect(player.playQueueCalls, 1);
    expect(player.queue.length, 2);
  });

  testWidgets('library albums render one card per release', (tester) async {
    final tracks = [
      _track(
        'MAFIA',
        'flac',
        950000,
        artist: 'Travis Scott',
        album: 'ESCAPE PLAN / MAFIA',
        sha: 'a' * 64,
        releaseId: 'rel-1',
      ),
      _track(
        'ESCAPE PLAN',
        'flac',
        950000,
        artist: 'Travis Scott',
        album: 'ESCAPE PLAN / MAFIA',
        sha: 'b' * 64,
        releaseId: 'rel-1',
      ),
    ];
    final manifest = TunesManifest(
      tracks: tracks,
      releases: [
        ManifestRelease(
          id: 'rel-1',
          title: 'ESCAPE PLAN / MAFIA',
          artist: 'Travis Scott',
          year: '2021',
          artSha: null,
          type: 'single',
          totalTracks: null,
          trackShas: ['a' * 64, 'b' * 64],
        ),
      ],
    );
    await pumpApp(tester, _FakeClient(() async => manifest), FakeTunePlayer());
    await goToLibrary(tester);

    await tester.tap(find.text('Albums').last);
    await tester.pumpAndSettle();

    expect(find.text('ESCAPE PLAN / MAFIA'), findsOneWidget);
    expect(find.text('Travis Scott · 2'), findsOneWidget);
  });

  testWidgets('profile sheet opens from the avatar', (tester) async {
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf(_library())),
      FakeTunePlayer(),
    );

    await tester.tap(find.byIcon(Icons.person_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Daemon'), findsOneWidget);
    expect(find.text('http://fake:4780'), findsOneWidget);
    expect(find.text('Library'), findsWidgets);
  });

  testWidgets('mini bar is minimal: art, title, play only', (tester) async {
    final player = FakeTunePlayer();
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf(_library())),
      player,
    );
    await goToLibrary(tester);

    await tester.tap(find.text('Bassline'));
    await tester.pumpAndSettle();

    expect(find.byType(Slider), findsNothing); // no progress in the bar
    expect(
      find.byIcon(Icons.close_rounded),
      findsNothing,
    ); // no stop in the bar
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    expect(player.toggleCalls, 1);
  });

  testWidgets('orientation change keeps the mini bar on the same player', (
    tester,
  ) async {
    final player = FakeTunePlayer();
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf(_library())),
      player,
    );
    await goToLibrary(tester);

    await tester.tap(find.text('Bassline'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();

    expect(find.text('Bassline'), findsNWidgets(2)); // row + mini bar
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(player.playQueueCalls, 1);
  });

  testWidgets('stop lives in the Now Playing menu', (tester) async {
    final player = FakeTunePlayer();
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf(_library())),
      player,
    );
    await goToLibrary(tester);

    await tester.tap(find.text('Bassline'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bassline').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();

    expect(player.stopCalls, 1);
    expect(find.byIcon(Icons.pause_rounded), findsNothing);
  });

  testWidgets('tapping the mini bar opens the full Now Playing page', (
    tester,
  ) async {
    final player = FakeTunePlayer();
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf(_library())),
      player,
    );
    await goToLibrary(tester);

    await tester.tap(find.text('Bassline'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bassline').last);
    await tester.pumpAndSettle();

    expect(find.text('Now Playing'), findsOneWidget);
    expect(find.text('Up next'), findsNothing); // queue is a secondary surface
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
  });

  testWidgets('full page controls reach the player', (tester) async {
    final player = FakeTunePlayer();
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf(_library())),
      player,
    );
    await goToLibrary(tester);

    await tester.tap(find.text('Bassline'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bassline').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    expect(player.nextCalls, 1);

    await tester.tap(find.byIcon(Icons.skip_previous_rounded));
    expect(player.previousCalls, 1);
  });

  testWidgets('queue is a secondary sheet that jumps tracks', (tester) async {
    final player = FakeTunePlayer();
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf(_library())),
      player,
    );
    await goToLibrary(tester);

    await tester.tap(find.text('Bassline'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bassline').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Queue'));
    await tester.pumpAndSettle();

    expect(find.text('Now playing'), findsOneWidget);
    await tester.tap(find.text('Nightdrive'));
    await tester.pumpAndSettle();
    expect(player.playAtCalls, 1);
    expect(player.index, 1);
  });

  testWidgets('now playing menu opens the album page', (tester) async {
    final player = FakeTunePlayer();
    final tracks = [
      _track(
        'MAFIA',
        'flac',
        950000,
        artist: 'Travis Scott',
        album: 'ESCAPE PLAN / MAFIA',
        sha: 'a' * 64,
        releaseId: 'rel-1',
      ),
    ];
    final manifest = TunesManifest(
      tracks: tracks,
      releases: [
        ManifestRelease(
          id: 'rel-1',
          title: 'ESCAPE PLAN / MAFIA',
          artist: 'Travis Scott',
          year: '2021',
          artSha: null,
          type: 'single',
          totalTracks: null,
          trackShas: ['a' * 64],
        ),
      ],
    );
    await pumpApp(tester, _FakeClient(() async => manifest), player);
    await goToLibrary(tester);
    await tester.tap(find.text('MAFIA'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MAFIA').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go to album'));
    await tester.pumpAndSettle();

    expect(find.byType(AlbumPage), findsOneWidget);
    expect(find.text('MAFIA'), findsWidgets); // the album tracklist row
    expect(
      find.byIcon(Icons.pause_rounded),
      findsOneWidget,
    ); // mini bar pinned, playing
  });

  testWidgets('active track is highlighted in the library list', (
    tester,
  ) async {
    final player = FakeTunePlayer();
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf(_library())),
      player,
    );
    await goToLibrary(tester);

    expect(find.byIcon(Icons.graphic_eq_rounded), findsNothing);

    await tester.tap(find.text('Bassline'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
  });

  testWidgets('album rows highlight the active track compactly', (
    tester,
  ) async {
    final player = FakeTunePlayer();
    final tracks = [
      _track(
        'MAFIA',
        'flac',
        950000,
        artist: 'Travis Scott',
        album: 'ESCAPE PLAN / MAFIA',
        sha: 'a' * 64,
        releaseId: 'rel-1',
      ),
      _track(
        'ESCAPE PLAN',
        'flac',
        950000,
        artist: 'Travis Scott',
        album: 'ESCAPE PLAN / MAFIA',
        sha: 'b' * 64,
        releaseId: 'rel-1',
      ),
    ];
    final manifest = TunesManifest(
      tracks: tracks,
      releases: [
        ManifestRelease(
          id: 'rel-1',
          title: 'ESCAPE PLAN / MAFIA',
          artist: 'Travis Scott',
          year: '2021',
          artSha: null,
          type: 'single',
          totalTracks: null,
          trackShas: ['a' * 64, 'b' * 64],
        ),
      ],
    );
    await pumpApp(tester, _FakeClient(() async => manifest), player);
    await goToLibrary(tester);
    await tester.tap(find.text('Albums').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ESCAPE PLAN / MAFIA').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('MAFIA').first);
    await tester.pumpAndSettle();

    expect(
      find.byIcon(Icons.pause_rounded),
      findsOneWidget,
    ); // playing via mini bar
    expect(
      find.textContaining('FLAC'),
      findsNothing,
    ); // no quality pill in album rows
  });

  testWidgets('mini bar docks on the album page (height bounded)', (
    tester,
  ) async {
    final player = FakeTunePlayer();
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf(_library())),
      player,
    );
    await goToLibrary(tester);
    await tester.tap(find.text('Bassline'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bassline').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go to album'));
    await tester.pumpAndSettle();

    final bar = find.byType(MiniPlayerBar);
    expect(bar, findsWidgets);
    final size = tester.getSize(bar.first);
    debugPrint('mini bar size: ${size.width}x${size.height}');
    expect(size.height, lessThan(200));
  });

  testWidgets('download icon downloads and marks the track offline-ready', (
    tester,
  ) async {
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf(_library())),
      FakeTunePlayer(),
    );
    await goToLibrary(tester);

    expect(find.byIcon(Icons.download_rounded), findsNWidgets(2));

    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.download_rounded).first);
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.offline_pin_rounded), findsOneWidget);
    expect(store.contains('a' * 64), isTrue);
    expect(File(store.pathFor('a' * 64)!).existsSync(), isTrue);
  });

  test('DownloadStore persists across instances', () async {
    await store.add('c' * 64, '${tempDir.path}/c' * 64);
    final reloaded = DownloadStore(tempDir);
    await reloaded.load();
    expect(reloaded.contains('c' * 64), isTrue);
    expect(reloaded.pathFor('c' * 64), '${tempDir.path}/c' * 64);
  });

  test('Heartbeat flips reachability on probe results', () async {
    var ok = false;
    final reach = Reachability();
    final hb = Heartbeat(ping: () async => ok, reachability: reach);
    await hb.probe();
    expect(reach.offline, isTrue);
    ok = true;
    await hb.probe();
    expect(reach.offline, isFalse);
  });

  testWidgets('offline banner shows and non-downloaded rows are inert', (
    tester,
  ) async {
    final reach = Reachability();
    final player = FakeTunePlayer();
    await tester.runAsync(
      () => store.add('b' * 64, '${tempDir.path}/nightdrive'),
    );
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf(_library())),
      player,
      reachability: reach,
    );
    await goToLibrary(tester);
    reach.setOffline(true);
    await tester.pumpAndSettle();

    expect(find.text('Offline — playing downloads only'), findsOneWidget);

    await tester.tap(find.text('Bassline'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(player.playQueueCalls, 0);

    await tester.tap(find.text('Nightdrive'));
    await tester.pumpAndSettle();
    expect(player.playQueueCalls, 1);
    expect(player.current?.title, 'Nightdrive');
  });

  testWidgets('banner disappears when reachability recovers', (tester) async {
    final reach = Reachability();
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf(_library())),
      FakeTunePlayer(),
      reachability: reach,
    );
    reach.setOffline(true);
    await tester.pumpAndSettle();
    expect(find.text('Offline — playing downloads only'), findsOneWidget);

    reach.setOffline(false);
    await tester.pumpAndSettle();
    expect(find.text('Offline — playing downloads only'), findsNothing);
  });
}
