import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/data/database.dart';
import 'package:tunes/core/audio/tune_player.dart';
import 'package:tunes/core/data/likes_store.dart';
import 'package:tunes/core/data/play_history.dart';
import 'package:tunes/core/data/manifest_store.dart';
import 'package:tunes/core/data/playlist_store.dart';
import 'package:tunes/core/data/settings_store.dart';
import 'package:tunes/core/sync/sync_domains.dart';
import 'package:tunes/domain/manifest.dart';
import 'package:tunes/core/sync/sync_engine.dart';

import 'support/fake_sync_server.dart';

/// A whole device: its own database and stores, syncing against the shared
/// fake server with the real domains.
class _Device {
  _Device(FakeSyncServer server, this.id) {
    db = TunesDatabase.forTesting(NativeDatabase.memory());
    likes = LikesStore(db);
    playlists = PlaylistStore(db);
    manifest = ManifestStore(db);
    settings = SettingsStore(db);
    history = PlayHistory(db, _NoPlayer());
    engine = SyncEngine(
      transport: server.as(id),
      domains: [
        LikesDomain(likes),
        PlaylistsDomain(playlists),
        EditsDomain(manifest),
        ProfileDomain(settings),
        HistoryDomain(history, settings, () async => id),
      ],
      memory: DbSyncMemory(db),
      deviceId: () async => id,
    );
  }
  final String id;
  late final TunesDatabase db;
  late final LikesStore likes;
  late final PlaylistStore playlists;
  late final ManifestStore manifest;
  late final SettingsStore settings;
  late final PlayHistory history;
  late final SyncEngine engine;
}

class _NoPlayer extends TunePlayer {
  @override
  List<ManifestTrack> get queue => const [];
  @override
  int get index => -1;
  @override
  bool get playing => false;
  @override
  Duration get position => Duration.zero;
  @override
  Duration get duration => Duration.zero;
  @override
  ManifestTrack? get current => null;
  @override
  PlaybackRepeat get repeat => PlaybackRepeat.off;
  @override
  bool get shuffle => false;
  @override
  void playQueue(List<ManifestTrack> l, int i) {}
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
  void playAt(int i) {}
  @override
  void seek(Duration t) {}
  @override
  void stop() {}
  @override
  void setRepeat(PlaybackRepeat m) {}
  @override
  void setShuffle(bool on) {}
}

Future<void> _listen(_Device d, String sha, int at) => d.db
    .into(d.db.playEvents)
    .insert(
      PlayEventsCompanion.insert(
        sha: sha,
        startedAt: at,
        listenedMs: 200000,
        durationMs: const Value(210000),
        completed: const Value(true),
      ),
    );

final _a = 'a' * 64;
final _b = 'b' * 64;

void main() {
  late FakeSyncServer server;
  late _Device phone;
  late _Device laptop;

  setUp(() async {
    server = FakeSyncServer();
    phone = _Device(server, 'phone');
    laptop = _Device(server, 'laptop');
    await phone.likes.load();
    await laptop.likes.load();
    await phone.settings.load();
    await laptop.settings.load();
  });

  tearDown(() async {
    await phone.db.close();
    await laptop.db.close();
  });

  test('likes cross over, and so does an unlike', () async {
    await phone.likes.toggle(_a);
    await phone.engine.run();
    await laptop.engine.run();
    expect(laptop.likes.isLiked(_a), isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    await laptop.likes.toggle(_a);
    await laptop.engine.run();
    await phone.engine.run();
    expect(phone.likes.isLiked(_a), isFalse);
  });

  test('a playlist arrives whole, in order, and is not duplicated by syncing again', () async {
    final id = await phone.playlists.create('Gym');
    await phone.playlists.addAll(id, [_a, _b, _a]);
    await phone.engine.run();
    await laptop.engine.run();
    await laptop.engine.run();
    await phone.engine.run();

    final lists = await laptop.playlists.summaries();
    expect(lists.map((l) => l.name), ['Gym']);
    expect(await laptop.playlists.itemsOf(lists.single.id), [_a, _b, _a]);
    expect((await phone.playlists.summaries()).length, 1);
  });

  test(
    'renaming and then deleting a playlist reaches the other device',
    () async {
      final id = await phone.playlists.create('Old');
      await phone.engine.run();
      await laptop.engine.run();

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await phone.playlists.rename(id, 'New');
      await phone.engine.run();
      await laptop.engine.run();
      expect((await laptop.playlists.summaries()).single.name, 'New');

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await phone.playlists.delete(id);
      await phone.engine.run();
      await laptop.engine.run();
      expect(await laptop.playlists.summaries(), isEmpty);
    },
  );

  test(
    'nothing is sent twice: a second round after settling pushes nothing',
    () async {
      await phone.likes.toggle(_a);
      final id = await phone.playlists.create('Mix');
      await phone.playlists.add(id, _b);
      await phone.engine.run();
      await laptop.engine.run();
      expect((await laptop.engine.run()).pushed, 0);
      expect((await phone.engine.run()).pushed, 0);
    },
  );

  test('the name in the greeting follows the account', () async {
    await phone.settings.setDisplayName('Dylan');
    await phone.engine.run();
    await laptop.engine.run();
    expect(laptop.settings.displayName, 'Dylan');
  });

  group('listening history', () {
    final day = DateTime.utc(2026, 10, 5, 12).millisecondsSinceEpoch;

    test(
      'plays on one device count on the other, and are not sent back',
      () async {
        await _listen(phone, _a, day);
        await _listen(phone, _a, day + 300000);
        await phone.engine.run();
        await laptop.engine.run();
        expect((await laptop.history.playCounts())[_a], 2);
        // the laptop does not return the phone's plays as its own
        expect((await laptop.engine.run()).pushed, 0);
        await phone.engine.run();
        expect((await phone.history.playCounts())[_a], 2);
      },
    );

    test(
      'a new play on the same day replaces that day, not duplicates it',
      () async {
        await _listen(phone, _a, day);
        await phone.engine.run();
        await laptop.engine.run();
        await _listen(phone, _b, day + 600000);
        await phone.engine.run();
        await laptop.engine.run();
        final counts = await laptop.history.playCounts();
        expect(counts[_a], 1);
        expect(counts[_b], 1);
      },
    );

    test(
      'with sharing off a device neither sends nor takes listening',
      () async {
        await laptop.settings.setSyncHistory(false);
        await _listen(phone, _a, day);
        await _listen(laptop, _b, day);
        await phone.engine.run();
        await laptop.engine.run();
        expect(await laptop.history.playCounts(), {_b: 1});
        await phone.engine.run();
        expect((await phone.history.playCounts()).containsKey(_b), isFalse);
      },
    );
  });
}
