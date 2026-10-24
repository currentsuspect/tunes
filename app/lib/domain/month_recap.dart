import 'listening_stats.dart';
import 'manifest.dart';

/// "Your month in Tunes" (design approved 24 Oct): one calendar month of
/// listening in the few numbers worth sharing.
///
/// Pure, like [ListeningStats]: the same events, library and month give the
/// same card.
class MonthRecap {
  const MonthRecap({
    required this.month,
    required this.listened,
    required this.plays,
    required this.artists,
    required this.topSong,
    required this.topArtist,
    required this.peakHour,
  });

  /// The first day of the month this is about.
  final DateTime month;
  final Duration listened;
  final int plays;
  final int artists;
  final Ranked topSong;
  final Ranked topArtist;

  /// The hour of day (0-23) with the most listening.
  final int peakHour;

  static const _names = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String get monthName => _names[month.month - 1];

  /// "7 pm", "midnight", "noon".
  String get peakHourLabel => switch (peakHour) {
    0 => 'midnight',
    12 => 'noon',
    < 12 => '$peakHour am',
    _ => '${peakHour - 12} pm',
  };

  /// Whole hours, rounded the way a person would say it.
  int get hours => (listened.inMinutes / 60).round();

  /// The month that just ended, as of [now]: what the card is about, once
  /// a month is over. Null when there is too little in it to be worth a
  /// card (under two hours, or no song played through three times).
  static MonthRecap? lastMonth({
    required List<ListenEvent> events,
    required Map<String, ManifestTrack> library,
    required DateTime now,
  }) => of(
    events: events,
    library: library,
    month: DateTime(now.year, now.month - 1),
  );

  static MonthRecap? of({
    required List<ListenEvent> events,
    required Map<String, ManifestTrack> library,
    required DateTime month,
  }) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    var listenedMs = 0;
    var plays = 0;
    final byHour = List<int>.filled(24, 0);
    final songPlays = <String, int>{};
    final artistPlays = <String, int>{};
    for (final e in events) {
      if (e.at.isBefore(start) || !e.at.isBefore(end)) continue;
      listenedMs += e.listenedMs;
      byHour[e.at.hour] += e.listenedMs;
      if (!e.completed) continue;
      plays++;
      final t = library[e.sha];
      if (t == null) continue;
      songPlays.update(t.sha, (v) => v + 1, ifAbsent: () => 1);
      artistPlays.update(t.artistKey, (v) => v + 1, ifAbsent: () => 1);
    }
    if (listenedMs < 2 * 3600 * 1000 || songPlays.isEmpty) return null;
    String best(Map<String, int> m) {
      final keys = m.keys.toList()
        ..sort((a, b) {
          final c = m[b]!.compareTo(m[a]!);
          return c != 0 ? c : a.compareTo(b);
        });
      return keys.first;
    }

    final songSha = best(songPlays);
    if (songPlays[songSha]! < 3) return null;
    final song = library[songSha]!;
    final artist = best(artistPlays);
    var peak = 0;
    for (var h = 1; h < 24; h++) {
      if (byHour[h] > byHour[peak]) peak = h;
    }
    return MonthRecap(
      month: start,
      listened: Duration(milliseconds: listenedMs),
      plays: plays,
      artists: artistPlays.length,
      topSong: Ranked(
        song.title,
        songPlays[songSha]!,
        sub: song.artistDisplay,
        artSha: song.artSha,
        sha: songSha,
      ),
      topArtist: Ranked(artist, artistPlays[artist]!),
      peakHour: peak,
    );
  }
}
