import 'package:tunes/domain/about.dart';

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/ui/playing_bars.dart';
import 'package:tunes/core/ui/tunes_refresh.dart';
import 'package:tunes/features/now_playing/now_playing_page.dart';
import 'package:tunes/core/audio/tune_player.dart';
import 'package:tunes/core/platform/device.dart';
import 'package:tunes/core/ui/tunes_nav_bar.dart';
import 'package:tunes/features/desktop/desktop_play_bar.dart';
import 'package:tunes/features/lyrics/lyrics_sheet.dart';
import 'package:tunes/features/player/scrubber.dart';
import 'package:tunes/features/now_playing/lyric_preview.dart';
import 'package:tunes/features/desktop/desktop_sidebar.dart';
import 'package:tunes/core/data/database.dart';
import 'package:tunes/core/data/art_store.dart';
import 'package:tunes/core/data/download_manager.dart';
import 'package:tunes/core/data/download_store.dart';
import 'package:tunes/core/audio/playhead_clock.dart';
import 'package:tunes/core/data/likes_store.dart';
import 'package:tunes/core/data/manifest_store.dart';
import 'package:tunes/core/data/play_history.dart';
import 'package:tunes/core/data/playlist_store.dart';
import 'package:tunes/core/data/queue_store.dart';
import 'package:tunes/core/data/settings_store.dart';
import 'package:tunes/core/data/reachability.dart';
import 'package:tunes/core/net/tunes_client.dart';
import 'package:tunes/core/sync/sync_models.dart';
import 'package:tunes/core/net/update_check.dart';
import 'package:tunes/domain/manifest.dart';
import 'package:tunes/domain/soulseek.dart';
import 'package:tunes/domain/whats_new.dart';
import 'package:tunes/domain/discography.dart';
import 'package:tunes/features/album/album_page.dart';
import 'package:tunes/features/artist/artist_page.dart';
import 'package:tunes/features/player/mini_player_bar.dart';
import 'package:tunes/core/auth/media_grants.dart';
import 'package:tunes/core/auth/token_store.dart';
import 'package:tunes/core/auth/tunes_auth.dart';
import 'package:tunes/main.dart';

/// Test-only QueueStore that persists to the same drift database
/// but exposes `watch()` as a synchronous, broadcast stream. Avoids
/// the drift-internal Timer that the real `watch()` schedules; that
/// Timer races the widget test runner's fake_async zone on teardown
/// and crashes the harness. Persists the same way (via the parent
/// QueueStore) so the row layout matches production. Caches the last
/// emitted value so new subscribers get the current state immediately
/// (broadcast streams don't replay missed events).
class _TestQueueStore extends QueueStore {
  _TestQueueStore(super.db);
  final _controller = StreamController<List<QueueItem>>.broadcast();
  List<QueueItem> _latest = const [];

  @override
  Stream<List<QueueItem>> watch() async* {
    if (_latest.isNotEmpty) yield _latest;
    yield* _controller.stream;
  }

  @override
  Future<void> replace(List<String> shas) async {
    await super.replace(shas);
    _latest = await load();
    _controller.add(_latest);
  }

  @override
  Future<void> append(String sha) async {
    await super.append(sha);
    _latest = await load();
    _controller.add(_latest);
  }

  @override
  Future<void> insertAt(int position, String sha) async {
    await super.insertAt(position, sha);
    _latest = await load();
    _controller.add(_latest);
  }

  @override
  Future<void> reorder(List<int> ids) async {
    await super.reorder(ids);
    _latest = await load();
    _controller.add(_latest);
  }

  @override
  Future<void> removeById(int id) async {
    await super.removeById(id);
    _latest = await load();
    _controller.add(_latest);
  }

  @override
  Future<void> clear() async {
    await super.clear();
    _latest = const [];
    _controller.add(_latest);
  }
}

class _FakeClient implements TunesClient {
  @override
  Future<({SongAbout? song, AlbumAbout? album})?> aboutSong(String sha) async =>
      null;
  @override
  Future<AlbumAbout?> aboutAlbum(String releaseId) async => null;
  @override
  Future<({ArtistAbout? artist, List<Collaborator> people})?> aboutArtist(
    String name,
  ) async => null;
  @override
  Future<List<Work>?> aboutPerson(String name) async => null;
  @override
  Future<List<GetJob>> soulseekCompleteAlbum(
    String artist,
    String album,
  ) async => const [];

  _FakeClient(
    this.result, {
    this.onSearch,
    this.onDiscography,
    this.onChanges,
    this.onMissing,
  });

  /// No token: these tests exercise the library UI, not enrolment, so the
  /// client behaves exactly as an un-enrolled device does for real.
  @override
  Future<String?> Function()? bearer;

  /// Unauthenticated by default. Every auth call is refused and the app falls
  /// back to unsigned URLs.
  @override
  Future<({int status, Map<String, dynamic> body})> postJson(
    String path,
    Map<String, dynamic> payload, {
    String? bearer,
  }) async => (status: 401, body: <String, dynamic>{});

  @override
  Future<ChangesResponse> fetchChanges(DateTime since) async {
    changesCalls.add(since);
    final custom = onChanges;
    if (custom != null) return custom(since);
    return ChangesResponse(
      generatedAt: null,
      integrity: '',
      addedShas: const [],
    );
  }

  final Future<TunesManifest> Function() result;
  final Future<SearchResults> Function(String q)? onSearch;
  final Future<ArtistDiscography> Function(String artist)? onDiscography;
  final Future<ChangesResponse> Function(DateTime since)? onChanges;
  final Future<List<MissingRelease>> Function()? onMissing;
  final List<DateTime> changesCalls = [];

  @override
  Future<List<MissingRelease>> missing({int limit = 40}) async {
    final custom = onMissing;
    return custom != null ? custom() : const [];
  }

  /// Settable, because the real client's address is now settable: pointing the
  /// app at a different server has to take effect without a relaunch. A
  /// getter-only override no longer satisfies the interface.
  @override
  String baseUrl = 'http://fake:4780';

  /// No update, which is what the daemon says when none is configured. These
  /// tests are about the library, and an update banner appearing in them would
  /// be noise from a subsystem they are not exercising.
  @override
  Future<AvailableUpdate?> fetchUpdate() async => null;

