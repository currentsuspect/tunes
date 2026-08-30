import 'dart:io' show File;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

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

  @override
  Set<Column> get primaryKey => {sha};
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

@DriftDatabase(tables: [Tracks, Releases, Artists, SyncState])
class TunesDatabase extends _$TunesDatabase {
  TunesDatabase() : super(_openDefault());

  TunesDatabase.forTesting(super.executor);

  TunesDatabase.withFile(File file)
    : super(NativeDatabase.createInBackground(file));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createFts();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(releases, releases.releaseTracksJson);
        await m.addColumn(releases, releases.type);
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
