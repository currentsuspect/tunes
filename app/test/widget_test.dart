import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/audio/tune_player.dart';
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
}

class FakeTunePlayer extends TunePlayer {
  List<ManifestTrack> _queue = const [];
  int _index = -1;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  int playQueueCalls = 0;
  int toggleCalls = 0;
  int seekCalls = 0;

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

  int nextCalls = 0;
  int previousCalls = 0;
  int playAtCalls = 0;
  int playCalls = 0;
  int pauseCalls = 0;

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
    _position = Duration.zero;
    notifyListeners();
  }

  @override
  void toggle() {
    toggleCalls += 1;
    _playing = !_playing;
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

ManifestTrack _track(String title, String codec, int bitrate) => ManifestTrack(
  sha: 'a' * 64,
  size: 1000,
  codec: codec,
  sampleRate: 44100,
  channels: 2,
  bitrate: bitrate,
  durationMs: 125000,
  title: title,
  artist: 'Artist',
  album: 'Album',
  year: null,
);

List<ManifestTrack> _library() => [
  _track('Bassline', 'flac', 950000),
  _track('Nightdrive', 'mp3', 320000),
];

void main() {
  testWidgets('renders tracks from the manifest', (tester) async {
    final client = _FakeClient(() async => _library());
    await tester.pumpWidget(TunesApp(client: client, player: FakeTunePlayer()));
    await tester.pumpAndSettle();

    expect(find.text('Bassline'), findsOneWidget);
    expect(find.text('FLAC 950k'), findsOneWidget);
    expect(find.text('MP3 320k'), findsOneWidget);
  });

  testWidgets('shows the honest empty state when the daemon is unreachable', (
    tester,
  ) async {
    final client = _FakeClient(
      () async => throw TunesFetchException('unreachable'),
    );
    await tester.pumpWidget(TunesApp(client: client, player: FakeTunePlayer()));
    await tester.pumpAndSettle();

    expect(find.text('No library yet'), findsOneWidget);
    expect(find.textContaining('tunesd is not answering'), findsOneWidget);
  });

  testWidgets('empty manifest shows the no-tracks state', (tester) async {
    final client = _FakeClient(() async => []);
    await tester.pumpWidget(TunesApp(client: client, player: FakeTunePlayer()));
    await tester.pumpAndSettle();

    expect(find.text('No Tracks yet'), findsOneWidget);
  });

  testWidgets('tab switch swaps the not-yet label', (tester) async {
    final client = _FakeClient(() async => []);
    await tester.pumpWidget(TunesApp(client: client, player: FakeTunePlayer()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();

    expect(find.text('Albums coming in M4'), findsOneWidget);
  });

  testWidgets('tapping a row starts playback on that track', (tester) async {
    final player = FakeTunePlayer();
    final client = _FakeClient(() async => _library());
    await tester.pumpWidget(TunesApp(client: client, player: player));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nightdrive'));
    await tester.pumpAndSettle();

    expect(player.playQueueCalls, 1);
    expect(player.index, 1);
    expect(player.current?.title, 'Nightdrive');
    expect(find.textContaining('playing'), findsOneWidget);
  });

  testWidgets('mini bar toggle and seek reach the player', (tester) async {
    final player = FakeTunePlayer();
    final client = _FakeClient(() async => _library());
    await tester.pumpWidget(TunesApp(client: client, player: player));
    await tester.pumpAndSettle();

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
    final client = _FakeClient(() async => _library());
    await tester.pumpWidget(TunesApp(client: client, player: player));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bassline'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();

    expect(
      find.text('Bassline'),
      findsNWidgets(2),
    ); // track row + mini bar both alive
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(player.index, 0);
    expect(player.playQueueCalls, 1);
  });

  testWidgets('stop clears the mini bar', (tester) async {
    final player = FakeTunePlayer();
    final client = _FakeClient(() async => _library());
    await tester.pumpWidget(TunesApp(client: client, player: player));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bassline'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(player.stopCalls, 1);
    expect(find.byIcon(Icons.pause_rounded), findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });

  testWidgets('tapping the mini bar opens the full Now Playing page', (
    tester,
  ) async {
    final player = FakeTunePlayer();
    final client = _FakeClient(() async => _library());
    await tester.pumpWidget(TunesApp(client: client, player: player));
    await tester.pumpAndSettle();

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
    final client = _FakeClient(() async => _library());
    await tester.pumpWidget(TunesApp(client: client, player: player));
    await tester.pumpAndSettle();

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
    final client = _FakeClient(() async => _library());
    await tester.pumpWidget(TunesApp(client: client, player: player));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bassline'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bassline').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nightdrive').last);
    expect(player.playAtCalls, 1);
    expect(player.index, 1);
  });
}