  @override
  String get updateApkUrl => '$baseUrl/update/apk';

  @override
  Future<TunesManifest> fetchManifest({bool fromCacheOnFailure = true}) =>
      result();

  @override
  Future<int?> syncPush(List<SyncDoc> docs) async => null;

  @override
  Future<SyncPullPage?> syncPull(int after, {bool onlyLive = false}) async =>
      null;

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
  Future<bool> putLyrics(String sha, String text) async => true;

  @override
  Future<Uint8List?> clip(
    String sha,
    Duration from,
    Duration to, {
    Uint8List? card,
  }) async => null;

  @override
  Future<List<FoundSong>> soulseekSearch(String q) async => const [];

  @override
  Future<GetJob> soulseekGet({
    required String title,
    required String artist,
    String? album,
    int? durationMs,
    String? release,
    FoundSong? copy,
  }) async =>
      GetJob(id: 'j', title: title, artist: artist, state: GetState.queued);

  @override
  Future<List<GetJob>> soulseekJobs({int? days}) async => const [];

  @override
  Future<List<GetJob>> soulseekComplete(String releaseId) async => const [];

  @override
  Future<bool> soulseekCancel(String id) async => false;

  @override
  Future<List<TracklistEntry>?> tracklist(String releaseId) async => null;

  @override
  Future<void> warm(String sha, {String? signedPath}) async {}

  @override
  Future<void> downloadTrack(
    String sha,
    String path, {
    void Function(int received, int total)? onProgress,
    CancelSignal? cancel,
  }) async {
    File(path).parent.createSync(recursive: true);
    File(path).writeAsBytesSync(List.filled(100, 1));
  }

  @override
  Future<void> downloadArt(String sha, String path) async {
    File(path).parent.createSync(recursive: true);
    File(path).writeAsBytesSync(List.filled(10, 2));
  }
}

class FakeTunePlayer extends TunePlayer {
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

