import 'manifest.dart';

/// One listen as the history table keeps it: a play or a skip.
class ListenEvent {
  const ListenEvent(
    this.sha,
    this.at,
    this.listenedMs, {
    required this.completed,
  });

  final String sha;
  final DateTime at;
  final int listenedMs;
  final bool completed;
}

/// How far back the numbers look.
enum StatsRange {
  week('7 days', 7),
  month('30 days', 30),
  year('Year', 365),
  all('All time', null);

  const StatsRange(this.label, this.days);
  final String label;
  final int? days;
}

/// A name and how many plays it had.
class Ranked {
  const Ranked(
    this.name,
    this.plays, {
    this.sub,
    this.artSha,
    this.sha,
    this.releaseId,
  });

  final String name;
  final int plays;

  /// Second line, e.g. the artist of a song.
  final String? sub;
  final String? artSha;
  final String? sha;

  /// For an album: its release, when the library knows it.
  final String? releaseId;
}

/// What the "Your listening" page says, worked out from the history.
///
/// Pure: given the same events, library and clock it says the same thing, so
/// it is tested on its own and the page only draws it.
class ListeningStats {
  const ListeningStats({
    required this.range,
    required this.listened,
    required this.plays,
    required this.skips,
    required this.artists,
    required this.newArtists,
    required this.buckets,
    required this.bucketLabels,
    required this.byHour,
    required this.topArtists,
    required this.topSongs,
    required this.topAlbums,
    required this.streakDays,
    required this.heardShare,
  });

  final StatsRange range;

  /// Time actually heard, skips included: a skip after two minutes was still
  /// two minutes of music.
  final Duration listened;
  final int plays;
  final int skips;

  /// Different artists played in the range.
  final int artists;

  /// Artists whose first ever play falls inside the range.
  final int newArtists;

  /// Minutes per day (week, month), per month (year, all time), oldest first.
  final List<int> buckets;
  final List<String> bucketLabels;

  /// Minutes heard in each hour of the day, 0 to 23.
  final List<int> byHour;

  final List<Ranked> topArtists;
  final List<Ranked> topSongs;
  final List<Ranked> topAlbums;

  /// Days in a row, up to today (or yesterday, if today has nothing yet),
  /// with at least one play. Counted over all history, not just the range.
  final int streakDays;

  /// Share of the library that has been played at least once, ever.
  final double heardShare;

  bool get isEmpty => plays == 0 && skips == 0;

  /// Share of starts that were skipped.
  double get skipRate => plays + skips == 0 ? 0 : skips / (plays + skips);

