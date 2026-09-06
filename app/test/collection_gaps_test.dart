import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/domain/collection_gaps.dart';
import 'package:tunes/domain/discography.dart';
import 'package:tunes/domain/manifest.dart';

MissingRelease _missing(
  String artist,
  String title, {
  String? year,
  int artistTracks = 10,
  int? owned,
  int? total,
}) => MissingRelease(
  id: '$artist-$title',
  title: title,
  artist: artist,
  type: 'Album',
  year: year,
  artistTracks: artistTracks,
  artistOwnedReleases: owned,
  artistTotalReleases: total,
);

ManifestTrack _track(String sha, String artist, {String? primary}) =>
    ManifestTrack(
      primaryArtist: primary,
      sha: sha,
      size: 0,
      codec: 'flac',
      sampleRate: 44100,
      channels: 2,
      bitrate: 900000,
      durationMs: 180000,
      title: 't',
      artist: artist,
      album: 'a',
      year: null,
      artSha: null,
      releaseId: null,
      trackNumber: null,
      discNumber: null,
    );

void main() {
  group('collectionGaps', () {
    test('ranks by what is listened to, not what is owned', () {
      // The whole reason play history had to exist first. A library can be
      // full of an act you never play; that is not the act to go completing.
      final gaps = collectionGaps(
        missing: [
          _missing('Hoarded', 'A', artistTracks: 80),
          _missing('Played', 'B', artistTracks: 5),
        ],
        plays: {'Played': 12},
      );
      expect(gaps.map((g) => g.artist), ['Played', 'Hoarded']);
    });

    test('falls back to ownership when nothing has been played', () {
      // A fresh install has no history at all, and the screen still has to
      // put something sensible first.
      final gaps = collectionGaps(
        missing: [
          _missing('Few', 'A', artistTracks: 5),
          _missing('Many', 'B', artistTracks: 80),
        ],
        plays: const {},
      );
      expect(gaps.map((g) => g.artist), ['Many', 'Few']);
    });

    test('groups an act into one entry, newest release first', () {
      final gaps = collectionGaps(
        missing: [
          _missing('Yeat', 'Lyfë', year: '2022'),
          _missing('Yeat', '2093', year: '2024'),
          _missing('Yeat', 'Alivë', year: '2021'),
        ],
        plays: const {},
      );
      expect(gaps, hasLength(1));
      expect(gaps.single.missing.map((m) => m.title), [
        '2093',
        'Lyfë',
        'Alivë',
      ]);
    });

    test('completion is null, not zero, when the daemon did not say', () {
      // An empty progress bar claims you own none of it. Saying nothing is
      // the only honest rendering of an unknown.
      final unknown = collectionGaps(
        missing: [_missing('A', 'x')],
        plays: const {},
      ).single;
      expect(unknown.completion, isNull);

      final known = collectionGaps(
        missing: [_missing('A', 'x', owned: 5, total: 20)],
        plays: const {},
      ).single;
      expect(known.completion, 0.25);
    });
  });

  group('playsByArtist', () {
    test('credits plays to the act that made the track', () {
      final plays = playsByArtist(
        {'s1': 3, 's2': 1},
        [_track('s1', 'Yeat'), _track('s2', 'Yeat')],
      );
      expect(plays, {'Yeat': 4});
    });

    test('a play of a track no longer in the library is dropped', () {
      // Rather than credited to an invented act, which would then rank.
      expect(playsByArtist({'gone': 9}, [_track('s1', 'Yeat')]), isEmpty);
    });

    test('a guest verse counts for the act, not the credit line', () {
      // The daemon splits the credit; the app groups on what it sent. A play
      // of "Don Toliver feat. Travis Scott" is a Don Toliver play, or every
      // guest appearance would look like an act you seek out.
      final plays = playsByArtist(
        {'s1': 2},
        [
          _track(
            's1',
            'Don Toliver feat. Travis Scott',
            primary: 'Don Toliver',
          ),
        ],
      );
      expect(plays, {'Don Toliver': 2});
    });

    test('an older sync with no primary act still counts', () {
      // Tracks synced before the daemon sent primaryArtist fall back to the
      // raw credit rather than being dropped from the ranking entirely.
      final plays = playsByArtist({'s1': 2}, [_track('s1', 'Nemzzz')]);
      expect(plays, {'Nemzzz': 2});
    });
  });
}
