import 'package:drift/drift.dart';

import 'dart:math';

import 'package:flutter/widgets.dart';

import 'database.dart';

/// A playlist and how big it is, without loading what is in it.
///
/// The list-of-playlists screen needs a count and nothing else; reading every
/// track of every playlist to draw "12 tracks" would be the whole library on
/// a screen that shows none of it.
class PlaylistSummary {
  const PlaylistSummary({
    required this.id,
    required this.name,
    required this.trackCount,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final int trackCount;
  final DateTime updatedAt;
}

/// Lists people made themselves.
///
/// Everything else the app knows is derived -- what was played, what was
/// liked, what is missing. This is the one thing that is purely a decision,
/// so it is stored exactly as given: in the order it was put in, duplicates
/// and all.
/// A playlist as it travels between devices.
class SyncedPlaylist {
  const SyncedPlaylist({
    required this.syncId,
    required this.name,
    required this.shas,
    required this.createdAt,
    required this.updatedAt,
  });

  final String syncId;
  final String name;
  final List<String> shas;
  final int createdAt;
  final int updatedAt;
}

class PlaylistStore extends ChangeNotifier {
  PlaylistStore(this._db);

  final TunesDatabase _db;

  static int get _now => DateTime.now().millisecondsSinceEpoch;

  /// Playlists with their sizes, most recently changed first.
  ///
  /// By change rather than by creation: the one being worked on is the one
  /// being looked for.
  Future<List<PlaylistSummary>> summaries() async {
    final lists = await (_db.select(
      _db.playlists,
    )..orderBy([(p) => OrderingTerm.desc(p.updatedAt)])).get();
    if (lists.isEmpty) return const [];
    final count = _db.playlistItems.id.count();
    final rows =
        await (_db.selectOnly(_db.playlistItems)
              ..addColumns([_db.playlistItems.playlistId, count])
              ..groupBy([_db.playlistItems.playlistId]))
            .get();
    final sizes = {
      for (final r in rows)
        r.read(_db.playlistItems.playlistId)!: r.read(count) ?? 0,
    };
    return [
      for (final p in lists)
        PlaylistSummary(
          id: p.id,
          name: p.name,
          trackCount: sizes[p.id] ?? 0,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(p.updatedAt),
        ),
    ];
  }

  /// The shas in one playlist, in order.
  ///
  /// Returned as shas rather than resolved tracks: what a playlist holds is a
  /// record of a decision, and whether the library currently has the file is
  /// a separate question the caller answers against its own manifest.
  Future<List<String>> itemsOf(int playlistId) async {
    final rows =
        await (_db.select(_db.playlistItems)
              ..where((i) => i.playlistId.equals(playlistId))
              ..orderBy([(i) => OrderingTerm.asc(i.position)]))
            .get();
    return [for (final r in rows) r.sha];
  }

  Future<int> create(String name) async {
    final id = await _db
        .into(_db.playlists)
        .insert(
          PlaylistsCompanion.insert(
            name: _clean(name),
            createdAt: _now,
            updatedAt: _now,
          ),
        );
    notifyListeners();
    return id;
  }

  Future<void> rename(int id, String name) async {
    await (_db.update(_db.playlists)..where((p) => p.id.equals(id))).write(
      PlaylistsCompanion(name: Value(_clean(name)), updatedAt: Value(_now)),
    );
    notifyListeners();
  }

  /// Removes the playlist and everything in it.
  ///
  /// In one transaction: a playlist whose rows outlived it would be invisible
  /// storage that grows every time someone changes their mind.
  Future<void> delete(int id) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.playlistItems,
      )..where((i) => i.playlistId.equals(id))).go();
      await (_db.delete(_db.playlists)..where((p) => p.id.equals(id))).go();
    });
    notifyListeners();
  }

  /// Appends, and says how many were added.
  ///
  /// Adding an album someone already has part of adds all of it. Silently
  /// skipping the overlap would leave a playlist that does not match what
  /// was asked for, and no way to tell.
  Future<int> addAll(int playlistId, List<String> shas) async {
    if (shas.isEmpty) return 0;
    await _db.transaction(() async {
      final last =
          await (_db.select(_db.playlistItems)
                ..where((i) => i.playlistId.equals(playlistId))
                ..orderBy([(i) => OrderingTerm.desc(i.position)])
                ..limit(1))
              .getSingleOrNull();
      var position = (last?.position ?? -1) + 1;
      for (final sha in shas) {
        await _db
            .into(_db.playlistItems)
            .insert(
              PlaylistItemsCompanion.insert(
                playlistId: playlistId,
                sha: sha,
                position: position,
                addedAt: _now,
              ),
            );
        position += 1;
      }
      await _touch(playlistId);
    });
    notifyListeners();
    return shas.length;
  }

  Future<void> add(int playlistId, String sha) => addAll(playlistId, [sha]);

  /// Removes the entry at [index], not every copy of that track.
  ///
  /// Indexed rather than keyed on the sha, because the same track may appear
  /// more than once and removing all of them is not what was asked.
  /// Puts [sha] at [index], pushing what was there down. For undoing a removal:
  /// the entry goes back where it was rather than to the end of the list.
  Future<void> insertAt(int playlistId, String sha, int index) async {
    await _db.transaction(() async {
      final rows =
          await (_db.select(_db.playlistItems)
                ..where((i) => i.playlistId.equals(playlistId))
                ..orderBy([(i) => OrderingTerm.asc(i.position)]))
              .get();
      final at = index.clamp(0, rows.length);
      // Everything from the slot onward moves down one, from the back so no two
      // rows ever share a position part-way through.
      for (var i = rows.length - 1; i >= at; i--) {
        await (_db.update(_db.playlistItems)
              ..where((it) => it.id.equals(rows[i].id)))
            .write(PlaylistItemsCompanion(position: Value(i + 1)));
      }
      await _db
          .into(_db.playlistItems)
          .insert(
            PlaylistItemsCompanion.insert(
              playlistId: playlistId,
              sha: sha,
              position: at,
              addedAt: _now,
            ),
          );
      await _touch(playlistId);
    });
    notifyListeners();
  }

  Future<void> removeAt(int playlistId, int index) async {
    await _db.transaction(() async {
      final rows =
          await (_db.select(_db.playlistItems)
                ..where((i) => i.playlistId.equals(playlistId))
                ..orderBy([(i) => OrderingTerm.asc(i.position)]))
              .get();
      if (index < 0 || index >= rows.length) return;
      await (_db.delete(
        _db.playlistItems,
      )..where((i) => i.id.equals(rows[index].id))).go();
      await _renumber(playlistId);
      await _touch(playlistId);
    });
    notifyListeners();
  }

  /// Moves the entry at [from] to [to], as a drag would.
  Future<void> move(int playlistId, int from, int to) async {
    await _db.transaction(() async {
      final rows =
          await (_db.select(_db.playlistItems)
                ..where((i) => i.playlistId.equals(playlistId))
                ..orderBy([(i) => OrderingTerm.asc(i.position)]))
              .get();
      if (from < 0 || from >= rows.length) return;
      final target = to.clamp(0, rows.length - 1);
      final ordered = [...rows];
      ordered.insert(target, ordered.removeAt(from));
      for (var i = 0; i < ordered.length; i++) {
        await (_db.update(_db.playlistItems)
              ..where((it) => it.id.equals(ordered[i].id)))
            .write(PlaylistItemsCompanion(position: Value(i)));
      }
      await _touch(playlistId);
    });
    notifyListeners();
  }

  Future<void> _renumber(int playlistId) async {
    final rows =
        await (_db.select(_db.playlistItems)
              ..where((i) => i.playlistId.equals(playlistId))
              ..orderBy([(i) => OrderingTerm.asc(i.position)]))
            .get();
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].position == i) continue;
      await (_db.update(_db.playlistItems)
            ..where((it) => it.id.equals(rows[i].id)))
          .write(PlaylistItemsCompanion(position: Value(i)));
    }
  }

  // --- account sync ----------------------------------------------------------

  /// Every playlist as account sync needs it. A playlist that has no identity
  /// across devices yet is given one here, which is what makes it findable
  /// from another device.
  Future<List<SyncedPlaylist>> forSync() async {
    final lists = await _db.select(_db.playlists).get();
    final out = <SyncedPlaylist>[];
    for (final p in lists) {
      var id = p.syncId;
      if (id == null) {
        id = _newSyncId();
        await (_db.update(_db.playlists)..where((r) => r.id.equals(p.id)))
            .write(PlaylistsCompanion(syncId: Value(id)));
      }
      out.add(
        SyncedPlaylist(
          syncId: id,
          name: p.name,
          shas: await itemsOf(p.id),
          createdAt: p.createdAt,
          updatedAt: p.updatedAt,
        ),
      );
    }
    return out;
  }

  /// Takes another device's version of a playlist: creates it, or replaces
  /// the name and contents of the one with this [SyncedPlaylist.syncId].
  Future<void> applyRemote(SyncedPlaylist remote) async {
    await _db.transaction(() async {
      final existing = await (_db.select(
        _db.playlists,
      )..where((p) => p.syncId.equals(remote.syncId))).getSingleOrNull();
      late final int id;
      if (existing == null) {
        id = await _db
            .into(_db.playlists)
            .insert(
              PlaylistsCompanion.insert(
                name: _clean(remote.name),
                createdAt: remote.createdAt,
                updatedAt: remote.updatedAt,
                syncId: Value(remote.syncId),
              ),
            );
      } else {
        id = existing.id;
        await (_db.update(_db.playlists)..where((p) => p.id.equals(id))).write(
          PlaylistsCompanion(
            name: Value(_clean(remote.name)),
            updatedAt: Value(remote.updatedAt),
          ),
        );
        await (_db.delete(
          _db.playlistItems,
        )..where((i) => i.playlistId.equals(id))).go();
      }
      for (var i = 0; i < remote.shas.length; i++) {
        await _db
            .into(_db.playlistItems)
            .insert(
              PlaylistItemsCompanion.insert(
                playlistId: id,
                sha: remote.shas[i],
                position: i,
                addedAt: remote.updatedAt,
              ),
            );
      }
    });
    notifyListeners();
  }

  /// Another device deleted this playlist.
  Future<bool> deleteRemote(String syncId) async {
    final existing = await (_db.select(
      _db.playlists,
    )..where((p) => p.syncId.equals(syncId))).getSingleOrNull();
    if (existing == null) return false;
    await delete(existing.id);
    return true;
  }

  static String _newSyncId() {
    final r = Random.secure();
    String hex(int n) =>
        List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
    final variant = (8 + r.nextInt(4)).toRadixString(16);
    return '${hex(8)}-${hex(4)}-4${hex(3)}-$variant${hex(3)}-${hex(12)}';
  }

  Future<void> _touch(int playlistId) async {
    await (_db.update(_db.playlists)..where((p) => p.id.equals(playlistId)))
        .write(PlaylistsCompanion(updatedAt: Value(_now)));
  }

  /// Trimmed, and never empty: a playlist with a blank name is one nobody can
  /// point at afterwards.
  static String _clean(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? 'Untitled playlist' : trimmed;
  }
}

/// Reachable from anywhere, published above the Navigator with the others so
/// a pushed album page can add to a playlist.
class PlaylistScope extends InheritedNotifier<PlaylistStore> {
  const PlaylistScope({
    super.key,
    required PlaylistStore playlists,
    required super.child,
  }) : super(notifier: playlists);

  static PlaylistStore? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<PlaylistScope>()
        ?.notifier;
  }
}
