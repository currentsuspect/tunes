import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/audio/tune_player.dart';
import 'package:tunes/core/sync/now_sync.dart';
import 'package:tunes/core/sync/sync_models.dart';
import 'package:tunes/domain/manifest.dart';

ManifestTrack _t(String c) => ManifestTrack(
  sha: c * 64,
  size: 1,
  codec: 'flac',
  sampleRate: 44100,
  channels: 2,
  bitrate: 1,
  durationMs: 180000,
  title: 'T$c',
  artist: 'A',
  album: 'B',
  year: null,
  artSha: null,
  releaseId: null,
  trackNumber: null,
  discNumber: null,
);

class _Player extends TunePlayer {
  List<ManifestTrack> q = [_t('a'), _t('b')];
  int i = 0;
  bool isPlaying = false;
  Duration pos = const Duration(seconds: 42);

  void change(void Function() f) {
    f();
    notifyListeners();
  }

  @override
  List<ManifestTrack> get queue => q;
  @override
  int get index => i;
  @override
  bool get playing => isPlaying;
  @override
  Duration get position => pos;
  @override
  Duration get duration => const Duration(minutes: 3);
  @override
  ManifestTrack? get current => q.isEmpty ? null : q[i];
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
  void seek(Duration target) {}
  @override
  void stop() {}
  @override
  void setRepeat(PlaybackRepeat mode) {}
  @override
  void setShuffle(bool on) {}
}

void main() {
  group('NowPublisher', () {
    testWidgets('says nothing about a queue that was only restored', (
      tester,
    ) async {
      final player = _Player();
      final sent = <List<SyncDoc>>[];
      final pub = NowPublisher(
        player: player,
        push: (d) async {
          sent.add(d);
          return true;
        },
      )..start();
      player.change(() {}); // a restore notifies, paused
      await tester.pump(const Duration(seconds: 40));
      expect(sent, isEmpty);
      pub.dispose();
    });

    testWidgets(
      'reports where it is once the listener plays, and when they pause',
      (tester) async {
        final player = _Player();
        final sent = <List<SyncDoc>>[];
        final pub = NowPublisher(
          player: player,
          push: (d) async {
            sent.add(d);
            return true;
          },
        )..start();

        player.change(() => player.isPlaying = true);
        await tester.pump(const Duration(seconds: 1));
        expect(sent.length, 1);
        final now = jsonDecode(
          sent.first.firstWhere((d) => d.key == 'now').value!,
        ) as Map;
        expect(now['sha'], 'a' * 64);
        expect(now['positionMs'], 42000);
        expect(now['playing'], true);
        expect(sent.first.any((d) => d.key == 'queue'), isTrue);

        // The heartbeat while playing carries the position but not the queue again.
        player.pos = const Duration(seconds: 57);
        await tester.pump(const Duration(seconds: 8));
        expect(sent.length, 2);
        expect(sent.last.any((d) => d.key == 'queue'), isFalse);
        expect(jsonDecode(sent.last.single.value!)['positionMs'], 57000);

        player.change(() => player.isPlaying = false);
        await tester.pump(const Duration(seconds: 1));
        expect(jsonDecode(sent.last.first.value!)['playing'], false);
        pub.dispose();
      },
    );

    testWidgets('keeps trying when the server cannot be reached', (
      tester,
    ) async {
      final player = _Player();
      var ok = false;
      var tries = 0;
      final pub = NowPublisher(
        player: player,
        push: (d) async {
          tries += 1;
          return ok;
        },
      )..start();
      player.change(() => player.isPlaying = true);
      await tester.pump(const Duration(seconds: 1));
      expect(tries, 1);
      ok = true;
      await tester.pump(const Duration(seconds: 8));
      expect(tries, 2);
      pub.dispose();
    });
  });

  group('RemoteNow', () {
    SyncDoc now(String device, {bool playing = true, int at = 100000}) =>
        SyncDoc(
          key: 'now',
          value: jsonEncode({
            'sha': 'a' * 64,
            'index': 1,
            'positionMs': 30000,
            'playing': playing,
          }),
          updatedAt: at,
          deviceId: device,
        );

    test('ignores what this device itself said', () {
      final r = RemoteNow()..ingest(now('phone'), {'phone': 'Phone'}, 'phone');
      expect(r.hasState, isFalse);
    });

    test('goes quiet once this device has played after the other one', () {
      final r = RemoteNow()
        ..ingest(now('laptop', at: 100000), const {}, 'phone');
      expect(r.hasState, isTrue);
      r.ingest(now('phone', at: 200000), const {}, 'phone');
      expect(r.hasState, isFalse);
    });

    test('names the other device and estimates where it has got to', () {
      final r = RemoteNow()
        ..ingest(now('laptop'), {'laptop': 'Laptop'}, 'phone');
      expect(r.deviceLabel, 'Laptop');
      expect(r.isLive(100000 + 20000), isTrue);
      expect(r.isLive(100000 + 60000), isFalse);
      expect(r.estimatedPosition(100000 + 10000), const Duration(seconds: 40));
    });

    test('a paused device is where it stopped, not still moving', () {
      final r = RemoteNow()
        ..ingest(now('laptop', playing: false), const {}, 'phone');
      expect(r.estimatedPosition(100000 + 10000), const Duration(seconds: 30));
      expect(r.isLive(100000 + 1000), isFalse);
    });

    test('continues with the queue only when it is the same device\'s', () {
      final r = RemoteNow()..ingest(now('laptop'), const {}, 'phone');
      expect(r.queueToContinue, ['a' * 64]);
      r.ingest(
        SyncDoc(
          key: 'queue',
          value: jsonEncode({
            'shas': ['b' * 64, 'a' * 64],
          }),
          updatedAt: 1,
          deviceId: 'tablet',
        ),
        const {},
        'phone',
      );
      expect(r.queueToContinue, ['a' * 64]);
      r.ingest(
        SyncDoc(
          key: 'queue',
          value: jsonEncode({
            'shas': ['b' * 64, 'a' * 64],
          }),
          updatedAt: 1,
          deviceId: 'laptop',
        ),
        const {},
        'phone',
      );
      expect(r.queueToContinue, ['b' * 64, 'a' * 64]);
    });
  });
}
