import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/data/database.dart';
import 'package:tunes/core/data/manifest_store.dart';
import 'package:tunes/domain/manifest.dart';

final _dead = 'a' * 64;
final _live = 'c' * 64;

void main() {
  test('dupeShas become pointers from the unlisted copy to the listed one', () {
    final m = TunesManifest.fromJson({
      'tracks': [
        {
          'sha': _live,
          'title': 'Team ceo',
          'dupeShas': [_dead],
        },
      ],
    });
    expect(m.pointers, {_dead: _live});
  });

  test('what was kept under a dead copy follows the song', () async {
    final db = TunesDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final store = ManifestStore(db);
    await db
        .into(db.likedTracks)
        .insert(LikedTracksCompanion.insert(sha: _dead, likedAt: 5));
    await db
        .into(db.playlistItems)
        .insert(
          PlaylistItemsCompanion.insert(
            playlistId: 1,
            sha: _dead,
            position: 0,
            addedAt: 1,
          ),
        );
    await db
        .into(db.queueEntries)
        .insert(
          QueueEntriesCompanion.insert(
            position: 0,
            trackSha: _dead,
            addedAt: 1,
          ),
        );
    await db
        .into(db.playEvents)
        .insert(
          PlayEventsCompanion.insert(sha: _dead, startedAt: 1, listenedMs: 9),
        );

    final moved = await store.repoint({_dead: _live});

    expect(moved, 4);
    final likes = await db.select(db.likedTracks).get();
    expect(likes.map((l) => l.sha), [_live]);
    expect(likes.single.likedAt, 5);
    expect((await db.select(db.playlistItems).getSingle()).sha, _live);
    expect((await db.select(db.queueEntries).getSingle()).trackSha, _live);
    expect((await db.select(db.playEvents).getSingle()).sha, _live);
  });

  test(
    'a like already on the live copy wins; the old one is dropped',
    () async {
      final db = TunesDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final store = ManifestStore(db);
      await db
          .into(db.likedTracks)
          .insert(LikedTracksCompanion.insert(sha: _dead, likedAt: 1));
      await db
          .into(db.likedTracks)
          .insert(LikedTracksCompanion.insert(sha: _live, likedAt: 2));
      await store.repoint({_dead: _live});
      final likes = await db.select(db.likedTracks).get();
      expect(likes.map((l) => l.sha), [_live]);
      expect(likes.single.likedAt, 2);
    },
  );
}
