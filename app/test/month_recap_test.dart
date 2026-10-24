import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/domain/listening_stats.dart';
import 'package:tunes/domain/manifest.dart';
import 'package:tunes/domain/month_recap.dart';

ManifestTrack _t(String sha, String artist) => ManifestTrack(
  sha: sha,
  size: 1,
  codec: 'flac',
  sampleRate: 44100,
  channels: 2,
  bitrate: 900,
  durationMs: 180000,
  title: 'Song $sha',
  artist: artist,
  album: 'X',
  year: null,
  artSha: null,
  releaseId: null,
  trackNumber: null,
  discNumber: null,
);

void main() {
  final lib = {'a': _t('a', 'Maajins'), 'b': _t('b', 'TeeZandos')};
  List<ListenEvent> plays(String sha, int n, DateTime at) => [
    for (var i = 0; i < n; i++)
      ListenEvent(
        sha,
        at.add(Duration(minutes: 4 * i)),
        180000,
        completed: true,
      ),
  ];

  test('last month: hours, the song on repeat, the artist, the hour', () {
    final events = [
      ...plays('a', 30, DateTime(2026, 9, 12, 19)),
      ...plays('b', 12, DateTime(2026, 9, 20, 8)),
      // October does not count toward September.
      ...plays('b', 50, DateTime(2026, 10, 2, 9)),
    ];
    final r = MonthRecap.lastMonth(
      events: events,
      library: lib,
      now: DateTime(2026, 10, 24),
    )!;
    expect(r.monthName, 'September');
    expect(r.hours, 2); // 42 plays x 3 min = 2.1 h
    expect(r.topSong.name, 'Song a');
    expect(r.topSong.plays, 30);
    expect(r.topArtist.name, 'Maajins');
    expect(r.artists, 2);
    expect(r.peakHourLabel, '7 pm');
  });

  test('too little of a month makes no card', () {
    final r = MonthRecap.lastMonth(
      events: plays('a', 5, DateTime(2026, 9, 12, 19)),
      library: lib,
      now: DateTime(2026, 10, 24),
    );
    expect(r, isNull);
  });

  test('January looks back to December of the year before', () {
    final r = MonthRecap.lastMonth(
      events: plays('a', 45, DateTime(2025, 12, 31, 0)),
      library: lib,
      now: DateTime(2026, 1, 3),
    )!;
    expect(r.monthName, 'December');
    expect(r.peakHourLabel, 'midnight');
  });
}
