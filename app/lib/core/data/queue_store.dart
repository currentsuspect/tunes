import 'package:drift/drift.dart';

import '../../domain/manifest.dart';
import 'database.dart';
import 'manifest_store.dart' show ManifestStore;

/// A queue entry: a single track in the persistent queue, with a
/// stable row id (used by the UI as a list key and for targeted
/// reorder/remove). The same trackSha can appear multiple times
/// because the row id, not the sha, identifies the position.
class QueueItem {
  const QueueItem({
    required this.id,
    required this.position,
    required this.track,
  });
  final int id;
  final int position;
  final ManifestTrack track;
}

/// Persistent play queue.
///
/// The [TunePlayer]'s queue is a *projection* of this table — when a
/// user plays a track, the queue is materialised into the player. On
/// subsequent plays, the queue rehydrates from here. "Play next" and
/// "Add to queue" write to this table; the player surfaces the
/// projection. Reorder updates `position` across rows in a single
/// transaction.
class QueueStore {
  QueueStore(this._db);

  final TunesDatabase _db;

  /// Load the current queue as a list of [QueueItem] in order.
  /// Missing tracks (e.g. deleted from the library since they were
  /// queued) are silently skipped.
  Future<List<QueueItem>> load() async {
    final rows = await (_db.select(
      _db.queueEntries,
    )..orderBy([(q) => OrderingTerm.asc(q.position)])).get();
    if (rows.isEmpty) return [];
    final shas = rows.map((r) => r.trackSha).toList();
    final trackRows = await (_db.select(
      _db.tracks,
    )..where((t) => t.sha.isIn(shas))).get();
    final trackBySha = {for (final t in trackRows) t.sha: t};
    final result = <QueueItem>[];
    final editsBySha = <String, Map<String, String>>{};
    final editRows = await (_db.select(
      _db.trackEdits,
    )..where((t) => t.sha.isIn(shas))).get();
    for (final e in editRows) {
      editsBySha.putIfAbsent(e.sha, () => {})[e.field] = e.value;
    }
    for (final r in rows) {
      final t = trackBySha[r.trackSha];
      if (t == null) continue;
      result.add(
        QueueItem(
          id: r.id,
          position: r.position,
          track: ManifestStore.applyEditsStatic(
            ManifestStore.rowToTrackStatic(t),
            editsBySha[t.sha] ?? const {},
          ),
        ),
      );
    }
    return result;
  }

  /// Replace the queue with a new ordered list of shas. Used by
  /// "Play" and "Play next" / "Add to queue" actions.
  Future<void> replace(List<String> shas) async {
    await _db.transaction(() async {
      await _db.delete(_db.queueEntries).go();
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < shas.length; i++) {
        await _db
            .into(_db.queueEntries)
            .insert(
              QueueEntriesCompanion.insert(
                position: i,
                trackSha: shas[i],
                addedAt: now,
              ),
            );
      }
    });
  }

  /// Append a track to the end of the queue.
  Future<void> append(String sha) async {
    // Read the max position and insert inside one transaction so two
    // concurrent append calls can't both pick the same position.
    // The insert must be awaited so the transaction knows to commit
    // after it lands.
    await _db.transaction(() async {
      final row = await _db
          .customSelect(
            'SELECT COALESCE(MAX(position), -1) AS m FROM queue_entries',
            readsFrom: {_db.queueEntries},
          )
          .getSingle();
      final maxPos = row.read<int>('m');
      final nextPos = maxPos + 1;
      await _db
          .into(_db.queueEntries)
          .insert(
            QueueEntriesCompanion.insert(
              position: nextPos,
              trackSha: sha,
              addedAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
    });
  }

  /// Insert a track at a specific position, shifting later entries down.
  Future<void> insertAt(int position, String sha) async {
    await _db.transaction(() async {
      // Bump every entry at or after `position` by one.
      await _db.customStatement(
        'UPDATE queue_entries SET position = position + 1 WHERE position >= ?',
        [position],
      );
      await _db
          .into(_db.queueEntries)
          .insert(
            QueueEntriesCompanion.insert(
              position: position,
              trackSha: sha,
              addedAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
    });
  }

  /// Reorder by writing positions in one transaction. The list is
  /// the new ordered entry ids; positions are recomputed from index.
  /// Takes ids (not shas) so duplicate entries of the same track are
  /// reordered correctly.
  Future<void> reorder(List<int> ids) async {
    await _db.transaction(() async {
      for (var i = 0; i < ids.length; i++) {
        await (_db.update(_db.queueEntries)..where((q) => q.id.equals(ids[i])))
            .write(QueueEntriesCompanion(position: Value(i)));
      }
    });
  }

  /// Remove a single queue entry by its stable id, shifting later
  /// entries up.
  Future<void> removeById(int id) async {
    await _db.transaction(() async {
      final target = await (_db.select(
        _db.queueEntries,
      )..where((q) => q.id.equals(id))).getSingleOrNull();
      if (target == null) return;
      await (_db.delete(_db.queueEntries)..where((q) => q.id.equals(id))).go();
      // Close the gap.
      await _db.customStatement(
        'UPDATE queue_entries SET position = position - 1 WHERE position > ?',
        [target.position],
      );
    });
  }

  /// Clear the entire queue.
  Future<void> clear() async {
    await _db.delete(_db.queueEntries).go();
  }

  /// Reactive watch: a Stream that emits the current queue every time
  /// it changes. Used by UI to reflect drag-reorder / remove actions.
  Stream<List<QueueItem>> watch() {
    return _db.select(_db.queueEntries).watch().asyncMap((_) => load());
  }
}
