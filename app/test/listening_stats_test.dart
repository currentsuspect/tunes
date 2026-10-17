import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/domain/listening_stats.dart';
import 'package:tunes/domain/manifest.dart';

ManifestTrack _t(String sha, String artist, String album) => ManifestTrack(
  sha: sha,
  size: 1,
  codec: 'flac',
  sampleRate: 44100,
  channels: 2,
  bitrate: 1000,
  durationMs: 180000,
  title: 'Song $sha',
  artist: artist,
  album: album,
  year: '2026',
  artSha: null,
  releaseId: null,
  trackNumber: null,
  discNumber: null,
  primaryArtist: artist,
  featured: const [],
);

void main() {
  final now = DateTime(2026, 10, 9, 21);
  final lib = {
    for (final t in [
      _t('a', 'Swapa', 'X'),
      _t('b', 'Swapa', 'X'),
      _t('c', 'Yeat', 'Y'),
      _t('d', 'Sade', 'Z'),
    ])
      t.sha: t,
  };
  ListenEvent play(String sha, DateTime at, {int min = 3}) =>
      ListenEvent(sha, at, min * 60000, completed: true);
  ListenEvent skip(String sha, DateTime at) =>
      ListenEvent(sha, at, 20000, completed: false);

  final events = [
    play('d', DateTime(2026, 8, 1, 10)), // Sade first heard long ago
    play('a', DateTime(2026, 10, 7, 22)),
    play('a', DateTime(2026, 10, 8, 22)),
    play('b', DateTime(2026, 10, 9, 9)),
    play('c', DateTime(2026, 10, 9, 22)),
    skip('c', DateTime(2026, 10, 9, 22, 5)),
  ];

  test('a week: totals, buckets, top lists, new artists', () {
    final s = ListeningStats.compute(
      events: events,
      library: lib,
      range: StatsRange.week,
      now: now,
    );
    expect(s.plays, 4);
    expect(s.skips, 1);
    expect(s.listened, const Duration(minutes: 12, seconds: 20));
    expect(s.buckets.length, 7);
    expect(s.buckets.last, 6); // today: 3 + 3 + a third of a minute
    expect(s.bucketLabels.last, 'Fri');
    expect(s.topArtists.first.name, 'Swapa');
    expect(s.topArtists.first.plays, 3);
    expect(s.topSongs.first.sha, 'a');
    expect(s.topAlbums.first.name, 'X');
    expect(s.artists, 2);
    // Swapa and Yeat are new this week; Sade was first heard in August.
    expect(s.newArtists, 2);
    expect(s.peakHour, 22);
    expect(s.skipRate, closeTo(0.2, 1e-9));
  });

  test('streak counts back from today over all history', () {
    final s = ListeningStats.compute(
      events: events,
      library: lib,
      range: StatsRange.week,
      now: now,
    );
    expect(s.streakDays, 3);
    // Nothing yet today still keeps yesterday's run alive.
    final tomorrow = ListeningStats.compute(
      events: events,
      library: lib,
      range: StatsRange.week,
      now: DateTime(2026, 10, 10, 8),
    );
    expect(tomorrow.streakDays, 3);
  });

  test('long ranges go by month and share of library is all time', () {
    final s = ListeningStats.compute(
      events: events,
      library: lib,
      range: StatsRange.all,
      now: now,
    );
    expect(s.buckets.length, greaterThanOrEqualTo(6));
    expect(s.buckets.last, 12);
    expect(s.heardShare, 1.0);
    expect(s.newArtists, 3);
  });

  test('empty history says so', () {
    final s = ListeningStats.compute(
      events: const [],
      library: lib,
      range: StatsRange.month,
      now: now,
    );
    expect(s.isEmpty, isTrue);
    expect(s.peakHour, isNull);
    expect(s.streakDays, 0);
    expect(s.buckets.length, 30);
  });
}
