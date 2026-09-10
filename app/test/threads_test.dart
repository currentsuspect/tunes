import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/domain/manifest.dart';
import 'package:tunes/domain/threads.dart';

ManifestTrack t(
  String sha, {
  String artist = 'A',
  String title = 'x',
  List<String> featured = const [],
  DateTime? addedAt,
}) => ManifestTrack(
  sha: sha,
  size: 1,
  codec: 'flac',
  sampleRate: 44100,
  channels: 2,
  bitrate: 1000,
  durationMs: 180000,
  title: title,
  artist: artist,
  album: 'album',
  year: null,
  artSha: null,
  releaseId: null,
  trackNumber: null,
  discNumber: null,
  primaryArtist: artist,
  featured: featured,
  addedAt: addedAt,
);

/// A library with a real guest graph: Yeat hosts PlaqueBoyMax, appears on
/// Don Toliver's track, and has unplayed deep cuts of his own.
List<ManifestTrack> library() => [
  t('y1', artist: 'Yeat', title: 'Monëy so big'),
  t('y2', artist: 'Yeat', title: 'Talk', featured: ['PlaqueBoyMax']),
  t('y3', artist: 'Yeat', title: 'Flawlëss'),
  t('y4', artist: 'Yeat', title: 'Out thë way'),
  t('y5', artist: 'Yeat', title: 'Twizzy Rich'),
  t('d1', artist: 'Don Toliver', title: 'New Drop', featured: ['Yeat']),
  t('d2', artist: 'Don Toliver', title: 'Slow Motion', featured: ['Yeat']),
  t('p1', artist: 'PlaqueBoyMax', title: 'Vetement'),
  t('p2', artist: 'PlaqueBoyMax', title: '4N'),
  t('p3', artist: 'PlaqueBoyMax', title: 'Pink Panther'),
  t('v1', artist: 'Vax', title: 'Alone'),
];

void main() {
  test('guest spots surface around the most-played act', () {
    final rails = followThreads(library: library(), plays: {'y1': 9, 'y2': 4});
    final room = rails.where((r) => r.title.contains('in the room'));
    expect(room, isNotEmpty);
    final shas = room.first.tracks.map((t) => t.sha);
    // Don Toliver hosting Yeat, plus Yeat hosting PlaqueBoyMax.
    expect(shas, containsAll(['d1', 'y2']));
  });

  test('unplayed own tracks become deep cuts, played ones do not', () {
    final rails = followThreads(library: library(), plays: {'y1': 9, 'y2': 4});
    final cuts = rails.where((r) => r.title.contains('deep cuts'));
    expect(cuts, isNotEmpty);
    final shas = cuts.first.tracks.map((t) => t.sha).toSet();
    expect(shas, containsAll(['y3', 'y4']));
    expect(shas, isNot(contains('y1')));
    expect(shas, isNot(contains('y2')));
  });

  test('thin material gets no rail rather than a stub', () {
    final rails = followThreads(
      library: [t('v1', artist: 'Vax', title: 'Alone')],
      plays: const {},
    );
    expect(rails, isEmpty);
  });

  test('an empty library has no threads', () {
    expect(followThreads(library: const [], plays: const {}), isEmpty);
  });

  test('ownership ranks acts before any history exists', () {
    final rails = followThreads(library: library(), plays: const {});
    expect(rails, isNotEmpty);
    // PlaqueBoyMax and Yeat own the most tracks; Vax owns one and gets none.
    expect(rails.every((r) => r.act != 'Vax'), isTrue);
  });
}
