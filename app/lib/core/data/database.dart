import 'dart:io' show File;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// Key/value app settings.
///
/// A table rather than a preferences plugin: the database is already open
/// before the first frame, so settings are available without a second async
/// store to wait on, and they survive with the rest of the local state.
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

class Tracks extends Table {
  TextColumn get sha => text()();
  IntColumn get size => integer().withDefault(const Constant(0))();
  TextColumn get codec => text().nullable()();
  IntColumn get sampleRate => integer().nullable()();
  IntColumn get channels => integer().nullable()();
  IntColumn get bitrate => integer().nullable()();
  IntColumn get durationMs => integer().nullable()();
  TextColumn get title => text().withDefault(const Constant('untitled'))();
  TextColumn get artist =>
      text().withDefault(const Constant('unknown artist'))();
  TextColumn get album => text().withDefault(const Constant('unknown album'))();
  TextColumn get year => text().nullable()();
  TextColumn get artSha => text().nullable()();
  TextColumn get releaseId => text().nullable()();
  TextColumn get releaseIdsJson => text().withDefault(const Constant('[]'))();
  IntColumn get trackNumber => integer().nullable()();
  IntColumn get discNumber => integer().nullable()();
  IntColumn get totalTracks => integer().nullable()();
  IntColumn get addedAt => integer().nullable()();
  TextColumn get searchText => text().withDefault(const Constant(''))();
  // v3: embedded tag values (ffprobe-extracted). The app prefers
  // user edits > embedded > daemon-supplied identity. When the user
  // edits a field, an entry appears in TrackEdits; the query layer
  // COALESCEs the values.
  // The act this track belongs to, separated from its guest credits by the
  // daemon. Grouping by the raw `artist` put one album under nine artists.
  TextColumn get primaryArtist => text().nullable()();
  TextColumn get featuredJson => text().withDefault(const Constant('[]'))();
  TextColumn get embeddedTitle => text().nullable()();
  TextColumn get embeddedArtist => text().nullable()();
  TextColumn get embeddedAlbum => text().nullable()();
  TextColumn get embeddedYear => text().nullable()();
  // v3: lyrics. Source column records provenance so the UI can
  // distinguish user-edited from auto-fetched from file.
  TextColumn get lyrics => text().nullable()();
  TextColumn get lyricsSource => text().nullable()();

  @override
  Set<Column> get primaryKey => {sha};
}

/// Per-track user edits. When the user fixes "unknown artist" or
/// overrides a wrong title, the override is written here and the
/// query layer substitutes it for the value the daemon sent.
/// Future syncs don't undo edits: this is the local-wins policy.
class TrackEdits extends Table {
  TextColumn get sha => text()();
  TextColumn get field => text()();
  TextColumn get value => text()();
  IntColumn get editedAt => integer()();

  @override
  Set<Column> get primaryKey => {sha, field};
}

/// Persistent play queue. The TunePlayer's queue is a *projection*
/// of this table; the queue survives restarts, the in-memory copy
/// does not. Each row has a stable autoincrement `id` so duplicate
/// tracks in the queue (same trackSha, different positions) are
/// individually addressable. Reorder updates `position` on rows by
/// their `id`.
class QueueEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get position => integer()();
  TextColumn get trackSha => text()();
  // 0 = ordinary, 1 = played, 2 = skipped (kept for history).
  // Currently only '0' is used but the column exists for future
  // "skip track but keep in queue" UX.
  IntColumn get state => integer().withDefault(const Constant(0))();
  IntColumn get addedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class Releases extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get artist => text()();
  TextColumn get year => text().nullable()();
  TextColumn get artSha => text().nullable()();
  IntColumn get totalTracks => integer().nullable()();
  TextColumn get trackShasJson => text().withDefault(const Constant('[]'))();
  TextColumn get releaseTracksJson =>
      text().withDefault(const Constant('[]'))();
  TextColumn get type => text().nullable()();
  TextColumn get searchText => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class Artists extends Table {
  TextColumn get name => text()();
  TextColumn get artSha => text().nullable()();
  TextColumn get searchText => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {name};
}

