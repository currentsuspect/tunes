import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/manifest.dart';
import 'database.dart';

class ManifestStore {
  ManifestStore(this._db);

  final TunesDatabase _db;

  Future<ManifestApplyResult> apply(TunesManifest manifest) async {
    return _db.transaction(() async {
      final existingShas = <String, int?>{};
      final rows = await _db.select(_db.tracks).get();
      for (final r in rows) {
        existingShas[r.sha] = r.addedAt;
      }

      var inserted = 0;
      var updated = 0;
      final incomingShas = <String>{};
      for (final t in manifest.tracks) {
        incomingShas.add(t.sha);
        final priorAdded = existingShas[t.sha];
        final effectiveAddedAt =
            priorAdded ?? t.addedAt?.millisecondsSinceEpoch;
        final searchText = _buildTrackSearchText(t);
        await _db
            .into(_db.tracks)
            .insertOnConflictUpdate(
              TracksCompanion.insert(
                sha: t.sha,
                size: Value(t.size),
                codec: Value(t.codec),
                sampleRate: Value(t.sampleRate),
                channels: Value(t.channels),
                bitrate: Value(t.bitrate),
                durationMs: Value(t.durationMs),
                title: Value(t.title),
                artist: Value(t.artist),
                album: Value(t.album),
                year: Value(t.year),
                artSha: Value(t.artSha),
                releaseId: Value(t.releaseId),
                releaseIdsJson: Value(jsonEncode(t.releaseIds)),
                trackNumber: Value(t.trackNumber),
                discNumber: Value(t.discNumber),
                totalTracks: Value(t.totalTracks),
                addedAt: Value(effectiveAddedAt),
                searchText: Value(searchText),
                // v3: embedded tags from the daemon. Stored raw; the
                // local-wins policy lives in the query layer.
                embeddedTitle: Value(t.embeddedTitle),
                embeddedArtist: Value(t.embeddedArtist),
                embeddedAlbum: Value(t.embeddedAlbum),
                embeddedYear: Value(t.embeddedYear),
              ),
            );
        if (priorAdded == null && effectiveAddedAt != null) {
          inserted++;
        } else if (priorAdded != null) {
          updated++;
        }
      }

      final presentShas = <String>{for (final r in rows) r.sha};
      final toRemove = presentShas.difference(incomingShas);
      final removed = toRemove.length;
      if (toRemove.isNotEmpty) {
        await (_db.delete(
          _db.tracks,
        )..where((t) => t.sha.isIn(toRemove.toList()))).go();
      }

      final incomingReleaseIds = <String>{
        for (final r in manifest.releases) r.id,
      };
      final releaseRows = await _db.select(_db.releases).get();
      final releasesToRemove = releaseRows
          .map((r) => r.id)
          .where((id) => !incomingReleaseIds.contains(id))
          .toList();
      if (releasesToRemove.isNotEmpty) {
        await (_db.delete(
          _db.releases,
        )..where((r) => r.id.isIn(releasesToRemove))).go();
      }

      final incomingArtistNames = <String>{
        for (final a in manifest.artists) a.name,
      };
      final artistRows = await _db.select(_db.artists).get();
      final artistsToRemove = artistRows
          .map((a) => a.name)
          .where((name) => !incomingArtistNames.contains(name))
          .toList();
      if (artistsToRemove.isNotEmpty) {
        await (_db.delete(
          _db.artists,
        )..where((a) => a.name.isIn(artistsToRemove))).go();
      }

      for (final r in manifest.releases) {
        final searchText = _buildReleaseSearchText(r);
        await _db
            .into(_db.releases)
            .insertOnConflictUpdate(
              ReleasesCompanion.insert(
                id: r.id,
                title: r.title,
                artist: r.artist,
                year: Value(r.year),
                artSha: Value(r.artSha),
                totalTracks: Value(r.totalTracks),
                type: Value(r.type),
                trackShasJson: Value(jsonEncode(r.trackShas)),
                releaseTracksJson: Value(
                  jsonEncode(
                    r.tracks
                        .map(
                          (t) => {
                            'sha': t.sha,
                            'trackNumber': t.trackNumber,
                            'discNumber': t.discNumber,
                          },
                        )
                        .toList(),
                  ),
                ),
                searchText: Value(searchText),
              ),
            );
      }

      for (final a in manifest.artists) {
        await _db
            .into(_db.artists)
            .insertOnConflictUpdate(
              ArtistsCompanion.insert(
                name: a.name,
                artSha: Value(a.artSha),
                searchText: Value(a.name.toLowerCase()),
              ),
            );
      }

      return ManifestApplyResult(
        tracksInserted: inserted,
        tracksUpdated: updated,
        tracksRemoved: removed,
      );
    });
  }

