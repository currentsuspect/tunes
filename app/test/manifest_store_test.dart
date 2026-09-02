import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/data/database.dart';
import 'package:tunes/core/data/manifest_store.dart';
import 'package:tunes/domain/manifest.dart';

TunesDatabase _newDb() => TunesDatabase.forTesting(NativeDatabase.memory());

TunesManifest _manifest({
  required List<ManifestTrack> tracks,
  List<ManifestRelease> releases = const [],
  List<ManifestArtist> artists = const [],
}) {
  return TunesManifest(tracks: tracks, releases: releases, artists: artists);
}

ManifestTrack _track(String sha, {DateTime? addedAt}) => ManifestTrack(
  sha: sha,
  size: 1000,
  codec: 'flac',
  sampleRate: 44100,
  channels: 2,
  bitrate: 950000,
  durationMs: 120000,
  title: 'Track $sha',
  artist: 'Artist A',
  album: 'Album A',
  year: '2024',
  artSha: null,
  releaseId: 'release-1',
  trackNumber: 1,
  discNumber: null,
  addedAt: addedAt,
);

void main() {
  group('ManifestStore.apply', () {
    late TunesDatabase db;
    late ManifestStore store;

    setUp(() {
      db = _newDb();
      store = ManifestStore(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('first sync inserts all tracks with manifest addedAt', () async {
      final added = DateTime.utc(2026, 8, 30, 10, 0, 0);
      final manifest = _manifest(tracks: [_track('a' * 64, addedAt: added)]);
      final result = await store.apply(manifest);
      expect(result.tracksInserted, 1);
      expect(result.tracksUpdated, 0);

      final rows = await db.select(db.tracks).get();
      expect(rows, hasLength(1));
      expect(rows.first.addedAt, added.millisecondsSinceEpoch);
    });

    test('re-sync is idempotent and preserves addedAt', () async {
      final first = DateTime.utc(2026, 8, 30, 10, 0, 0);
      final manifest = _manifest(tracks: [_track('a' * 64, addedAt: first)]);
      await store.apply(manifest);
      // Second sync with the same track but a *newer* addedAt — store must
      // keep the original first-seen timestamp.
      final newer = DateTime.utc(2026, 8, 30, 11, 0, 0);
      final reSync = _manifest(tracks: [_track('a' * 64, addedAt: newer)]);
      final result = await store.apply(reSync);
      expect(result.tracksInserted, 0);
      expect(result.tracksUpdated, 1);

      final rows = await db.select(db.tracks).get();
      expect(rows.first.addedAt, first.millisecondsSinceEpoch);
    });

    test('a new track in a later sync gets its own addedAt', () async {
      final first = DateTime.utc(2026, 8, 30, 10, 0, 0);
      final second = DateTime.utc(2026, 8, 30, 11, 0, 0);
      await store.apply(_manifest(tracks: [_track('a' * 64, addedAt: first)]));
      await store.apply(
        _manifest(
          tracks: [
            _track('a' * 64, addedAt: first),
            _track('b' * 64, addedAt: second),
          ],
        ),
      );

      final all = await db.select(db.tracks).get();
      expect(all, hasLength(2));
      final bySha = {for (final r in all) r.sha: r.addedAt};
      expect(bySha['a' * 64], first.millisecondsSinceEpoch);
      expect(bySha['b' * 64], second.millisecondsSinceEpoch);
    });

    test('track missing from a later manifest is removed', () async {
      await store.apply(
        _manifest(tracks: [_track('a' * 64), _track('b' * 64)]),
      );
      final result = await store.apply(_manifest(tracks: [_track('a' * 64)]));
      expect(result.tracksRemoved, 1);
      final rows = await db.select(db.tracks).get();
      expect(rows.map((r) => r.sha), ['a' * 64]);
    });

    test(
      'release and artist missing from a later manifest are removed',
      () async {
        await store.apply(
          _manifest(
            tracks: [_track('a' * 64)],
            releases: [
              ManifestRelease(
                id: 'r-keep',
                title: 'Keep',
                artist: 'Artist A',
                year: '2024',
                artSha: null,
                type: null,
                totalTracks: 1,
                trackShas: ['a' * 64],
              ),
              ManifestRelease(
                id: 'r-drop',
                title: 'Drop',
                artist: 'Artist A',
                year: '2024',
                artSha: null,
                type: null,
                totalTracks: 1,
                trackShas: ['a' * 64],
              ),
            ],
            artists: const [
              ManifestArtist(name: 'Artist A', artSha: null),
              ManifestArtist(name: 'Artist B', artSha: null),
            ],
          ),
        );
        await store.apply(
          _manifest(
            tracks: [_track('a' * 64)],
            releases: [
              ManifestRelease(
                id: 'r-keep',
                title: 'Keep',
                artist: 'Artist A',
                year: '2024',
                artSha: null,
                type: null,
                totalTracks: 1,
                trackShas: ['a' * 64],
              ),
            ],
            artists: const [ManifestArtist(name: 'Artist A', artSha: null)],
          ),
        );

        final releases = await db.select(db.releases).get();
        expect(releases.map((r) => r.id), ['r-keep']);
        final artists = await db.select(db.artists).get();
        expect(artists.map((a) => a.name), ['Artist A']);
      },
    );

    test(
      'tracks inserted with null addedAt survive a read-back without throwing',
      () async {
        // 132 of the 161 tracks on the live daemon arrive with no
        // addedAt timestamp. The store must round-trip them as null
        // instead of crashing in _trackFromRow's addedAt! assert.
        final manifest = _manifest(
          tracks: [_track('a' * 64), _track('b' * 64, addedAt: null)],
        );
        await store.apply(manifest);

        final rows = await db.select(db.tracks).get();
        expect(rows, hasLength(2));
        expect(rows.firstWhere((r) => r.sha == 'a' * 64).addedAt, isNull);
        expect(rows.firstWhere((r) => r.sha == 'b' * 64).addedAt, isNull);

        // The post-apply in-memory read path is what used to crash.
        final fresh = await store.allTracksNewestFirst();
        expect(fresh.map((t) => t.sha).toSet(), {'a' * 64, 'b' * 64});
        expect(fresh.firstWhere((t) => t.sha == 'a' * 64).addedAt, isNull);
      },
    );
  });

  group('ManifestStore.tracksAddedSince', () {
    late TunesDatabase db;
    late ManifestStore store;

    setUp(() {
      db = _newDb();
      store = ManifestStore(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('returns only tracks with addedAt >= cutoff, newest first', () async {
      await store.apply(
        _manifest(
          tracks: [
            _track('a' * 64, addedAt: DateTime.utc(2026, 8, 25)),
            _track('b' * 64, addedAt: DateTime.utc(2026, 8, 30, 9)),
            _track('c' * 64, addedAt: DateTime.utc(2026, 8, 30, 12)),
            _track('d' * 64, addedAt: DateTime.utc(2026, 8, 31)),
          ],
        ),
      );
      final hits = await store.tracksAddedSince(
        DateTime.utc(2026, 8, 30),
        limit: 10,
      );
      final shas = hits.map((t) => t.sha).toList();
      expect(shas, ['d' * 64, 'c' * 64, 'b' * 64]);
    });
  });

  group('ManifestStore.searchTracks', () {
    late TunesDatabase db;
    late ManifestStore store;

    setUp(() async {
      db = _newDb();
      store = ManifestStore(db);
      await store.apply(
        _manifest(
          tracks: [
            ManifestTrack(
              sha: 'a' * 64,
              size: 1,
              codec: 'flac',
              sampleRate: 44100,
              channels: 2,
              bitrate: 950000,
              durationMs: 120000,
              title: 'Escape Plan',
              artist: 'Travis Scott',
              album: 'FTR',
              year: '2021',
              artSha: null,
              releaseId: 'r1',
              trackNumber: 1,
              discNumber: null,
            ),
            ManifestTrack(
              sha: 'b' * 64,
              size: 1,
              codec: 'flac',
              sampleRate: 44100,
              channels: 2,
              bitrate: 950000,
              durationMs: 120000,
              title: 'Mafia',
              artist: 'Travis Scott',
              album: 'FTR',
              year: '2021',
              artSha: null,
              releaseId: 'r1',
              trackNumber: 2,
              discNumber: null,
            ),
            ManifestTrack(
              sha: 'c' * 64,
              size: 1,
              codec: 'flac',
              sampleRate: 44100,
              channels: 2,
              bitrate: 950000,
              durationMs: 120000,
              title: 'Stairway',
              artist: 'Led Zeppelin',
              album: 'Untitled',
              year: '1971',
              artSha: null,
              releaseId: 'r2',
              trackNumber: 1,
              discNumber: null,
            ),
          ],
        ),
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('artist query ranks Travis Scott above Led Zeppelin', () async {
      final hits = await store.searchTracks('travis');
      expect(hits, isNotEmpty);
      final shas = hits.map((h) => h.sha).toSet();
      expect(shas.contains('a' * 64), isTrue);
      expect(shas.contains('b' * 64), isTrue);
      expect(shas.contains('c' * 64), isFalse);
    });

    test('empty query returns no hits', () async {
      expect(await store.searchTracks(''), isEmpty);
      expect(await store.searchTracks('   '), isEmpty);
    });
  });
}
