import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/data/database.dart';
import 'package:tunes/core/data/playlist_store.dart';

void main() {
  late TunesDatabase db;
  late PlaylistStore store;

  setUp(() {
    db = TunesDatabase.forTesting(NativeDatabase.memory());
    store = PlaylistStore(db);
  });

  tearDown(() async {
    store.dispose();
    await db.close();
  });

  test('a new playlist is empty and named', () async {
    final id = await store.create('Late night');
    final all = await store.summaries();

    expect(all, hasLength(1));
    expect(all.single.id, id);
    expect(all.single.name, 'Late night');
    expect(all.single.trackCount, 0);
  });

  test('a blank name becomes a name you can point at', () async {
    await store.create('   ');
    expect((await store.summaries()).single.name, 'Untitled playlist');
  });

  test('tracks keep the order they were added in', () async {
    final id = await store.create('x');
    await store.addAll(id, ['a', 'b', 'c']);

    expect(await store.itemsOf(id), ['a', 'b', 'c']);
  });

  test('the same track twice is allowed', () async {
    // A sequence someone assembled is theirs. Refusing the duplicate would
    // be overruling a choice, not preventing a mistake.
    final id = await store.create('x');
    await store.addAll(id, ['a', 'b', 'a']);

    expect(await store.itemsOf(id), ['a', 'b', 'a']);
    expect((await store.summaries()).single.trackCount, 3);
  });

  test('removing takes the entry, not every copy of the track', () async {
    final id = await store.create('x');
    await store.addAll(id, ['a', 'b', 'a']);

    await store.removeAt(id, 0);

    expect(await store.itemsOf(id), ['b', 'a']);
  });

  test('reordering moves one entry and keeps the rest in sequence', () async {
    final id = await store.create('x');
    await store.addAll(id, ['a', 'b', 'c', 'd']);

    await store.move(id, 3, 0);

    expect(await store.itemsOf(id), ['d', 'a', 'b', 'c']);
  });

  test(
    'positions stay dense after a removal, so later moves are right',
    () async {
      // A gap left behind would make the next reorder land somewhere else.
      final id = await store.create('x');
      await store.addAll(id, ['a', 'b', 'c']);
      await store.removeAt(id, 1);
      await store.move(id, 1, 0);

      expect(await store.itemsOf(id), ['c', 'a']);
    },
  );

  test('insertAt puts a removed entry back exactly where it was', () async {
    final id = await store.create('x');
    await store.addAll(id, ['a', 'b', 'c', 'd']);
    await store.removeAt(id, 1);
    expect(await store.itemsOf(id), ['a', 'c', 'd']);

    await store.insertAt(id, 'b', 1);
    expect(await store.itemsOf(id), ['a', 'b', 'c', 'd']);
  });

  test('insertAt handles the ends and clamps past them', () async {
    final id = await store.create('x');
    await store.addAll(id, ['a', 'b']);
    await store.insertAt(id, 'front', 0);
    await store.insertAt(id, 'back', 99);
    await store.insertAt(id, 'neg', -5);
    expect(await store.itemsOf(id), ['neg', 'front', 'a', 'b', 'back']);
  });

  test('insertAt keeps positions dense so a later move still lands', () async {
    final id = await store.create('x');
    await store.addAll(id, ['a', 'b', 'c']);
    await store.insertAt(id, 'n', 1);
    await store.move(id, 3, 0);
    expect(await store.itemsOf(id), ['c', 'a', 'n', 'b']);
  });

  test('adding appends after what is already there', () async {
    final id = await store.create('x');
    await store.addAll(id, ['a', 'b']);
    await store.add(id, 'c');

    expect(await store.itemsOf(id), ['a', 'b', 'c']);
  });

  test('deleting a playlist takes its tracks with it', () async {
    // Rows outliving their playlist would be invisible storage that grows
    // every time someone changes their mind.
    final id = await store.create('x');
    await store.addAll(id, ['a', 'b']);

    await store.delete(id);

    expect(await store.summaries(), isEmpty);
    expect(await db.select(db.playlistItems).get(), isEmpty);
  });

  test('deleting one playlist leaves the others alone', () async {
    final keep = await store.create('keep');
    final drop = await store.create('drop');
    await store.addAll(keep, ['a']);
    await store.addAll(drop, ['b']);

    await store.delete(drop);

    expect(await store.itemsOf(keep), ['a']);
  });

  test('the most recently changed playlist comes first', () async {
    final first = await store.create('first');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final second = await store.create('second');
    await Future<void>.delayed(const Duration(milliseconds: 5));

    // Touching the older one puts it back on top: the list is ordered by
    // what is being worked on, not by what is newest.
    await store.add(first, 'a');

    expect((await store.summaries()).map((p) => p.id), [first, second]);
  });

  test('renaming keeps the contents', () async {
    final id = await store.create('old');
    await store.addAll(id, ['a', 'b']);

    await store.rename(id, 'new');

    expect((await store.summaries()).single.name, 'new');
    expect(await store.itemsOf(id), ['a', 'b']);
  });
}