  Future<List<ManifestTrack>> allTracksNewestFirst({int limit = 200000}) async {
    final rows =
        await (_db.select(_db.tracks)
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.addedAt,
                  mode: OrderingMode.desc,
                  nulls: NullsOrder.last,
                ),
                (t) => OrderingTerm.desc(t.sha),
              ])
              ..limit(limit))
            .get();
    return _rowsToResolvedTracks(rows);
  }

  Future<List<ManifestRelease>> allReleases({int limit = 200000}) async {
    final rows =
        await (_db.select(_db.releases)
              ..orderBy([
                (r) => OrderingTerm(expression: r.artist),
                (r) => OrderingTerm(expression: r.title),
              ])
              ..limit(limit))
            .get();
    return rows.map(_releaseFromRow).toList();
  }

  Future<List<ManifestArtist>> allArtists({int limit = 200000}) async {
    final rows =
        await (_db.select(_db.artists)
              ..orderBy([(a) => OrderingTerm(expression: a.name)])
              ..limit(limit))
            .get();
    return rows.map(_artistFromRow).toList();
  }

  Future<List<ManifestTrack>> tracksAddedSince(
    DateTime cutoff, {
    int limit = 50,
  }) async {
    final rows =
        await (_db.select(_db.tracks)
              ..where(
                (t) =>
                    t.addedAt.isNotNull() &
                    t.addedAt.isBiggerOrEqualValue(
                      cutoff.millisecondsSinceEpoch,
                    ),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.addedAt)])
              ..limit(limit))
            .get();
    return _rowsToResolvedTracks(rows);
  }

  Future<List<ManifestTrack>> _rowsToResolvedTracks(List<Track> rows) async {
    if (rows.isEmpty) return [];
    final shas = rows.map((r) => r.sha).toList();
    // Batch-load all edits for these tracks in one round trip.
    final editRows = await (_db.select(
      _db.trackEdits,
    )..where((t) => t.sha.isIn(shas))).get();
    final editsBySha = <String, Map<String, String>>{};
    for (final e in editRows) {
      editsBySha.putIfAbsent(e.sha, () => {})[e.field] = e.value;
    }
    return [
      for (final r in rows)
        _applyEdits(_trackFromRow(r), editsBySha[r.sha] ?? const {}),
    ];
  }

  Future<List<SearchHit>> searchTracks(String query, {int limit = 50}) async {
    final q = _sanitize(query);
    if (q.isEmpty) return const [];
    final rows = await _db
        .customSelect(
          '''
      SELECT t.sha, bm25(tracks_fts) AS rank
      FROM tracks_fts
      JOIN tracks t ON t.sha = tracks_fts.sha
      WHERE tracks_fts MATCH ?
      ORDER BY rank
      LIMIT ?
      ''',
          variables: [Variable.withString(q), Variable.withInt(limit)],
          readsFrom: {_db.tracks},
        )
        .get();
    return [
      for (final row in rows)
        SearchHit(sha: row.read<String>('sha'), rank: row.read<double>('rank')),
    ];
  }

  String _sanitize(String q) {
    final lower = q.toLowerCase().trim();
    return lower
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _buildTrackSearchText(ManifestTrack t) {
    return [t.title, t.artist, t.album].map((s) => s.toLowerCase()).join(' ');
  }

  String _buildReleaseSearchText(ManifestRelease r) {
    return [r.title, r.artist].map((s) => s.toLowerCase()).join(' ');
  }

  ManifestTrack _trackFromRow(Track row) {
    final releaseIds = (jsonDecode(row.releaseIdsJson) as List)
        .cast<String>()
        .toList();
    return ManifestTrack(
      sha: row.sha,
      size: row.size,
      codec: row.codec,
      sampleRate: row.sampleRate,
      channels: row.channels,
      bitrate: row.bitrate,
      durationMs: row.durationMs,
      title: row.title,
      artist: row.artist,
      album: row.album,
      year: row.year,
      artSha: row.artSha,
      releaseId: row.releaseId,
      releaseIds: releaseIds,
      trackNumber: row.trackNumber,
      discNumber: row.discNumber,
      totalTracks: row.totalTracks,
      addedAt: row.addedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row.addedAt!),
      embeddedTitle: row.embeddedTitle,
      embeddedArtist: row.embeddedArtist,
      embeddedAlbum: row.embeddedAlbum,
      embeddedYear: row.embeddedYear,
      lyrics: row.lyrics,
      lyricsSource: row.lyricsSource,
    );
  }

  ManifestRelease _releaseFromRow(Release row) {
    final shas = (jsonDecode(row.trackShasJson) as List).cast<String>();
    final tracksJson = (jsonDecode(row.releaseTracksJson) as List).cast<Map>();
    return ManifestRelease(
      id: row.id,
      title: row.title,
      artist: row.artist,
      year: row.year,
      artSha: row.artSha,
      type: row.type,
      totalTracks: row.totalTracks,
      trackShas: shas,
      tracks: [
        for (final t in tracksJson)
          ManifestReleaseTrack(
            sha: t['sha'] as String,
            trackNumber: (t['trackNumber'] as num?)?.toInt(),
            discNumber: (t['discNumber'] as num?)?.toInt(),
          ),
      ],
    );
  }

  ManifestArtist _artistFromRow(Artist row) {
    return ManifestArtist(name: row.name, artSha: row.artSha);
  }

  // --- User edits --------------------------------------------------------

  /// Persist a user edit for a single field. Future syncs won't undo
  /// it. Pass null/empty to clear the edit and revert to the daemon-
  /// supplied (or embedded-tag) value.
  Future<void> setEdit(String sha, String field, String? value) async {
    final key = _validateField(field);
    if (value == null || value.isEmpty) {
      await (_db.delete(
        _db.trackEdits,
      )..where((t) => t.sha.equals(sha) & t.field.equals(key))).go();
    } else {
      await _db
          .into(_db.trackEdits)
          .insertOnConflictUpdate(
            TrackEditsCompanion.insert(
              sha: sha,
              field: key,
              value: value,
              editedAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
    }
  }

  /// Reads all edits for a track in one round trip; cheap because the
  /// edit table is keyed on (sha, field). Returns a map keyed by field.
  Future<Map<String, String>> editsFor(String sha) async {
    final rows = await (_db.select(
      _db.trackEdits,
    )..where((t) => t.sha.equals(sha))).get();
    return {for (final r in rows) r.field: r.value};
  }

  /// Applies the local-wins policy: user edit > embedded tag >
  /// daemon-supplied value. Returns a [ManifestTrack] with the resolved
  /// identity fields, ready for UI display.
  Future<ManifestTrack> trackBySha(String sha) async {
    final row = await (_db.select(
      _db.tracks,
    )..where((t) => t.sha.equals(sha))).getSingleOrNull();
    if (row == null) {
      throw StateError('no track with sha $sha');
    }
    final track = _trackFromRow(row);
    final edits = await editsFor(sha);
    return _applyEdits(track, edits);
  }

  static const _editableFields = {'title', 'artist', 'album', 'year', 'lyrics'};

  String _validateField(String field) {
    if (!_editableFields.contains(field)) {
      throw ArgumentError('non-editable field: $field');
    }
    return field;
  }

  ManifestTrack _applyEdits(ManifestTrack t, Map<String, String> edits) {
    return applyEditsStatic(t, edits);
  }

  /// Public for [QueueStore] which also needs to apply the same
  /// local-wins policy when materialising tracks from its table.
  static ManifestTrack applyEditsStatic(
    ManifestTrack t,
    Map<String, String> edits,
  ) {
    if (edits.isEmpty) return t;
    return ManifestTrack(
      sha: t.sha,
      size: t.size,
      codec: t.codec,
      sampleRate: t.sampleRate,
      channels: t.channels,
      bitrate: t.bitrate,
      durationMs: t.durationMs,
      title: edits['title'] ?? t.embeddedTitle ?? t.title,
      artist: edits['artist'] ?? t.embeddedArtist ?? t.artist,
      album: edits['album'] ?? t.embeddedAlbum ?? t.album,
      year: edits['year'] ?? t.embeddedYear ?? t.year,
      artSha: t.artSha,
      releaseId: t.releaseId,
      releaseIds: t.releaseIds,
      trackNumber: t.trackNumber,
      discNumber: t.discNumber,
      totalTracks: t.totalTracks,
      addedAt: t.addedAt,
      embeddedTitle: t.embeddedTitle,
      embeddedArtist: t.embeddedArtist,
      embeddedAlbum: t.embeddedAlbum,
      embeddedYear: t.embeddedYear,
      lyrics: t.lyrics,
      lyricsSource: t.lyricsSource,
    );
  }

  /// Public for [QueueStore]. Converts a drift row to a domain
  /// track without applying edits (caller does the edit batch).
  static ManifestTrack rowToTrackStatic(Track row) {
    final releaseIds = (jsonDecode(row.releaseIdsJson) as List)
        .cast<String>()
        .toList();
    return ManifestTrack(
      sha: row.sha,
      size: row.size,
      codec: row.codec,
      sampleRate: row.sampleRate,
      channels: row.channels,
      bitrate: row.bitrate,
      durationMs: row.durationMs,
      title: row.title,
      artist: row.artist,
      album: row.album,
      year: row.year,
      artSha: row.artSha,
      releaseId: row.releaseId,
      releaseIds: releaseIds,
      trackNumber: row.trackNumber,
      discNumber: row.discNumber,
      totalTracks: row.totalTracks,
      addedAt: row.addedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row.addedAt!),
      embeddedTitle: row.embeddedTitle,
      embeddedArtist: row.embeddedArtist,
      embeddedAlbum: row.embeddedAlbum,
      embeddedYear: row.embeddedYear,
      lyrics: row.lyrics,
      lyricsSource: row.lyricsSource,
    );
  }
}

class ManifestApplyResult {
  const ManifestApplyResult({
    required this.tracksInserted,
    required this.tracksUpdated,
    required this.tracksRemoved,
  });

  final int tracksInserted;
  final int tracksUpdated;
  final int tracksRemoved;
}

class SearchHit {
  const SearchHit({required this.sha, required this.rank});

  final String sha;
  final double rank;
}
