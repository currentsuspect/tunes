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

/// Tracks the listener said yes to.
///
/// The first signal in the app that comes from a decision rather than from
/// behaviour. Play history says what happened; this says what was meant, and
/// the two disagree often enough that neither can stand in for the other --
/// a track played forty times because it opens an album is not a favourite,
/// and a favourite played twice is still a favourite.
class LikedTracks extends Table {
  TextColumn get sha => text()();

  /// Epoch milliseconds, so the list can be newest first. Liking is the kind
  /// of thing people do in bursts, and the order they did it in is the only
  /// order that means anything without a manual sort.
  IntColumn get likedAt => integer()();

  /// The sha, so liking twice is the same as liking once.
  @override
  Set<Column> get primaryKey => {sha};
}

/// A list someone made, as opposed to one the app worked out.
///
/// Everything else here is derived -- what was played, what was liked, what
/// is missing. This is the one table whose contents are entirely a decision,
/// which is why it keeps its own order rather than sorting itself.
class Playlists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get createdAt => integer()();

  /// Touched on every change to its contents, so a list of playlists can be
  /// ordered by what is being worked on rather than by what is oldest.
  IntColumn get updatedAt => integer()();
}

/// One track's place in one playlist.
///
/// Keyed on its own id, not on (playlist, track): **the same track twice in
/// one playlist is allowed**. A sequence someone assembled is theirs, and a
/// player that refuses to repeat a track is overruling a choice rather than
/// preventing a mistake.
class PlaylistItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get playlistId => integer()();
  TextColumn get sha => text()();

  /// Dense and renumbered on reorder. Gap-based ordering buys nothing at the
  /// sizes a person actually curates by hand.
  IntColumn get position => integer()();
  IntColumn get addedAt => integer()();
}

/// One row per listen, kept as events rather than counters.
///
/// A counter can answer "how many times", and nothing else. The discovery
/// work needs to ask questions that have not been decided yet -- what was
/// abandoned, what was played to the end, what was on heavy rotation last
/// month and is not now -- and every one of those is unanswerable once the
/// events have been folded into a total.
class PlayEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sha => text()();

  /// Epoch milliseconds, so recency is a comparison rather than a parse.
  IntColumn get startedAt => integer()();

  /// Milliseconds actually heard, accumulated from playback rather than taken
  /// from the end position: seeking to the last second of a track is not the
  /// same as listening to it.
  IntColumn get listenedMs => integer()();

  /// The track's own length at the time, so a ratio can be recomputed later
  /// without joining against a library that may have changed.
  IntColumn get durationMs => integer().withDefault(const Constant(0))();

  /// Whether this counted as a play under the rule in PlayHistory. Stored so
  /// the decision is auditable, and recomputable if the rule changes.
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
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

  /// The artist's crowd tags from the box (genres: "trap", "cloud rap"), as a
  /// JSON array. Kept so mixes can tell what a library is made of; an artist the
  /// providers had nothing on has an empty list, which is the truth.
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();

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
    PlayEvents,
    LikedTracks,
    Playlists,
    PlaylistItems,
  ],
)
class TunesDatabase extends _$TunesDatabase {
  TunesDatabase() : super(_openDefault());

  TunesDatabase.forTesting(super.executor);

  TunesDatabase.withFile(File file)
    : super(NativeDatabase.createInBackground(file));

  @override
  int get schemaVersion => 10;

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
      if (from < 7) {
        // v6 -> v7: play history. New table only. An install upgrading here
        // starts with no history, which is the truth -- nothing was recorded
        // before, and inventing plays from the library would poison every
        // taste signal built on top of it.
        await m.createTable(playEvents);
      }
      if (from < 8) {
        // v7 -> v8: liked tracks. New table only. An upgrading install starts
        // with nothing liked, which is the truth: inferring likes from play
        // counts would put words in the listener's mouth, and the whole point
        // of this table is that it holds what was actually decided.
        await m.createTable(likedTracks);
      }
      if (from < 9) {
        // v8 -> v9: playlists. New tables only. Nothing existing is read or
        // rewritten, so an upgrade cannot damage a library that has been
        // playing fine for months.
        await m.createTable(playlists);
        await m.createTable(playlistItems);
      }
      if (from < 10) {
        // v9 -> v10: artist tags. One new column with a default, so existing
        // rows read as "no tags" until the next sync fills them in.
        await m.addColumn(artists, artists.tagsJson);
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
