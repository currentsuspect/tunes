import 'package:flutter_test/flutter_test.dart';
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

void main() {
  testWidgets('renders tracks from the manifest', (tester) async {
    final client = _FakeClient(
      () async => [
        _track('Bassline', 'flac', 950000),
        _track('Nightdrive', 'mp3', 320000),
      ],
    );
    await tester.pumpWidget(TunesApp(client: client));
    await tester.pumpAndSettle();

    expect(find.text('Bassline'), findsOneWidget);
    expect(find.text('FLAC 950k'), findsOneWidget);
    expect(find.text('mp3'), findsNothing);
    expect(find.text('MP3 320k'), findsOneWidget);
  });

  testWidgets('shows the honest empty state when the daemon is unreachable', (
    tester,
  ) async {
    final client = _FakeClient(
      () async => throw TunesFetchException('unreachable'),
    );
    await tester.pumpWidget(TunesApp(client: client));
    await tester.pumpAndSettle();

    expect(find.text('No library yet'), findsOneWidget);
    expect(find.textContaining('tunesd is not answering'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('empty manifest shows the no-tracks state', (tester) async {
    final client = _FakeClient(() async => []);
    await tester.pumpWidget(TunesApp(client: client));
    await tester.pumpAndSettle();

    expect(find.text('No Tracks yet'), findsOneWidget);
  });

  testWidgets('tab switch swaps the not-yet label', (tester) async {
    final client = _FakeClient(() async => []);
    await tester.pumpWidget(TunesApp(client: client));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();

    expect(find.text('Albums coming in M4'), findsOneWidget);
  });
}