  int playQueueCalls = 0;
  int toggleCalls = 0;
  int seekCalls = 0;
  int nextCalls = 0;
  int previousCalls = 0;
  int playAtCalls = 0;
  int playCalls = 0;
  int pauseCalls = 0;
  int setRepeatCalls = 0;
  int setShuffleCalls = 0;
  List<PlaybackRepeat> repeatHistory = [];
  List<bool> shuffleHistory = [];

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
    if (_repeat == PlaybackRepeat.one && _queue.isNotEmpty) {
      _position = Duration.zero;
      _playing = true;
      notifyListeners();
      return;
    }
    if (_index >= _queue.length - 1) {
      if (_repeat == PlaybackRepeat.all && _queue.length > 1) {
        _index = 0;
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
    previousCalls += 1;
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
    playAtCalls += 1;
    _index = index;
    _playing = true;
    notifyListeners();
  }

  @override
  void playQueue(List<ManifestTrack> tracks, int startIndex) {
    playQueueCalls += 1;
    if (tracks.isEmpty) return;
    final safeStart = startIndex.clamp(0, tracks.length - 1).toInt();
    if (_shuffle && tracks.length > 1) {
      // Mirror MediaKitTunePlayer: pin the start track first, rotate
      // the remainder. Deterministic enough for tests — the rotation
      // is intentionally unseeded since we only care about the
      // contract (start track at index 0, queue size unchanged).
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

  @override
  void setRepeat(PlaybackRepeat mode) {
    if (_repeat == mode) return;
    setRepeatCalls += 1;
    repeatHistory.add(mode);
    _repeat = mode;
    notifyListeners();
  }

  @override
  void setShuffle(bool on) {
    if (_shuffle == on) return;
    setShuffleCalls += 1;
    shuffleHistory.add(on);
    _shuffle = on;
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
  DateTime? addedAt,
  String? lyrics,
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
  addedAt: addedAt,
  lyrics: lyrics,
);

List<ManifestTrack> _library() => [
  _track('Bassline', 'flac', 950000, addedAt: DateTime.utc(2026, 8, 30)),
  _track('Nightdrive', 'mp3', 320000, addedAt: DateTime.utc(2026, 1, 1)),
];

TunesManifest _manifestOf(
  List<ManifestTrack> tracks, {
  DateTime? generatedAt,
}) => TunesManifest(
  tracks: tracks,
  releases: groupReleases(tracks),
  generatedAt: generatedAt,
);

void main() {
  late Directory tempDir;
  late DownloadStore store;
  late ArtStore artStore;
  late TunesDatabase db;
  late ManifestStore manifestStore;
  late QueueStore queueStore;
  late SettingsStore settings;
  late LikesStore likes;
  late PlaylistStore playlists;
  late PlayHistory history;

  setUp(() async {
    // Continuous ticking and pumpAndSettle cannot both be true: the clock
    // schedules a frame every frame while playing, so a settle after starting
    // playback would never finish. Positions still flow from the player.
    PlayheadClock.ticking = false;
    tempDir = await Directory.systemTemp.createTemp('tunes-test-');
    store = DownloadStore(tempDir);
    await store.load();
    artStore = ArtStore(Directory('${tempDir.path}/art'));
    await artStore.load();
    db = TunesDatabase.forTesting(NativeDatabase.memory());
    manifestStore = ManifestStore(db);
    queueStore = _TestQueueStore(db);
    settings = SettingsStore(db);
    await settings.load();
    // The What's new page covers the app on a first open. Tests are not on a
    // first open unless they say so, so it is marked as seen.
    await settings.setWhatsNewSeen(kWhatsNewId);
    likes = LikesStore(db);
    await likes.load();
    playlists = PlaylistStore(db);
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
    await db.close();
  });

  Future<void> pumpApp(
    WidgetTester tester,
    _FakeClient client,
    FakeTunePlayer player, {
    Reachability? reachability,
  }) async {
    history = PlayHistory(db, player);
    // Un-enrolled, which is what these tests want: the library UI must render
    // from the local store without any credential.
    final auth = TunesAuth(post: client.postJson, store: MemoryTokenStore());
    // Reduced motion, as a user can ask for. The bars on the playing song, and
    // the pulse on a queued download, move for ever by design, and a test that
    // waits for the screen to settle would wait for ever with them.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(
      TunesApp(
        client: client,
        grants: MediaGrants(auth: auth),
        auth: auth,
        player: player,
        store: store,
        artStore: artStore,
        reachability: reachability ?? Reachability(),
        manifestStore: manifestStore,
        queueStore: queueStore,
        settings: settings,
        history: history,
        likes: likes,
        playlists: playlists,
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

  testWidgets('second sync uses /changes and skips full manifest', (
    tester,
  ) async {
    final client = _FakeClient(
      () async =>
          _manifestOf(_library(), generatedAt: DateTime.utc(2026, 8, 31)),
      onChanges: (_) async => ChangesResponse(
        generatedAt: null,
        integrity: '',
        addedShas: const [],
      ),
    );
    await pumpApp(tester, client, FakeTunePlayer());
    // Initial sync: no _lastSyncAt yet → /manifest only, no /changes call.
    expect(client.changesCalls, isEmpty);
    expect(find.text('2 tracks · 1 artist · 2 releases'), findsOneWidget);

    // Force a second sync by pulling the feed down, which is the only way to
    // ask for one now that the header button is gone.
    // Fling the feed itself. The library line moved into the static header,
    // and pulling something that does not scroll refreshes nothing.
    await tester.fling(
      find.byType(TunesRefreshList),
      const Offset(0, 320),
      1000,
    );
    await tester.pumpAndSettle();

    // Second sync: _lastSyncAt is set → /changes called with it; empty
    // addedShas short-circuits the /manifest download.
    expect(client.changesCalls, hasLength(1));
    // The 'since' parameter is the watermark: the moment the manifest the
    // phone holds was built, never the moment of the last sync. A watermark
    // of "now" would retire every track the applied manifest did not contain,
    // and /changes only ever names what arrived after the watermark
    // (domain/sync_watermark).
    final since = client.changesCalls.single;
    expect(since, DateTime.utc(2026, 8, 31));
  });

  testWidgets('a stale manifest does not retire the tracks it is missing', (
    tester,
  ) async {
    // The edge answers /manifest from a cached copy while /changes is
    // answered by the live daemon, so the two can disagree: /changes names a
    // track the cached manifest predates. Applying that manifest and then
    // claiming "now" would retire the track for good — nothing would ever
    // name it again, and the library would stop growing. The watermark has
    // to stay at the moment that copy was built.
    final stale = _track(
      'Bassline',
      'flac',
      950000,
      addedAt: DateTime.utc(2026, 8, 30),
    );
    final client = _FakeClient(
      () async => _manifestOf([stale], generatedAt: DateTime.utc(2026, 8, 31)),
      onChanges: (_) async => ChangesResponse(
        generatedAt: null,
        integrity: '',
        addedShas: ['c' * 64],
      ),
    );
    await pumpApp(tester, client, FakeTunePlayer());
    expect(client.changesCalls, isEmpty);

    await tester.fling(
      find.byType(TunesRefreshList),
      const Offset(0, 320),
      1000,
    );
    await tester.pumpAndSettle();

    // The second sync asked about the tracks it is missing, and the watermark
    // it sent is when that stale copy was built -- not the moment it synced,
    // so the track the copy predates keeps being named.
    expect(client.changesCalls, hasLength(1));
    final since = client.changesCalls.single;
    expect(since, DateTime.utc(2026, 8, 31));
    expect(
      DateTime.now().difference(since).inDays,
      greaterThan(1),
      reason: 'the watermark must not run past the manifest that was applied',
    );
  });

  testWidgets('the library is asked about again every few minutes, and on '
      'coming back to the app', (tester) async {
    final client = _FakeClient(
      () async => _manifestOf(_library()),
      onChanges: (_) async => ChangesResponse(
        generatedAt: null,
        integrity: '',
        addedShas: const [],
      ),
    );
    await pumpApp(tester, client, FakeTunePlayer());
    expect(client.changesCalls, isEmpty);

    // Not before the beat.
    await tester.pump(const Duration(minutes: 2));
    expect(client.changesCalls, isEmpty);

    await tester.pump(const Duration(minutes: 1, seconds: 1));
    expect(client.changesCalls, hasLength(1));

    // Out of sight it holds still: no beat while the app is in the background.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 10));
    expect(client.changesCalls, hasLength(1));

    // Back on screen it asks straight away.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 100));
    expect(client.changesCalls, hasLength(2));
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

    expect(find.textContaining('Your library is empty'), findsOneWidget);
    // The empty state has to offer the gesture, since there is no content to
    // discover it on.
    expect(find.textContaining('pull down'), findsOneWidget);
  });

  testWidgets('library tab lists tracks, title first', (tester) async {
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf(_library())),
      FakeTunePlayer(),
    );
    await goToLibrary(tester);

    expect(find.text('Bassline'), findsOneWidget);
    expect(find.text('Tracks'), findsWidgets);
    expect(find.text('Albums'), findsWidgets);

    // The quality badge used to sit in every row and squeezed titles down to
    // about six characters. It now lives in Now Playing's info panel, so the
    // row must NOT carry it.
    expect(find.text('FLAC 950k'), findsNothing);
    expect(find.text('MP3 320k'), findsNothing);
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
    expect(player.current?.title, 'Nightdrive');
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
  });

  testWidgets('playing records recents, shown above the library list', (
    tester,
  ) async {
    final player = FakeTunePlayer();
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf(_library())),
      player,
    );
    await goToLibrary(tester);
    // Nothing played yet, so no rail.
    expect(find.text('Recently played'), findsNothing);
    await tester.tap(find.text('Bassline'));
    await tester.pumpAndSettle();
    expect(player.playQueueCalls, 1);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    // Home no longer carries it: it was a long scroll from where anyone looks.
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Recently played'), findsNothing);

    await goToLibrary(tester);
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
    // The count says how many of how many; what is missing is its own mark.
    expect(find.text('1 of 19 songs'), findsOneWidget);
    expect(find.text('18 missing'), findsOneWidget);
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

    // Records and artists the box knows join the library's own results.
    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('Nightdrive (Remaster)'), findsOneWidget);

    await tester.ensureVisible(find.text('Nightdrive (Remaster)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nightdrive (Remaster)'));
    await tester.pumpAndSettle();
    expect(find.byType(AlbumPage), findsOneWidget);
  });

  testWidgets(
    'search surfaces releases from MusicBrainz with ownership flags',
    (tester) async {
      final manifest = _manifestOf(_library());
      final client = _FakeClient(
        () async => manifest,
        onSearch: (q) async => SearchResults(
          tracks: [],
          releases: [],
          artists: [],
          externalArtists: const [],
          externalReleases: const [
            ExternalRelease(
              id: 'rg-octane',
              title: 'OCTANE',
              artist: 'Don Toliver',
              type: 'Album',
              year: '2026',
              date: '2026-06-26',
              owned: false,
              releaseId: null,
              ownedTracks: 0,
              totalTracks: null,
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

      expect(find.text('Albums on MusicBrainz'), findsOneWidget);
      expect(find.text('OCTANE'), findsOneWidget);
      expect(
        find.text('Don Toliver · Album · 2026 · not in your library'),
        findsOneWidget,
      );

      await tester.tap(find.text('OCTANE'));
      await tester.pumpAndSettle();
      expect(find.text('Don Toliver'), findsWidgets);
    },
  );

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

    expect(find.byType(ArtistPage), findsOneWidget);
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
    // The name also appears under the part-owned album above the rail; the rail
    // is the later of the two.
    await tester.tap(find.text('Don Toliver').last);
    await tester.pumpAndSettle();

    // The band's facts line carries how much of the catalogue is held.
    expect(find.textContaining('1 of 3 records'), findsOneWidget);
    // Held records show how much of them (v2 discography, 24 Oct); wholly
    // missing ones are there too, dashed, to get.
    expect(find.text('1 / 19'), findsOneWidget);
    expect(find.text('OCTANE'), findsOneWidget);
    expect(find.text('Love Sick'), findsOneWidget);
    expect(find.textContaining('· not yet'), findsNWidgets(2));
    // And the songs you own come before any of it.
    final songs = tester.getTopLeft(find.text('Top songs')).dy;
    final records = tester.getTopLeft(find.text('Discography')).dy;
    expect(songs, lessThan(records));
  });

  testWidgets('home surfaces a part-owned album and released-this-year', (
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

    // An album that is here but incomplete belongs under "Finish these
    // albums". "Missing from your collection" now means a record we do not
    // have at all, which the daemon decides.
    expect(find.text('Finish these albums'), findsOneWidget);
    expect(find.text('Missing from your collection'), findsNothing);
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

  group('the dock', () {
    Future<FakeTunePlayer> openArtistWithMusic(WidgetTester tester) async {
      final player = FakeTunePlayer();
      final track = _track('One', 'flac', 950000, artist: 'Vax');
      await pumpApp(
        tester,
        _FakeClient(() async => _manifestOf([track])),
        player,
      );
      player.playQueue([track], 0);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vax').first);
      await tester.pumpAndSettle();
      expect(find.byType(ArtistPage), findsOneWidget);
      return player;
    }

    testWidgets('the tabs stay on screen inside an artist page', (
      tester,
    ) async {
      await openArtistWithMusic(tester);
      for (final label in ['Home', 'Discover', 'Search', 'Library']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('there is one mini bar, not one per page', (tester) async {
      await openArtistWithMusic(tester);
      expect(find.byType(MiniPlayerBar), findsOneWidget);
    });

    testWidgets('tapping another tab leaves the page for that tab', (
      tester,
    ) async {
      await openArtistWithMusic(tester);

      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();

      expect(find.byType(ArtistPage), findsNothing);
      expect(find.text('Albums'), findsWidgets); // the Library's own tabs
    });

    testWidgets('tapping the tab you are on goes back to its top', (
      tester,
    ) async {
      await openArtistWithMusic(tester);

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      expect(find.byType(ArtistPage), findsNothing);
    });

    testWidgets('the player covers the tabs, and Back brings them back', (
      tester,
    ) async {
      await openArtistWithMusic(tester);

      await tester.tap(find.byType(MiniPlayerBar));
      await tester.pumpAndSettle();
      expect(find.byType(NowPlayingPage), findsOneWidget);
      expect(find.text('Discover'), findsNothing);

      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(ArtistPage), findsOneWidget);
      expect(find.text('Discover'), findsOneWidget);
    });
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

    expect(find.byType(ArtistPage), findsOneWidget);
    expect(find.text('Top songs'), findsOneWidget);
    expect(find.text('Shuffle'), findsOneWidget);
    expect(find.text('Vax'), findsWidgets); // page title
  });

  TunesManifest albumManifest() {
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
    return TunesManifest(
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
  }

  testWidgets('back from an album returns to the artist, not home', (
    tester,
  ) async {
    // The regression: panels used to be replaced on open, so Back from an
    // album skipped the artist it came from and fell through to Home.
    await pumpApp(
      tester,
      _FakeClient(() async => albumManifest()),
      FakeTunePlayer(),
    );

    await tester.tap(find.text('Travis Scott').first);
    await tester.pumpAndSettle();
    expect(find.byType(ArtistPage), findsOneWidget);

    // The dock is on screen now, so the card can sit below the fold of a
    // short test surface, as it would on a small phone: scroll to it first.
    // The record's tile in the discography: the album's name also sits
    // under its song in Top songs, above it.
    await tester.ensureVisible(find.text('ESCAPE PLAN / MAFIA').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ESCAPE PLAN / MAFIA').last);
    await tester.pumpAndSettle();
    expect(find.byType(AlbumPage), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(ArtistPage), findsOneWidget);
    expect(find.byType(AlbumPage), findsNothing);
  });

  testWidgets('revisiting panels keeps one instance each', (tester) async {
    // History holds unique identities; a revisit moves to the top. Artist
    // -> Album -> Artist -> Back lands on the album, Back again on Home,
    // and only one of each page exists throughout.
    await pumpApp(
      tester,
      _FakeClient(() async => albumManifest()),
      FakeTunePlayer(),
    );

    await tester.tap(find.text('Travis Scott').first);
    await tester.pumpAndSettle();
    // The dock is on screen now, so the card can sit below the fold of a
    // short test surface, as it would on a small phone: scroll to it first.
    // The record's tile in the discography: the album's name also sits
    // under its song in Top songs, above it.
    await tester.ensureVisible(find.text('ESCAPE PLAN / MAFIA').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ESCAPE PLAN / MAFIA').last);
    await tester.pumpAndSettle();
    // The album's artist link revisits the artist: a navigation event that
    // repositions, not a duplicate pane.
    await tester.tap(find.text('Travis Scott').first);
    await tester.pumpAndSettle();

    expect(find.byType(ArtistPage), findsOneWidget);
    expect(find.byType(AlbumPage), findsNothing);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(AlbumPage), findsOneWidget);
    expect(find.text('MAFIA'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(ArtistPage), findsNothing);
    expect(find.byType(AlbumPage), findsNothing);
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

    // The top result and its row in Songs.
    expect(find.text('Nightdrive'), findsWidgets);
    expect(find.text('Bassline'), findsNothing);

    await tester.tap(find.text('Nightdrive').last);
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

    // The dock is on screen now, so the card can sit below the fold of a
    // short test surface, as it would on a small phone: scroll to it first.
    // The record's tile in the discography: the album's name also sits
    // under its song in Top songs, above it.
    await tester.ensureVisible(find.text('ESCAPE PLAN / MAFIA').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ESCAPE PLAN / MAFIA').last);
    await tester.pumpAndSettle();

    expect(find.byType(AlbumPage), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('MAFIA'), findsOneWidget);
    // The second track is below the fold of a short surface with the dock up.
    await tester.scrollUntilVisible(find.text('ESCAPE PLAN'), 120);
    expect(find.text('ESCAPE PLAN'), findsOneWidget);
    // Clear of the mini player at the bottom before tapping.
    await tester.drag(find.text('ESCAPE PLAN'), const Offset(0, -200));
    await tester.pumpAndSettle();

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
    // The artist and the facts are separate lines now: the artist in the body
    // voice, the year and size of the record in mono.
    expect(find.text('Travis Scott'), findsOneWidget);
    expect(find.text('2021  ·  2 songs'), findsOneWidget);
  });

  testWidgets('the track list says how many and can shuffle them all', (
    tester,
  ) async {
    final player = FakeTunePlayer();
    await pumpApp(
      tester,
      _FakeClient(
        () async => _manifestOf([
          // Distinct shas: the library keys tracks by sha, so three that share
          // the default would be one track.
          _track('One', 'flac', 950000, sha: '1' * 64),
          _track('Two', 'flac', 950000, sha: '2' * 64),
          _track('Three', 'flac', 950000, sha: '3' * 64),
        ]),
      ),
      player,
    );
    await goToLibrary(tester);

    expect(find.text('3 songs'), findsOneWidget);
    await tester.tap(find.text('Shuffle'));
    await tester.pump();

    expect(player.playQueueCalls, 1);
    expect(player.queue.map((t) => t.title).toSet(), {'One', 'Two', 'Three'});
  });

  testWidgets('the first open of a release says what is new, once', (
    tester,
  ) async {
    await tester.runAsync(() => settings.setWhatsNewSeen(''));
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf(_library())),
      FakeTunePlayer(),
    );

    expect(find.text(kWhatsNewTitle), findsOneWidget);
    expect(find.text(kWhatsNew.first.title), findsOneWidget);
    // Recorded as shown straight away, so an interruption does not bring it back.
    expect(settings.whatsNewSeen, kWhatsNewId);

    await tester.tap(find.text('Let\'s go'));
    await tester.pumpAndSettle();
    expect(find.text(kWhatsNewTitle), findsNothing);
    // The app is there underneath.
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('and not again on the next open', (tester) async {
    // setUp has marked this pack as seen, which is what a second open looks like.
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf(_library())),
      FakeTunePlayer(),
    );
    expect(find.text(kWhatsNewTitle), findsNothing);
  });

  testWidgets('settings open from the avatar', (tester) async {
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf(_library())),
      FakeTunePlayer(),
    );

    await tester.tap(find.byIcon(Icons.person_rounded));
    await tester.pumpAndSettle();

    // The avatar now opens Settings; the old read-only sheet's diagnostics
    // live under its Library section.
    expect(find.text('Settings'), findsOneWidget);
    // Every control has to do something, so each one is asserted present
    // rather than the screen merely opening.
    // The name field says what it is for, in the hint, until a name is typed.
    expect(find.text('What should it call you?'), findsOneWidget);
    expect(find.text('Light or dark'), findsOneWidget);
    // Listening sits below the theme picker, so scroll to it.
    for (
      var i = 0;
      i < 10 && find.text('Stop when the app closes').evaluate().isEmpty;
      i++
    ) {
      await tester.dragFrom(const Offset(400, 400), const Offset(0, -160));
      await tester.pumpAndSettle();
    }
    expect(find.text('Gapless playback'), findsOneWidget);
    expect(find.text('Stop when the app closes'), findsOneWidget);
    expect(find.text('Keep playing with radio'), findsOneWidget);

    // The developer section is hidden until asked for.
    expect(find.text('Developer'), findsNothing);

    // Scrolled rather than assumed on screen: the list is longer than the
    // viewport, and a lazy sliver never builds what it has not reached.
    //
    // Dragged from a fixed point rather than from a widget: any widget used
    // as the drag handle is itself scrolled away by the first drag and then
    // unmounted, so the finder that named it stops resolving.
    Future<void> reveal(String label) async {
      for (var i = 0; i < 15 && find.text(label).evaluate().isEmpty; i++) {
        await tester.dragFrom(const Offset(400, 400), const Offset(0, -160));
        await tester.pumpAndSettle();
      }
      expect(find.text(label), findsOneWidget, reason: 'never reached $label');
    }

    // In the order they appear, since the helper only scrolls down.
    await reveal('Tap timing');
    await reveal('Server address');
    await reveal('http://fake:4780');
    await reveal('Made by Aestra Studios');
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

    // A phone on its side: 800 x 360 logical. (At a computer's size the app
    // switches to its desktop layout, which has its own tests.)
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();

    // The row and the mini bar (the recently played rail above the list is
    // out of a short window's view).
    expect(find.text('Bassline'), findsAtLeastNWidgets(2));
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(player.playQueueCalls, 1);
  });

  testWidgets(
    'a computer-sized window gets the sidebar and the bottom player',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final player = FakeTunePlayer();
      await pumpApp(
        tester,
        _FakeClient(() async => _manifestOf(_library())),
        player,
      );
      expect(find.byType(DesktopSidebar), findsOneWidget);
      expect(find.byType(DesktopPlayBar), findsOneWidget);
      expect(find.byType(TunesNavBar), findsNothing);

      // The sidebar is the navigation.
      await tester.tap(
        find.descendant(
          of: find.byType(DesktopSidebar),
          matching: find.text('Library'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bassline'), findsWidgets);

      // Playing something fills the bottom player, and nothing overflows.
      await tester.tap(find.text('Bassline').first);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(DesktopPlayBar),
          matching: find.text('Bassline'),
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.pause_rounded), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  group('Now Playing on a computer', () {
    Future<void> open(WidgetTester tester, List<ManifestTrack> lib) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpApp(
        tester,
        _FakeClient(() async => _manifestOf(lib)),
        FakeTunePlayer(),
      );
      await tester.tap(
        find.descendant(
          of: find.byType(DesktopSidebar),
          matching: find.text('Library'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bassline').first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DesktopPlayBar),
          matching: find.text('Bassline'),
        ),
      );
      await tester.pumpAndSettle();
    }

    List<ManifestTrack> withLyrics() => [
      _track('Bassline', 'flac', 950000, lyrics: '[00:01.00]first line'),
      _track('Nightdrive', 'mp3', 320000),
    ];

    testWidgets('has the lyrics beside it, once, when the song has them', (
      tester,
    ) async {
      await open(tester, withLyrics());
      expect(find.byType(LyricsSheet), findsOneWidget);
      // not also as a strip under the controls
      expect(find.byType(LyricPreview), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not repeat the transport the bottom player already has', (
      tester,
    ) async {
      await open(tester, withLyrics());
      // one seek bar and one set of skip buttons: the bottom player's
      expect(find.byType(Scrubber), findsOneWidget);
      expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
    });

    testWidgets('does not offer Lyrics in the menu when they are beside it', (
      tester,
    ) async {
      await open(tester, withLyrics());
      await tester.tap(
        find.descendant(
          of: find.byType(NowPlayingPage),
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Track information'), findsOneWidget);
      expect(find.text('Lyrics'), findsNothing);
    });

    testWidgets('offers it when the song has none, as the way to add some', (
      tester,
    ) async {
      await open(tester, _library());
      await tester.tap(
        find.descendant(
          of: find.byType(NowPlayingPage),
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Lyrics'), findsOneWidget);
    });

    testWidgets('has no empty lyrics pane when the song has none', (
      tester,
    ) async {
      await open(tester, _library());
      expect(find.byType(LyricsSheet), findsNothing);
      expect(find.byType(LyricPreview), findsNothing);
      expect(find.byType(DesktopPlayBar), findsOneWidget);
    });

    testWidgets('hides the lyrics when the listener has turned them off', (
      tester,
    ) async {
      await settings.setShowLyrics(false);
      await open(tester, withLyrics());
      expect(find.byType(LyricsSheet), findsNothing);
    });
  });

  group('keyboard on a computer', () {
    Future<FakeTunePlayer> desktop(WidgetTester tester) async {
      Device.debugDesktop = true;
      addTearDown(() => Device.debugDesktop = false);
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final player = FakeTunePlayer();
      await pumpApp(
        tester,
        _FakeClient(() async => _manifestOf(_library())),
        player,
      );
      return player;
    }

    Future<void> tab(WidgetTester tester, String name) async {
      await tester.tap(
        find.descendant(
          of: find.byType(DesktopSidebar),
          matching: find.text(name),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('space pauses from a fresh start', (tester) async {
      final player = await desktop(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(player.toggleCalls, 1);
    });

    testWidgets('and after moving around the sidebar', (tester) async {
      final player = await desktop(tester);
      await tab(tester, 'Library');
      await tab(tester, 'Discover');
      await tab(tester, 'Home');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(player.toggleCalls, 1);
    });

    testWidgets('and after using the search box and leaving it', (
      tester,
    ) async {
      final player = await desktop(tester);
      await tab(tester, 'Search');
      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'bass');
      await tester.pumpAndSettle();
      await tab(tester, 'Home');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(player.toggleCalls, 1, reason: 'after leaving Search');
    });

    testWidgets('and after clicking empty space while a box has focus', (
      tester,
    ) async {
      final player = await desktop(tester);
      await tab(tester, 'Search');
      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      // click somewhere that is not a control
      await tester.tapAt(const Offset(900, 400));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(player.toggleCalls, 1, reason: 'after clicking away');
    });

    testWidgets('but typing in the search box is still typing', (tester) async {
      final player = await desktop(tester);
      await tab(tester, 'Search');
      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      expect(player.toggleCalls, 0);
    });

    testWidgets('and after a track is played from the list', (tester) async {
      final player = await desktop(tester);
      await tab(tester, 'Library');
      await tester.tap(find.text('Bassline').first);
      await tester.pumpAndSettle();
      final before = player.toggleCalls;
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(player.toggleCalls, before + 1);
    });
  });

  testWidgets('a phone-sized window keeps the tab bar and no sidebar', (
    tester,
  ) async {
    final player = FakeTunePlayer();
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf(_library())),
      player,
    );
    expect(find.byType(DesktopSidebar), findsNothing);
    expect(find.byType(TunesNavBar), findsOneWidget);
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

    expect(find.byType(NowPlayingPage), findsOneWidget);
    expect(find.text('Up next'), findsNothing); // queue is a secondary surface
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
  });

  group('Now Playing on a phone', () {
    Future<void> open(WidgetTester tester, List<ManifestTrack> lib) async {
      await pumpApp(
        tester,
        _FakeClient(() async => _manifestOf(lib)),
        FakeTunePlayer(),
      );
      await goToLibrary(tester);
      await tester.tap(find.text('Bassline'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bassline').last);
      await tester.pumpAndSettle();
    }

    testWidgets('shows the lyric strip only when there are lyrics', (
      tester,
    ) async {
      await open(tester, _library());
      expect(find.byType(LyricPreview), findsNothing);
    });

    testWidgets('shows it for a song that has them', (tester) async {
      await open(tester, [
        _track('Bassline', 'flac', 950000, lyrics: '[00:01.00]first line'),
        _track('Nightdrive', 'mp3', 320000),
      ]);
      expect(find.byType(LyricPreview), findsOneWidget);
    });

    testWidgets('and not when the listener has turned lyrics off', (
      tester,
    ) async {
      await settings.setShowLyrics(false);
      await open(tester, [
        _track('Bassline', 'flac', 950000, lyrics: '[00:01.00]first line'),
        _track('Nightdrive', 'mp3', 320000),
      ]);
      expect(find.byType(LyricPreview), findsNothing);
    });

    testWidgets(
      'the page below has no lyrics section, and The file says how good it is',
      (tester) async {
        await open(tester, [
          _track('Bassline', 'flac', 950000, lyrics: '[00:01.00]first line'),
          _track('Nightdrive', 'mp3', 320000),
        ]);
        await tester.drag(find.byType(NowPlayingPage), const Offset(0, -2000));
        await tester.pumpAndSettle();
        expect(find.text('Lyrics'), findsNothing);
        expect(find.text('The file'), findsOneWidget);
        expect(find.text('Lossless'), findsOneWidget);
        expect(find.text('FLAC'), findsOneWidget);
      },
    );
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

  // The queue sheet subscribes to QueueStore.watch(), a drift stream
  // query. When the test's widget tree is torn down, the StreamBuilder
  // unsubscribes; drift's StreamQueryStore.markAsClosed races with
  // the next test's setup, throwing "Bad state: Cannot add event while
  // adding stream." This is harmless in production (drift handles its
  // own isolate lifecycle) but trips the widget test runner. The
  // sheet's render path is covered by manual dogfooding on the phone.
  testWidgets('queue sheet renders from persistent queue', (tester) async {
    final player = FakeTunePlayer();
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf(_library())),
      player,
    );
    await goToLibrary(tester);

    // Seed the persistent queue directly. Calling playQueue here
    // would race the async write to the queue store; for this test
    // we just need the queue store to know about one track.
    await queueStore.replace(['a' * 64]);
    await tester.pumpAndSettle();

    // Open Now Playing via the mini-player (it's the bottom bar
    // showing the currently-playing track).
    await tester.tap(find.text('Bassline'));
    await tester.pumpAndSettle();
    // The mini-player has its own Bassline text; tap the one in the
    // mini-player (the last one in the tree) to open Now Playing.
    await tester.tap(find.text('Bassline').last);
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingPage), findsOneWidget);

    // Open the Now Playing page's menu and tap "Queue".
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Queue'));
    await tester.pumpAndSettle();

    expect(find.text('Queue'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);
    // The sheet's _QueueRow renders the seeded track title. We can't
    // scope the finder to the sheet (it's a private widget), but the
    // count of 'Bassline' in the tree tells us the row rendered: 1
    // for the Now Playing header + 1 for the sheet row. If the row
    // were missing, the count would be 1, not 2.
    expect(find.text('Bassline'), findsNWidgets(2));
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

    expect(find.byType(PlayingBars), findsNothing);

    await tester.tap(find.text('Bassline'));
    await tester.pumpAndSettle();

    expect(find.byType(PlayingBars), findsOneWidget);
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
    // The dock is on screen now, so the card can sit below the fold of a
    // short test surface, as it would on a small phone: scroll to it first.
    // The record's tile in the discography: the album's name also sits
    // under its song in Top songs, above it.
    await tester.ensureVisible(find.text('ESCAPE PLAN / MAFIA').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ESCAPE PLAN / MAFIA').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('MAFIA').first);
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

    expect(find.byIcon(Icons.arrow_circle_down_outlined), findsNWidgets(2));

    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.arrow_circle_down_outlined).first);
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pumpAndSettle();

    // On the phone now: the green tick, where the arrow was.
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
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
    // Three missed answers in a row, not one: a single slow reply is not an
    // outage.
    await hb.probe();
    await hb.probe();
    expect(reach.offline, isFalse);
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

    expect(find.text('Showing what is on this phone'), findsOneWidget);

    // Offline the library is what is on the phone: a song that was never
    // downloaded is not offered at all, rather than shown and dead.
    expect(find.text('Bassline'), findsNothing);
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
    expect(find.text('Showing what is on this phone'), findsOneWidget);

    reach.setOffline(false);
    await tester.pumpAndSettle();
    expect(find.text('Showing what is on this phone'), findsNothing);
  });

  testWidgets(
    'a release holding more tracks than its total drops the fraction',
    (tester) async {
      // The live library has a 35-track release whose enriched total says 22.
      // "35/22 tracks - complete" asserts a completeness we cannot vouch for,
      // so the page counts what is actually here instead.
      final tracks = [
        _track('One', 'flac', 950000, sha: 'a' * 64, releaseId: 'rel-over'),
        _track('Two', 'flac', 950000, sha: 'b' * 64, releaseId: 'rel-over'),
        _track('Three', 'flac', 950000, sha: 'c' * 64, releaseId: 'rel-over'),
      ];
      final manifest = TunesManifest(
        tracks: tracks,
        releases: [
          ManifestRelease(
            id: 'rel-over',
            title: 'OVERSTUFFED',
            artist: 'Artist',
            year: '2026',
            artSha: null,
            type: 'album',
            totalTracks: 2,
            trackShas: ['a' * 64, 'b' * 64, 'c' * 64],
          ),
        ],
      );
      await pumpApp(
        tester,
        _FakeClient(() async => manifest),
        FakeTunePlayer(),
      );
      await tester.tap(find.text('OVERSTUFFED').first);
      await tester.pumpAndSettle();
      expect(find.text('3 songs'), findsOneWidget);
      expect(find.textContaining('3/2'), findsNothing);
      expect(find.textContaining('complete'), findsNothing);
    },
  );

  testWidgets('missing albums come from the daemon, not from track counts', (
    tester,
  ) async {
    // Deciding an album is absent entirely needs the artist discographies,
    // which only the daemon holds. The app must not try to derive it.
    final client = _FakeClient(
      () async => _manifestOf(_library()),
      onMissing: () async => const [
        MissingRelease(
          id: 'g1',
          title: 'UTOPIA',
          artist: 'Travis Scott',
          type: 'Album',
          year: '2023',
          artistTracks: 17,
        ),
      ],
    );
    await pumpApp(tester, client, FakeTunePlayer());
    await tester.pumpAndSettle();
    expect(find.text('Missing from your collection'), findsOneWidget);
    expect(find.text('UTOPIA'), findsOneWidget);
    expect(find.textContaining('Travis Scott'), findsWidgets);
  });

  testWidgets('the missing section stays away when there is nothing to say', (
    tester,
  ) async {
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf(_library())),
      FakeTunePlayer(),
    );
    await tester.pumpAndSettle();
    expect(find.text('Missing from your collection'), findsNothing);
  });

  testWidgets('a missing album shows its real cover when one was fetched', (
    tester,
  ) async {
    // The daemon fetches sleeves from Deezer for records we do not have; a
    // null artSha is ordinary and must fall back rather than break the rail.
    final client = _FakeClient(
      () async => _manifestOf(_library()),
      onMissing: () async => const [
        MissingRelease(
          id: 'g1',
          title: 'UTOPIA',
          artist: 'Travis Scott',
          type: 'Album',
          year: '2023',
          artistTracks: 17,
          artSha: 'c0ffee',
        ),
        MissingRelease(
          id: 'g2',
          title: 'Rodeo',
          artist: 'Travis Scott',
          type: 'Album',
          year: '2015',
          artistTracks: 17,
        ),
      ],
    );
    await pumpApp(tester, client, FakeTunePlayer());
    await tester.pumpAndSettle();
    expect(find.text('UTOPIA'), findsOneWidget);
    expect(find.text('Rodeo'), findsOneWidget);
    // The one without a cover falls back to the generated tile, labelled by
    // the album so a rail of one act does not repeat the same initial.
    expect(find.text('R'), findsOneWidget);
  });
  testWidgets('a pushed album page can reach the download scope', (
    tester,
  ) async {
    // The regression: DownloadScope was created inside AppShell, which is
    // MaterialApp's `home`, while album and artist pages are pushed onto the
    // root Navigator -- an ancestor of `home`. So maybeOf returned null on
    // those routes, the row never rebuilt on progress, and tapping download
    // did nothing visible until you left and came back.
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
          totalTracks: 1,
          trackShas: ['a' * 64],
        ),
      ],
    );
    await pumpApp(tester, _FakeClient(() async => manifest), FakeTunePlayer());
    await tester.tap(find.text('Life of a DON').first);
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(AlbumPage));
    final DownloadManager? seen = DownloadScope.maybeOf(context);
    expect(
      seen,
      isNotNull,
      reason: 'a pushed route must still be inside DownloadScope',
    );
  });

  testWidgets('re-tapping the active tab returns its list to the top', (
    tester,
  ) async {
    // Tapping Home twice doing nothing was the complaint. The mechanism is
    // per-tab (a fresh content key remounts the scrollable at offset zero),
    // so the library's long track list proves it best; every tab shares the
    // same path.
    final tracks = List.generate(
      14,
      (i) => _track(
        'Song $i',
        'flac',
        200000 + i,
        sha: 'song$i'.padRight(64, '0'),
        releaseId: 'rel-$i',
      ),
    );
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf(tracks)),
      FakeTunePlayer(),
    );
    await goToLibrary(tester);

    final list = find.byType(ListView);
    expect(list, findsOneWidget);
    ScrollableState scroller() => tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)),
    );
    await tester.drag(list, const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(scroller().position.pixels, greaterThan(0));

    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    expect(scroller().position.pixels, 0);
  });

  testWidgets('backgrounding pins the exact resume point', (tester) async {
    // The periodic saver runs every five seconds; without a save on the way
    // out, closing could lose most of a track's progress.
    final player = FakeTunePlayer();
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf(_library())),
      player,
    );
    await goToLibrary(tester);
    await tester.tap(find.text('Bassline'));
    await tester.pumpAndSettle();

    player.seek(const Duration(minutes: 1));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    expect(settings.lastPlayedSha, 'a' * 64);
    expect(settings.lastPosition, const Duration(minutes: 1));
  });

  testWidgets('radio continues the queue after the last track', (tester) async {
    final player = FakeTunePlayer();
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf(_library())),
      player,
    );
    await goToLibrary(tester);
    await tester.tap(find.text('Bassline'));
    await tester.pumpAndSettle();

    final last = player.current!;
    final pick = await player.onQueueEnded!(last);
    // Two tracks in the library, one playing: the other is the only answer.
    expect(pick?.sha, 'b' * 64);
  });

  testWidgets('radio off ends the queue in silence', (tester) async {
    final player = FakeTunePlayer();
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf(_library())),
      player,
    );
    await settings.setRadioAutoplay(false);
    await goToLibrary(tester);
    await tester.tap(find.text('Bassline'));
    await tester.pumpAndSettle();

    expect(await player.onQueueEnded!(player.current!), isNull);
  });

  testWidgets('offline radio only offers what is downloaded', (tester) async {
    final reach = Reachability();
    final player = FakeTunePlayer();
    await tester.runAsync(() async {
      await store.add('a' * 64, '${tempDir.path}/bassline');
      await store.add('b' * 64, '${tempDir.path}/nightdrive');
    });
    await pumpApp(
      tester,
      _FakeClient(() async => _manifestOf(_library())),
      player,
      reachability: reach,
    );
    await goToLibrary(tester);
    reach.setOffline(true);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bassline'));
    await tester.pumpAndSettle();
    expect(player.current?.title, 'Bassline');
    // Both are on the device, so the other one is playable.
    expect((await player.onQueueEnded!(player.current!))?.title, 'Nightdrive');
  });

  testWidgets('offline radio ends the queue when nothing else is downloaded', (
    tester,
  ) async {
    final reach = Reachability();
    final player = FakeTunePlayer();
    await tester.runAsync(
      () => store.add('a' * 64, '${tempDir.path}/bassline'),
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

    await tester.tap(find.text('Bassline'));
    await tester.pumpAndSettle();
    // The only downloaded track is the one playing: offering anything else
    // would be offering something that cannot play.
    expect(await player.onQueueEnded!(player.current!), isNull);
  });
}
