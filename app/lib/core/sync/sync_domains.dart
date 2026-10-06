import 'dart:convert';

import 'package:drift/drift.dart'
    show InsertMode, StringExpressionOperators, Value;

import '../data/database.dart';
import '../data/likes_store.dart';
import '../data/manifest_store.dart';
import '../data/play_history.dart';
import '../data/playlist_store.dart';
import '../data/settings_store.dart';
import 'sync_engine.dart';

/// Hearts. One document per liked track; unliking is the document going away.
class LikesDomain extends SyncDomain {
  LikesDomain(this.likes);
  final LikesStore likes;

  static const _prefix = 'like:';

  @override
  bool owns(String key) => key.startsWith(_prefix);

  @override
  Future<Map<String, LocalDoc>> snapshot() async => {
    for (final e in likes.likedAtBySha.entries)
      '$_prefix${e.key}': LocalDoc('1', e.value),
  };

  @override
  Future<bool> apply(String key, String? value, int updatedAt) =>
      likes.applyRemote(
        key.substring(_prefix.length),
        value == null ? null : updatedAt,
      );
}

/// Playlists, one document each, matched across devices by their sync id.
///
/// A whole playlist is one document, so two devices changing the same
/// playlist at once keep whichever change was later -- the other is lost. That
/// is the trade for not having a merge algorithm, and it is the right size
/// for one person's lists.
class PlaylistsDomain extends SyncDomain {
  PlaylistsDomain(this.playlists);
  final PlaylistStore playlists;

  static const _prefix = 'playlist:';

  @override
  bool owns(String key) => key.startsWith(_prefix);

  @override
  Future<Map<String, LocalDoc>> snapshot() async => {
    for (final p in await playlists.forSync())
      '$_prefix${p.syncId}': LocalDoc(
        jsonEncode({'name': p.name, 'createdAt': p.createdAt, 'shas': p.shas}),
        p.updatedAt,
      ),
  };

  @override
  Future<bool> apply(String key, String? value, int updatedAt) async {
    final id = key.substring(_prefix.length);
    if (value == null) return playlists.deleteRemote(id);
    final json = jsonDecode(value);
    if (json is! Map) return false;
    await playlists.applyRemote(
      SyncedPlaylist(
        syncId: id,
        name: (json['name'] as String?) ?? 'Untitled playlist',
        shas: [
          for (final s in (json['shas'] as List?) ?? const []) s as String,
        ],
        createdAt: (json['createdAt'] as num?)?.toInt() ?? updatedAt,
        updatedAt: updatedAt,
      ),
    );
    return true;
  }
}

/// A title, artist, album or year the listener corrected.
class EditsDomain extends SyncDomain {
  EditsDomain(this.store);
  final ManifestStore store;

  static const _prefix = 'edit:';

  @override
  bool owns(String key) => key.startsWith(_prefix);

  @override
  Future<Map<String, LocalDoc>> snapshot() async => {
    for (final e in await store.syncableEdits())
      '$_prefix${e.sha}:${e.field}': LocalDoc(e.value, e.editedAt),
  };

  @override
  Future<bool> apply(String key, String? value, int updatedAt) async {
    final rest = key.substring(_prefix.length);
    final colon = rest.indexOf(':');
    if (colon < 0) return false;
    await store.setEdit(
      rest.substring(0, colon),
      rest.substring(colon + 1),
      value,
      editedAt: updatedAt,
    );
    return true;
  }
}

/// The name shown in the greeting.
class ProfileDomain extends SyncDomain {
  ProfileDomain(this.settings);
  final SettingsStore settings;

  @override
  bool owns(String key) => key == 'profile';

  @override
  Future<Map<String, LocalDoc>> snapshot() async {
    final name = settings.displayName;
    if (name.isEmpty) return const {};
    return {
      'profile': LocalDoc(jsonEncode({'name': name})),
    };
  }

  @override
  Future<bool> apply(String key, String? value, int updatedAt) async {
    if (value == null) return false;
    final json = jsonDecode(value);
    final name = json is Map ? json['name'] : null;
    if (name is! String || name.trim().isEmpty) return false;
    if (name == settings.displayName) return false;
    await settings.setDisplayName(name);
    return true;
  }
}

/// What sync remembers, kept in the table the manifest sync already uses for
/// its own bookkeeping.
class DbSyncMemory extends SyncMemory {
  DbSyncMemory(this._db);
  final TunesDatabase _db;

  static const _mark = 'acct.mark:';
  static const _cursor = 'acct.cursor';

  @override
  Future<Map<String, String>> marks() async {
    final rows = await (_db.select(
      _db.syncState,
    )..where((t) => t.key.like('$_mark%'))).get();
    return {for (final r in rows) r.key.substring(_mark.length): r.value};
  }

  @override
  Future<void> writeMarks(Map<String, String?> changes) async {
    await _db.batch((b) {
      for (final e in changes.entries) {
        if (e.value == null) {
          b.deleteWhere(_db.syncState, (t) => t.key.equals('$_mark${e.key}'));
        } else {
          b.insert(
            _db.syncState,
            SyncStateCompanion(
              key: Value('$_mark${e.key}'),
              value: Value(e.value!),
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      }
    });
  }

  @override
  Future<int> cursor() async {
    final row = await (_db.select(
      _db.syncState,
    )..where((t) => t.key.equals(_cursor))).getSingleOrNull();
    return int.tryParse(row?.value ?? '') ?? 0;
  }

  @override
  Future<void> writeCursor(int seq) => _db
      .into(_db.syncState)
      .insertOnConflictUpdate(
        SyncStateCompanion(key: const Value(_cursor), value: Value('$seq')),
      );
}

/// Listening, shared so every device knows what you play.
///
/// One document per device per day, written only by the device that did the
/// listening, so two devices never write the same key and nothing needs
/// merging. Each device keeps the others' listens in its own history marked
/// with where they came from, and never sends those on.
///
/// Switchable: with it off a device neither sends nor takes listening, and
/// what it took is dropped, so its recommendations are its own.
class HistoryDomain extends SyncDomain {
  HistoryDomain(this.history, this.settings, this.deviceId);
  final PlayHistory history;
  final SettingsStore settings;
  final Future<String?> Function() deviceId;

  static const _prefix = 'plays:';

  @override
  bool get active => settings.syncHistory;

  @override
  bool owns(String key) => key.startsWith(_prefix);

  @override
  Future<Map<String, LocalDoc>> snapshot() async {
    final me = await deviceId();
    if (me == null) return const {};
    final days = await history.localEventsByDay();
    return {
      for (final e in days.entries)
        '$_prefix$me:${e.key}': LocalDoc(jsonEncode(e.value)),
    };
  }

  @override
  Future<bool> apply(String key, String? value, int updatedAt) async {
    final rest = key.substring(_prefix.length);
    final colon = rest.lastIndexOf(':');
    if (colon < 0) return false;
    final device = rest.substring(0, colon);
    final day = rest.substring(colon + 1);
    if (day.length != 8) return false;
    List<List<Object?>>? events;
    if (value != null) {
      final json = jsonDecode(value);
      if (json is! List) return false;
      events = [for (final e in json) (e as List).cast<Object?>()];
    }
    await history.replaceFromDevice(device, day, events);
    return true;
  }
}