  /// The hour with the most listening, or null with no listening at all.
  int? get peakHour {
    var best = -1;
    var at = -1;
    for (var h = 0; h < 24; h++) {
      if (byHour[h] > best) {
        best = byHour[h];
        at = h;
      }
    }
    return best <= 0 ? null : at;
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

  static ListeningStats compute({
    required List<ListenEvent> events,
    required Map<String, ManifestTrack> library,
    required StatsRange range,
    required DateTime now,
    int top = 5,
  }) {
    final today = _day(now);
    final DateTime? since = range.days == null
        ? null
        : today.subtract(Duration(days: range.days! - 1));
    final inRange = [
      for (final e in events)
        if (since == null || !e.at.isBefore(since)) e,
    ];

    var listenedMs = 0;
    var plays = 0;
    var skips = 0;
    final byHourMs = List<int>.filled(24, 0);
    final artistPlays = <String, int>{};
    final songPlays = <String, int>{};
    final albumPlays = <String, int>{};
    final albumInfo = <String, ManifestTrack>{};
    for (final e in inRange) {
      listenedMs += e.listenedMs;
      byHourMs[e.at.hour] += e.listenedMs;
      if (!e.completed) {
        skips++;
        continue;
      }
      plays++;
      final t = library[e.sha];
      if (t == null) continue;
      artistPlays.update(t.artistKey, (v) => v + 1, ifAbsent: () => 1);
      songPlays.update(t.sha, (v) => v + 1, ifAbsent: () => 1);
      final albumKey = '${t.album}\u0000${t.artistKey}';
      albumPlays.update(albumKey, (v) => v + 1, ifAbsent: () => 1);
      albumInfo.putIfAbsent(albumKey, () => t);
    }

    // Buckets: days for the short ranges, months for the long ones.
    final buckets = <int>[];
    final labels = <String>[];
    if (range.days != null && range.days! <= 30) {
      final n = range.days!;
      final perDay = List<int>.filled(n, 0);
      for (final e in inRange) {
        final i = _day(e.at).difference(since!).inDays;
        if (i >= 0 && i < n) perDay[i] += e.listenedMs;
      }
      for (var i = 0; i < n; i++) {
        buckets.add((perDay[i] / 60000).round());
        final d = since!.add(Duration(days: i));
        labels.add(
          n <= 7 ? _days[d.weekday - 1] : '${d.day} ${_months[d.month - 1]}',
        );
      }
    } else {
      DateTime first;
      if (range.days != null) {
        first = DateTime(now.year, now.month - 11);
      } else {
        final earliest = inRange.isEmpty
            ? now
            : inRange.map((e) => e.at).reduce((a, b) => a.isBefore(b) ? a : b);
        first = DateTime(earliest.year, earliest.month);
        // Never fewer than six bars, so a new history is not one fat block.
        final floor = DateTime(now.year, now.month - 5);
        if (first.isAfter(floor)) first = floor;
      }
      final months = (now.year - first.year) * 12 + now.month - first.month + 1;
      final perMonth = List<int>.filled(months, 0);
      for (final e in inRange) {
        final i = (e.at.year - first.year) * 12 + e.at.month - first.month;
        if (i >= 0 && i < months) perMonth[i] += e.listenedMs;
      }
      for (var i = 0; i < months; i++) {
        buckets.add((perMonth[i] / 60000).round());
        final m = DateTime(first.year, first.month + i);
        labels.add(
          m.month == 1 || i == 0
              ? '${_months[m.month - 1]} ${m.year % 100}'
              : _months[m.month - 1],
        );
      }
    }

    // New artists: first ever completed play inside the range.
    final firstHeard = <String, DateTime>{};
    final everHeard = <String>{};
    for (final e in events) {
      if (!e.completed) continue;
      everHeard.add(e.sha);
      final t = library[e.sha];
      if (t == null) continue;
      final prev = firstHeard[t.artistKey];
      if (prev == null || e.at.isBefore(prev)) firstHeard[t.artistKey] = e.at;
    }
    final newArtists = since == null
        ? firstHeard.length
        : firstHeard.values.where((d) => !d.isBefore(since)).length;

    // Streak, over all history.
    final playedDays = {
      for (final e in events)
        if (e.completed) _day(e.at),
    };
    var cursor = playedDays.contains(today)
        ? today
        : today.subtract(const Duration(days: 1));
    var streak = 0;
    while (playedDays.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    List<Ranked> rank(Map<String, int> m, Ranked Function(String, int) make) {
      final keys = m.keys.toList()
        ..sort((a, b) {
          final c = m[b]!.compareTo(m[a]!);
          return c != 0 ? c : a.compareTo(b);
        });
      return [for (final k in keys.take(top)) make(k, m[k]!)];
    }

    final libraryShas = library.keys.toSet();
    final heard = everHeard.where(libraryShas.contains).length;

    return ListeningStats(
      range: range,
      listened: Duration(milliseconds: listenedMs),
      plays: plays,
      skips: skips,
      artists: artistPlays.length,
      newArtists: newArtists,
      buckets: buckets,
      bucketLabels: labels,
      byHour: [for (final ms in byHourMs) (ms / 60000).round()],
      topArtists: rank(artistPlays, (k, n) => Ranked(k, n)),
      topSongs: rank(songPlays, (k, n) {
        final t = library[k]!;
        return Ranked(
          t.title,
          n,
          sub: t.artistDisplay,
          artSha: t.artSha,
          sha: k,
        );
      }),
      topAlbums: rank(albumPlays, (k, n) {
        final t = albumInfo[k]!;
        return Ranked(
          t.album,
          n,
          sub: t.artistKey,
          artSha: t.artSha,
          releaseId: t.releaseId,
        );
      }),
      streakDays: streak,
      heardShare: libraryShas.isEmpty ? 0 : heard / libraryShas.length,
    );
  }
}