class SyncState extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(
  tables: [
    Tracks,
    Releases,
    Artists,
    SyncState,
    TrackEdits,
    QueueEntries,
    Settings,
  ],
)
class TunesDatabase extends _$TunesDatabase {
  TunesDatabase() : super(_openDefault());

  TunesDatabase.forTesting(super.executor);

  TunesDatabase.withFile(File file)
    : super(NativeDatabase.createInBackground(file));

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createFts();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // v1 -> v2: releaseTracksJson + type on Releases.
        await m.addColumn(releases, releases.releaseTracksJson);
        await m.addColumn(releases, releases.type);
      }
      if (from < 3) {
        // v2 -> v3: embedded tag fields, lyrics, track_edits,
        // queue_entries.
        await m.addColumn(tracks, tracks.embeddedTitle);
        await m.addColumn(tracks, tracks.embeddedArtist);
        await m.addColumn(tracks, tracks.embeddedAlbum);
        await m.addColumn(tracks, tracks.embeddedYear);
        await m.addColumn(tracks, tracks.lyrics);
        await m.addColumn(tracks, tracks.lyricsSource);
        await m.createTable(trackEdits);
        await m.createTable(queueEntries);
      }
      if (from < 4) {
        // v3 -> v4: stable autoincrement `id` for queue entries.
        // The v3 row class doesn't have an `id` column, so reading
        // existing rows into the v4 row class NPEs. Drop the table
        // and recreate; no real user has a persistent multi-entry
        // queue yet, so this is safe.
        await m.deleteTable('queue_entries');
        await m.createTable(queueEntries);
      }
      if (from < 5) {
        // v4 -> v5: primaryArtist + featured credits, so the artist list can
        // group by the act instead of the raw credit string. Additive; existing
        // rows get null / '[]' and are corrected on the next manifest sync.
        await m.addColumn(tracks, tracks.primaryArtist);
        await m.addColumn(tracks, tracks.featuredJson);
      }
      if (from < 6) {
        // v5 -> v6: settings. New table only; nothing existing is touched, and
        // an absent key means "the default", so an upgraded install starts
        // with the same behaviour it had.
        await m.createTable(settings);
      }
    },
  );

  Future<void> _createFts() async {
    await customStatement(
      'CREATE VIRTUAL TABLE IF NOT EXISTS tracks_fts USING fts5('
      'sha UNINDEXED, searchText, '
      "tokenize='unicode61 remove_diacritics 2'"
      ')',
    );
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS tracks_ai AFTER INSERT ON tracks BEGIN
        INSERT INTO tracks_fts(sha, searchText) VALUES (NEW.sha, NEW.search_text);
      END
    ''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS tracks_ad AFTER DELETE ON tracks BEGIN
        DELETE FROM tracks_fts WHERE sha = OLD.sha;
      END
    ''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS tracks_au AFTER UPDATE ON tracks BEGIN
        DELETE FROM tracks_fts WHERE sha = OLD.sha;
        INSERT INTO tracks_fts(sha, searchText) VALUES (NEW.sha, NEW.search_text);
      END
    ''');
    await customStatement('''
      CREATE VIRTUAL TABLE IF NOT EXISTS releases_fts USING fts5(
        id UNINDEXED, searchText,
        tokenize='unicode61 remove_diacritics 2'
      )
    ''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS releases_ai AFTER INSERT ON releases BEGIN
        INSERT INTO releases_fts(id, searchText) VALUES (NEW.id, NEW.search_text);
      END
    ''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS releases_ad AFTER DELETE ON releases BEGIN
        DELETE FROM releases_fts WHERE id = OLD.id;
      END
    ''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS releases_au AFTER UPDATE ON releases BEGIN
        DELETE FROM releases_fts WHERE id = OLD.id;
        INSERT INTO releases_fts(id, searchText) VALUES (NEW.id, NEW.search_text);
      END
    ''');
  }
}

LazyDatabase _openDefault() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    return NativeDatabase.createInBackground(
      File(p.join(dir.path, 'tunes.db')),
    );
  });
}
