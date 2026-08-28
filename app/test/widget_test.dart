import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/audio/tune_player.dart';
import 'package:tunes/core/data/download_store.dart';
import 'package:tunes/core/data/reachability.dart';
import 'package:tunes/core/net/tunes_client.dart';
import 'package:tunes/domain/manifest.dart';
import 'package:tunes/main.dart';

class _FakeClient implements TunesClient {
  _FakeClient(this.result);

  final Future<List<ManifestTrack>> Function() result;

  @override
  String get baseUrl => 'http://fake:4780';

  @override
  Future<List<ManifestTrack>> fetchManifest() => result();

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
}) => ManifestTrack(
  sha: title == 'Bassline' ? 'a' * 64 : 'b' * 64,
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
);

List<ManifestTrack> _library() => [
  _track('Bassline', 'flac', 950000),
  _track('Nightdrive', 'mp3', 320000),
];

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
      _FakeClient(() async => _library()),
      FakeTunePlayer(),
    );

    expect(find.text('2'), findsWidgets); // tracks count
    expect(find.text('tracks'), findsOneWidget);
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
    await pumpApp(tester, _FakeClient(() async => []), FakeTunePlayer());

    expect(
      find.textContaining('No library yet — channels are configured'),
      findsOneWidget,
    );
  });

  testWidgets('library tab lists tracks with quality badges', (tester) async {
    await pumpApp(
      tester,
      _FakeClient(() async => _library()),
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
    await pumpApp(tester, _FakeClient(() async => _library()), player);
    await goToLibrary(tester);

    await tester.tap(find.text('Nightdrive'));
    await tester.pumpAndSettle();

    expect(player.playQueueCalls, 1);
    expect(player.index, 1);
    expect(player.current?.title, 'Nightdrive');
    expect(find.textContaining('playing'), findsOneWidget);
  });

  testWidgets('playing records recents on the home tab', (tester) async {
    final player = FakeTunePlayer();
    await pumpApp(tester, _FakeClient(() async => _library()), player);
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

  testWidgets('artist chip on home filters the library', (tester) async {
    await pumpApp(
      tester,
      _FakeClient(() async => [_track('One', 'flac', 950000, artist: 'Vax')]),
      FakeTunePlayer(),
    );

    await tester.tap(find.text('Vax'));
    await tester.pumpAndSettle();

    expect(find.text('One'), findsOneWidget);
  });

  testWidgets('search filters and plays results', (tester) async {
    final player = FakeTunePlayer();
    await pumpApp(tester, _FakeClient(() async => _library()), player);

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

  testWidgets('profile sheet opens from the avatar', (tester) async {
    await pumpApp(
      tester,
      _FakeClient(() async => _library()),
      FakeTunePlayer(),
    );

    await tester.tap(find.byIcon(Icons.person_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Daemon'), findsOneWidget);
    expect(find.text('http://fake:4780'), findsOneWidget);
    expect(find.text('Library'), findsWidgets);
  });

  testWidgets('mini bar toggle and seek reach the player', (tester) async {
    final player = FakeTunePlayer();
    await pumpApp(tester, _FakeClient(() async => _library()), player);
    await goToLibrary(tester);

    await tester.tap(find.text('Bassline'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.pause_rounded));
    expect(player.toggleCalls, 1);

    await tester.tap(find.byType(Slider));
    expect(player.seekCalls, greaterThan(0));
  });

  testWidgets('orientation change keeps the mini bar on the same player', (
    tester,
  ) async {
    final player = FakeTunePlayer();
    await pumpApp(tester, _FakeClient(() async => _library()), player);
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

  testWidgets('stop clears the mini bar', (tester) async {
    final player = FakeTunePlayer();
    await pumpApp(tester, _FakeClient(() async => _library()), player);
    await goToLibrary(tester);

    await tester.tap(find.text('Bassline'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(player.stopCalls, 1);
    expect(find.byIcon(Icons.pause_rounded), findsNothing);
  });

  testWidgets('tapping the mini bar opens the full Now Playing page', (
    tester,
  ) async {
    final player = FakeTunePlayer();
    await pumpApp(tester, _FakeClient(() async => _library()), player);
    await goToLibrary(tester);

    await tester.tap(find.text('Bassline'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bassline').last);
    await tester.pumpAndSettle();

    expect(find.text('Now Playing'), findsOneWidget);
    expect(find.text('Up next'), findsOneWidget);
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
  });

  testWidgets('full page controls reach the player', (tester) async {
    final player = FakeTunePlayer();
    await pumpApp(tester, _FakeClient(() async => _library()), player);
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

  testWidgets('queue list jumps to a tapped track', (tester) async {
    final player = FakeTunePlayer();
    await pumpApp(tester, _FakeClient(() async => _library()), player);
    await goToLibrary(tester);

    await tester.tap(find.text('Bassline'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bassline').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nightdrive').last);
    expect(player.playAtCalls, 1);
    expect(player.index, 1);
  });

  testWidgets('download icon downloads and marks the track offline-ready', (
    tester,
  ) async {
    await pumpApp(
      tester,
      _FakeClient(() async => _library()),
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
      _FakeClient(() async => _library()),
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
      _FakeClient(() async => _library()),
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
