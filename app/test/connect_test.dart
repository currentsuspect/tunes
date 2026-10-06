import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/audio/tune_player.dart';
import 'package:tunes/core/sync/connect_control.dart';
import 'package:tunes/core/sync/connect_player.dart';
import 'package:tunes/core/sync/now_sync.dart';
import 'package:tunes/core/sync/sync_engine.dart';
import 'package:tunes/core/sync/sync_models.dart';
import 'package:tunes/domain/manifest.dart';

import 'support/fake_sync_server.dart';

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

class _Local extends TunePlayer {
  List<ManifestTrack> q = [];
  int i = 0;
  bool isPlaying = false;
  Duration pos = Duration.zero;
  final calls = <String>[];

  void set(void Function() f) {
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
  void playQueue(List<ManifestTrack> tracks, int startIndex) {
    calls.add('playQueue');
    set(() {
      q = tracks;
      i = startIndex;
      isPlaying = true;
    });
  }

  @override
  void restoreQueue(
    List<ManifestTrack> tracks,
    int startIndex, {
    Duration at = Duration.zero,
  }) {
    calls.add('restore@${at.inSeconds}');
    q = tracks;
    i = startIndex;
    pos = at;
  }

  @override
  void play() => set(() {
    calls.add('play');
    isPlaying = true;
  });
  @override
  void pause() => set(() {
    calls.add('pause');
    isPlaying = false;
  });
  @override
  void toggle() {}
  @override
  void next() => calls.add('next');
  @override
  void previous() => calls.add('previous');
  @override
  void playAt(int index) => calls.add('playAt$index');
  @override
  void seek(Duration target) => calls.add('seek${target.inSeconds}');
  @override
  void stop() {}
  @override
  void setRepeat(PlaybackRepeat mode) {}
  @override
  void setShuffle(bool on) {}
}

void main() {
  late _Local local;
  late RemoteNow remote;
  late List<SyncDoc> sent;
  late int clock;
  late ConnectPlayer player;
  final library = {
    for (final c in ['a', 'b', 'c']) c * 64: _t(c),
  };

  SyncDoc nowDoc({bool playing = true, int at = 1000000, int since = 900000}) =>
      SyncDoc(
        key: 'now',
        value: jsonEncode({
          'sha': 'b' * 64,
          'index': 1,
          'positionMs': 30000,
          'playing': playing,
          'since': since,
        }),
        updatedAt: at,
        deviceId: 'phone',
      );

  void remoteSays(SyncDoc d) => remote.ingest(d, {'phone': 'Phone'}, 'pc');

  setUp(() {
    local = _Local();
    remote = RemoteNow();
    sent = [];
    clock = 1005000;
    player = ConnectPlayer(
      local: local,
      remote: remote,
      resolve: (s) => library[s],
      serverNow: () => clock,
      send: (d) async {
        sent.add(d);
        return true;
      },
    );
  });

  tearDown(() => player.dispose());

  testWidgets('with nothing playing elsewhere it is simply the local player', (
    tester,
  ) async {
    expect(player.isRemote, isFalse);
    expect(player.remoteDeviceLabel, isNull);
    player.playQueue([_t('a')], 0);
    expect(local.calls, ['playQueue']);
  });

  testWidgets(
    'shows the other device\'s music, keeps its playhead moving, and is silent',
    (tester) async {
      remoteSays(nowDoc());
      remote.ingest(
        SyncDoc(
          key: 'queue',
          value: jsonEncode({
            'shas': ['a' * 64, 'b' * 64, 'c' * 64],
          }),
          updatedAt: 1,
          deviceId: 'phone',
        ),
        const {},
        'pc',
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(player.isRemote, isTrue);
      expect(player.remoteDeviceLabel, 'Phone');
      expect(player.current!.sha, 'b' * 64);
      expect(player.index, 1);
      expect(player.playing, isTrue);
      // 5 s since the report, so 30 s + 5 s
      expect(player.position, const Duration(seconds: 35));
      clock += 10000;
      expect(player.position, const Duration(seconds: 45));
      expect(local.calls, isEmpty);
    },
  );

  testWidgets(
    'pause sends a command to the playing device and shows paused at once',
    (tester) async {
      remoteSays(nowDoc());
      await tester.pump(const Duration(milliseconds: 300));
      player.pause();
      expect(player.playing, isFalse);
      await tester.pump();
      final cmd = jsonDecode(sent.single.value!) as Map;
      expect(sent.single.key, 'cmd');
      expect(cmd['to'], 'phone');
      expect(cmd['action'], 'pause');
      expect(local.calls, isEmpty);

      player.seek(const Duration(seconds: 90));
      expect((jsonDecode(sent.last.value!) as Map)['positionMs'], 90000);
      player.next();
      expect((jsonDecode(sent.last.value!) as Map)['action'], 'next');
    },
  );

  testWidgets(
    'a paused session stays for a few minutes, so it can be resumed, then goes',
    (tester) async {
      remoteSays(nowDoc(playing: false, at: 1000000));
      await tester.pump(const Duration(milliseconds: 300));
      expect(player.isRemote, isTrue);
      clock = 1000000 + 4 * 60 * 1000;
      await tester.pump(const Duration(milliseconds: 300));
      expect(player.isRemote, isFalse);
    },
  );

  testWidgets('playing something here ends the remote view', (tester) async {
    remoteSays(nowDoc());
    await tester.pump(const Duration(milliseconds: 300));
    expect(player.isRemote, isTrue);
    player.playQueue([_t('c')], 0);
    await tester.pump(const Duration(milliseconds: 300));
    expect(player.isRemote, isFalse);
    expect(player.current!.sha, 'c' * 64);
  });

  testWidgets(
    'play here carries on locally from the same second and pauses the other',
    (tester) async {
      remoteSays(nowDoc());
      remote.ingest(
        SyncDoc(
          key: 'queue',
          value: jsonEncode({
            'shas': ['a' * 64, 'b' * 64],
          }),
          updatedAt: 1,
          deviceId: 'phone',
        ),
        const {},
        'pc',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await player.playHere();
      expect(local.calls, ['restore@35', 'play']);
      expect(local.i, 1);
      expect((jsonDecode(sent.single.value!) as Map)['action'], 'pause');
      expect(player.isRemote, isFalse);
    },
  );

  testWidgets(
    'a heartbeat from the other device does not take the screen back after playing here',
    (tester) async {
      remoteSays(nowDoc(at: 1000000, since: 900000));
      await tester.pump(const Duration(milliseconds: 300));
      expect(player.isRemote, isTrue);
      player.playQueue([_t('c')], 0);
      // this device's audio has a gap (a track loading) ...
      local.set(() => local.isPlaying = false);
      // ... and the other device reports again, later but still the same session
      clock += 8000;
      remoteSays(nowDoc(at: clock, since: 900000));
      await tester.pump(const Duration(milliseconds: 300));
      expect(player.isRemote, isFalse);
      expect(player.current!.sha, 'c' * 64);
      // a session that began after this one did is a real new one
      remoteSays(nowDoc(at: clock + 1000, since: clock + 500));
      await tester.pump(const Duration(milliseconds: 300));
      expect(player.isRemote, isTrue);
    },
  );

  testWidgets('a command nobody answers makes the remote say so', (
    tester,
  ) async {
    remoteSays(nowDoc());
    await tester.pump(const Duration(milliseconds: 300));
    player.pause();
    expect(player.remoteStalled, isFalse);
    clock += 6000;
    expect(player.remoteStalled, isTrue);
    remoteSays(nowDoc(playing: false, at: clock));
    expect(player.remoteStalled, isFalse);
  });

  group('ConnectControl', () {
    late ConnectControl control;
    late int now;

    setUp(() {
      now = 1000000;
      final server = FakeSyncServer()..clock = now;
      control = ConnectControl(
        local: local,
        engine: SyncEngine(
          transport: server.as('pc'),
          domains: const [],
          memory: _NoMemory(),
          deviceId: () async => 'pc',
        ),
        serverNow: () => now,
        isBusy: () => false,
      );
    });

    SyncDoc cmd(Map<String, Object?> v, {int at = 999000}) => SyncDoc(
      key: 'cmd',
      value: jsonEncode(v),
      updatedAt: at,
      deviceId: 'phone',
    );

    test('obeys a command addressed to this device, once', () {
      final c = cmd({'id': 'x1', 'to': 'pc', 'action': 'pause'});
      control.onDoc(c, 'pc');
      control.onDoc(c, 'pc');
      expect(local.calls, ['pause']);
    });

    test('runs seek, skip and jump commands', () {
      control.onDoc(
        cmd({'id': '1', 'to': 'pc', 'action': 'seek', 'positionMs': 61000}),
        'pc',
      );
      control.onDoc(cmd({'id': '2', 'to': 'pc', 'action': 'next'}), 'pc');
      control.onDoc(
        cmd({'id': '3', 'to': 'pc', 'action': 'playAt', 'index': 4}),
        'pc',
      );
      expect(local.calls, ['seek61', 'next', 'playAt4']);
    });

    test('ignores commands for another device and stale ones', () {
      control.onDoc(cmd({'id': 'a', 'to': 'tablet', 'action': 'pause'}), 'pc');
      control.onDoc(
        cmd({'id': 'b', 'to': 'pc', 'action': 'pause'}, at: now - 60000),
        'pc',
      );
      expect(local.calls, isEmpty);
    });

    test(
      'stops when another device starts playing after it did, not before',
      () {
        control.start();
        local.set(() => local.isPlaying = true); // began at `now`
        SyncDoc other(int since) => SyncDoc(
          key: 'now',
          value: jsonEncode({'sha': 'a' * 64, 'playing': true, 'since': since}),
          updatedAt: now,
          deviceId: 'phone',
        );
        control.onDoc(
          other(now - 5000),
          'pc',
        ); // they started earlier: carry on
        expect(local.playing, isTrue);
        control.onDoc(
          other(now + 3000),
          'pc',
        ); // they started later: step aside
        expect(local.playing, isFalse);
        control.dispose();
      },
    );
  });
}

class _NoMemory extends SyncMemory {
  @override
  Future<Map<String, String>> marks() async => {};
  @override
  Future<void> writeMarks(Map<String, String?> changes) async {}
  @override
  Future<int> cursor() async => 0;
  @override
  Future<void> writeCursor(int seq) async {}
}
