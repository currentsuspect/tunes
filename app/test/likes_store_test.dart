import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/data/database.dart';
import 'package:tunes/core/data/likes_store.dart';

void main() {
  late TunesDatabase db;
  late LikesStore likes;

  setUp(() async {
    db = TunesDatabase.forTesting(NativeDatabase.memory());
    likes = LikesStore(db);
    await likes.load();
  });

  tearDown(() async {
    likes.dispose();
    await db.close();
  });

  test('a fresh install has liked nothing', () {
    expect(likes.count, 0);
    expect(likes.isLiked('a'), isFalse);
    expect(likes.shas, isEmpty);
  });

  test('liking is remembered, and unliking forgets it', () async {
    expect(await likes.toggle('a'), isTrue);
    expect(likes.isLiked('a'), isTrue);

    expect(await likes.toggle('a'), isFalse);
    expect(likes.isLiked('a'), isFalse);
    expect(likes.count, 0);
  });

  test('a like survives a reload', () async {
    // The point of the table. In-memory state that is never read back would
    // pass every test above and lose the like on the next launch.
    await likes.toggle('a');
    final reopened = LikesStore(db);
    await reopened.load();

    expect(reopened.isLiked('a'), isTrue);
    reopened.dispose();
  });

  test('liked songs come back newest first', () async {
    await likes.toggle('first');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await likes.toggle('second');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await likes.toggle('third');

    expect(likes.shas, ['third', 'second', 'first']);
  });

  test('liking twice is the same as liking once', () async {
    // The sha is the primary key, so a double tap cannot produce two rows.
    await likes.toggle('a');
    await likes.toggle('a');
    await likes.toggle('a');

    expect(likes.count, 1);
    expect(await db.select(db.likedTracks).get(), hasLength(1));
  });

  test('the heart fills before the write lands', () async {
    // Not awaited: the control has to answer the finger immediately, so the
    // in-memory state leads and the row follows.
    final pending = likes.toggle('a');
    expect(likes.isLiked('a'), isTrue);
    await pending;
  });

  test('listeners are notified so every heart agrees', () async {
    var notified = 0;
    likes.addListener(() => notified += 1);
    await likes.toggle('a');
    await likes.toggle('a');

    expect(notified, 2);
  });
}
