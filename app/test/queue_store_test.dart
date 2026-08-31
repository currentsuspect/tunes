import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/data/database.dart';
import 'package:tunes/core/data/queue_store.dart';

TunesDatabase _db() => TunesDatabase.forTesting(NativeDatabase.memory());

Future<void> _seed(TunesDatabase db) async {
  await db
      .into(db.tracks)
      .insert(
        TracksCompanion.insert(
          sha: 'a' * 64,
          title: Value('T1'),
          artist: Value('A1'),
          album: Value('L1'),
        ),
      );
  await db
      .into(db.tracks)
      .insert(
        TracksCompanion.insert(
          sha: 'b' * 64,
          title: Value('T2'),
          artist: Value('A2'),
          album: Value('L2'),
        ),
      );
}

void main() {
  group('QueueStore', () {
    late TunesDatabase db;
    late QueueStore store;

    setUp(() async {
      db = _db();
      await _seed(db);
      store = QueueStore(db);
      // Insert two copies of the same track + one other.
      await store.replace(['a' * 64, 'a' * 64, 'b' * 64]);
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'load() returns QueueItems with stable ids and the right order',
      () async {
        final items = await store.load();
        expect(items, hasLength(3));
        expect(items[0].track.sha, 'a' * 64);
        expect(items[1].track.sha, 'a' * 64);
        expect(items[2].track.sha, 'b' * 64);
        // All three ids are distinct.
        final ids = items.map((e) => e.id).toSet();
        expect(ids, hasLength(3));
        // Positions are 0, 1, 2 in order.
        expect(items.map((e) => e.position).toList(), [0, 1, 2]);
      },
    );

    test(
      'removeById removes a single duplicate without touching the other',
      () async {
        final items = await store.load();
        final middle = items[1]; // the duplicate at position 1
        await store.removeById(middle.id);
        final after = await store.load();
        expect(after, hasLength(2));
        // The other copy at position 0 is still there.
        expect(after[0].track.sha, 'a' * 64);
        expect(after[0].id, isNot(middle.id));
        // The other track is now at position 0 (gap closed).
        expect(after[0].position, 0);
      },
    );

    test('reorder by ids swaps two duplicates and keeps both', () async {
      final items = await store.load();
      // Swap the two duplicates: index 0 <-> index 1.
      final first = items[0];
      final second = items[1];
      await store.reorder([second.id, first.id, items[2].id]);
      final after = await store.load();
      expect(after, hasLength(3));
      // Their positions swapped.
      expect(after[0].id, second.id);
      expect(after[1].id, first.id);
      // The id values themselves are unchanged.
      expect(after[0].id, isNot(first.id));
      expect(after[1].id, isNot(second.id));
    });

    test(
      'insertAt + removeById preserves stable ids for new entries',
      () async {
        final before = await store.load();
        await store.insertAt(1, 'a' * 64);
        final after = await store.load();
        expect(after, hasLength(4));
        // New entry got a new id.
        final newId = after[1].id;
        expect(before.any((e) => e.id == newId), isFalse);
        // The old entry that used to be at 1 is now at 2.
        expect(after[2].id, before[1].id);
      },
    );
  });
}
