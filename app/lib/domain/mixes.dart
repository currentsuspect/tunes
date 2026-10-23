import 'dart:math';

import 'genre_lanes.dart';
import 'manifest.dart';

/// Playlists the app makes from how you listen, and albums it thinks you have
/// not found yet.
///
/// Everything here runs on the phone, from the library and the listening
/// history, and nothing about it leaves the device (docs/MIXES.md). It is pure:
/// no widgets, no clock, no database. Time comes in as [MixInputs.now], so every
/// rule can be tested at any hour of any day.
///
/// The rules are plain and the reasons are said. A mix names what it was built
/// from ("what you play on Fridays"), and it is left out when the history is too
/// thin to say anything honest. Nothing is invented to fill a shelf.

/// One finished play of a track, and when it started.
class PlayStamp {
  const PlayStamp(this.sha, this.at);

  final String sha;
  final DateTime at;
}

enum MixKind { weekday, timeOfDay, deepCuts, genre }

/// A playlist the app built, ready to play or to keep.
class Mix {
  const Mix({
    required this.id,
    required this.title,
    required this.note,
    required this.kind,
    required this.tracks,
  });

  /// Stable across a day or a week, so the same mix is the same mix when it is
  /// opened twice.
  final String id;
  final String title;

  /// Why it is this list, in a sentence.
  final String note;
  final MixKind kind;
  final List<ManifestTrack> tracks;
}

/// A record in the library that has never been played, and the reason it is
/// being pointed at.
class UnheardAlbum {
  const UnheardAlbum({
    required this.release,
    required this.songs,
    required this.why,
    this.addedAt,
  });

  final ManifestRelease release;
  final int songs;
  final String why;
  final DateTime? addedAt;
}

class MixInputs {
  const MixInputs({
    required this.tracks,
    required this.artists,
    required this.releases,
    required this.stamps,
    required this.liked,
    required this.now,
    this.removed = const {},
  });

  final List<ManifestTrack> tracks;
  final List<ManifestArtist> artists;
  final List<ManifestRelease> releases;
  final List<PlayStamp> stamps;

  /// Shas the listener has hearted: a decision, not a behaviour.
  final Set<String> liked;
  final DateTime now;

  /// Songs the listener took out, by mix id; under [removedEverywhere], out
  /// of every mix.
  final Map<String, Set<String>> removed;
}

/// The key in [MixInputs.removed] for songs kept out of every mix.
const removedEverywhere = '*';

/// Every mix that is worth showing right now, most relevant first.
///
/// [minTracks] is the floor: a mix with fewer songs than this is not a mix, it
/// is a handful, and is left out. [size] is how long one is.
List<Mix> buildMixes(MixInputs input, {int minTracks = 15, int size = 30}) {
  final ctx = _Context(input);
  final built = _allMixes(ctx, minTracks, size);
  if (input.removed.isEmpty) return built;

  // Songs taken out of a mix stay out, and the mix keeps its length. The
  // rest keep their places: the list is built as it would have been, the
  // removed songs are dropped, and the gap is filled from the end of a
  // longer build of the same mix. Building it again without them would
  // reshuffle every song the moment one is taken out.
  final everywhere = input.removed[removedEverywhere] ?? const <String>{};
  final wide = {for (final m in _allMixes(ctx, minTracks, size * 2)) m.id: m};
  final out = <Mix>[];
  for (final m in built) {
    final gone = {...everywhere, ...?input.removed[m.id]};
    if (gone.isEmpty) {
      out.add(m);
      continue;
    }
    final kept = [
      for (final t in m.tracks)
        if (!gone.contains(t.sha)) t,
    ];
    final have = {for (final t in m.tracks) t.sha};
    for (final t in wide[m.id]?.tracks ?? const <ManifestTrack>[]) {
      if (kept.length >= m.tracks.length) break;
      if (gone.contains(t.sha) || have.contains(t.sha)) continue;
      kept.add(t);
    }
    if (kept.length < minTracks) continue;
    out.add(
      Mix(id: m.id, title: m.title, note: m.note, kind: m.kind, tracks: kept),
    );
  }
  return out;
}

List<Mix> _allMixes(_Context ctx, int minTracks, int size) {
  final mixes = <Mix>[];

  final day = _weekdayMix(ctx, minTracks, size);
  if (day != null) mixes.add(day);

  final late = _timeOfDayMix(
    ctx,
    id: 'late-night',
    title: 'Late Night',
    note: 'What you play after dark.',
    hours: const {22, 23, 0, 1, 2, 3},
    showWhen: (h) => h >= 21 || h < 4,
    minTracks: minTracks,
    size: size,
  );
  if (late != null) mixes.add(late);

  final morning = _timeOfDayMix(
    ctx,
    id: 'morning',
    title: 'Morning',
    note: 'What you start the day with.',
    hours: const {5, 6, 7, 8, 9, 10},
    showWhen: (h) => h >= 5 && h < 12,
    minTracks: minTracks,
    size: size,
  );
  if (morning != null) mixes.add(morning);

  final deep = _deepCuts(ctx, minTracks, size);
  if (deep != null) mixes.add(deep);

  mixes.addAll(_genreLanes(ctx, minTracks, size));
  return mixes;
}

/// Albums you have not played a single song of, ordered by how likely they are
/// to be worth the trouble: recently added, by artists you already play, with
/// something you have hearted on them.
///
/// For finding what is already yours. A library of a thousand songs holds
/// records nobody opened.
List<UnheardAlbum> unheardAlbums(
  MixInputs input, {
  int limit = 12,
  int minSongs = 3,
  int minResults = 3,
}) {
  final ctx = _Context(input);
  final rng = Random(_seed('unheard', input.now, weekly: false));
  final scored = <({UnheardAlbum album, double score})>[];

  for (final r in input.releases) {
    final shas = r.trackShas.toSet();
    if (shas.length < minSongs) continue;
    if (shas.any((s) => (ctx.plays[s] ?? 0) > 0)) continue;

    DateTime? added;
    var likedHere = 0;
    for (final s in shas) {
      final t = ctx.bySha[s];
      if (t == null) continue;
      final a = t.addedAt;
      if (a != null && (added == null || a.isAfter(added))) added = a;
      if (input.liked.contains(s)) likedHere += 1;
    }
    final daysAgo = added == null
        ? null
        : input.now.difference(added).inDays.clamp(0, 100000);
    final recent = daysAgo == null ? 0.0 : max(0.0, 1 - daysAgo / 120) * 3;
    final act = ctx.artistPlays[_actOf(r.artist)] ?? 0;
    final affinity = min(5.0, act / 20);
    final score =
        recent + affinity + (likedHere > 0 ? 2 : 0) + rng.nextDouble() * 1.5;

    final why = daysAgo != null && daysAgo <= 30
        ? (daysAgo == 0
              ? 'Added today, not played'
              : 'Added ${daysAgo == 1 ? 'yesterday' : '$daysAgo days ago'}, not played')
        : act > 0
        ? 'By ${r.artist}, who you play. Never opened.'
        : 'Never played';
    scored.add((
      album: UnheardAlbum(
        release: r,
        songs: shas.length,
        why: why,
        addedAt: added,
      ),
      score: score,
    ));
  }

  if (scored.length < minResults) return const [];
  scored.sort((a, b) => b.score.compareTo(a.score));
  return [for (final s in scored.take(limit)) s.album];
}

// ----------------------------------------------------------------- internals

class _Context {
  _Context(this.input) {
    for (final t in input.tracks) {
      bySha[t.sha] = t;
    }
    for (final a in input.artists) {
      tagsByArtist[a.name] = a.tags;
      if (a.genres.isNotEmpty) genresByArtist[a.name] = a.genres;
    }
    for (final p in input.stamps) {
      plays[p.sha] = (plays[p.sha] ?? 0) + 1;
    }
    for (final t in input.tracks) {
      final n = plays[t.sha] ?? 0;
      if (n > 0) {
        artistPlays[t.artistKey] = (artistPlays[t.artistKey] ?? 0) + n;
      }
    }
  }

  final MixInputs input;
  final Map<String, ManifestTrack> bySha = {};
  final Map<String, List<String>> tagsByArtist = {};
  final Map<String, List<ArtistGenre>> genresByArtist = {};
  final Map<String, int> plays = {};
  final Map<String, int> artistPlays = {};

  DateTime get now => input.now;

  /// Plays of each song whose start satisfies [when].
  Map<String, int> playsWhen(bool Function(DateTime at) when) {
    final out = <String, int>{};
    for (final p in input.stamps) {
      if (when(p.at)) out[p.sha] = (out[p.sha] ?? 0) + 1;
    }
    return out;
  }
}

/// The act behind a release's credit line, matching how the library groups
/// tracks by act.
String _actOf(String credit) => credit;

/// A number that is the same for the same mix all day (or all week) and
/// different tomorrow (or next week): a stable shuffle, not a fresh one on
/// every build.
int _seed(String id, DateTime now, {required bool weekly}) {
  final day = DateTime(now.year, now.month, now.day);
  final span = weekly
      ? day.difference(DateTime(2026, 1, 5)).inDays ~/ 7
      : day.difference(DateTime(2026, 1, 1)).inDays;
  var h = 0x811c9dc5;
  for (final c in '$id:$span'.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0x7fffffff;
  }
  return h;
}

/// The top of [ranked], at most [perArtist] from any one act, [size] long, so a
/// mix reads as a mix and not as one artist's album with extras.
List<ManifestTrack> _diversify(
  List<ManifestTrack> ranked,
  int size,
  int perArtist,
) {
  final seen = <String, int>{};
  final out = <ManifestTrack>[];
  for (final t in ranked) {
    final n = seen[t.artistKey] ?? 0;
    if (n >= perArtist) continue;
    seen[t.artistKey] = n + 1;
    out.add(t);
    if (out.length >= size) break;
  }
  return out;
}

List<ManifestTrack> _shuffled(List<ManifestTrack> l, Random rng) =>
    [...l]..shuffle(rng);

const _weekdayThemes = <int, ({String title, String name})>{
  DateTime.monday: (title: 'Monday Reset', name: 'Mondays'),
  DateTime.tuesday: (title: 'Tuesday Mix', name: 'Tuesdays'),
  DateTime.wednesday: (title: 'Wednesday Mix', name: 'Wednesdays'),
  DateTime.thursday: (title: 'Thursday Mix', name: 'Thursdays'),
  DateTime.friday: (title: 'Feel Good Friday', name: 'Fridays'),
  DateTime.saturday: (title: 'Saturday Night', name: 'Saturdays'),
  DateTime.sunday: (title: 'Sunday Sessions', name: 'Sundays'),
};

/// Today's mix: what you play on this day of the week, and the songs you love.
///
/// Built from your own Fridays, not from a guess about what a Friday sounds
/// like. When there is little history for the day it falls back to what you
/// play most and love most, and says so.
Mix? _weekdayMix(_Context c, int minTracks, int size) {
  final wd = c.now.weekday;
  final theme = _weekdayThemes[wd]!;
  final onDay = c.playsWhen((at) => at.weekday == wd);
  final dayHistory = onDay.values.fold<int>(0, (a, b) => a + b);

  final scored = <({ManifestTrack t, int score})>[];
  for (final t in c.input.tracks) {
    final score =
        3 * (onDay[t.sha] ?? 0) +
        (c.plays[t.sha] ?? 0) +
        (c.input.liked.contains(t.sha) ? 4 : 0);
    if (score > 0) scored.add((t: t, score: score));
  }
  scored.sort((a, b) => b.score.compareTo(a.score));
  final pool = _diversify([for (final s in scored) s.t], size * 2, 3);
  if (pool.length < minTracks) return null;

  final rng = Random(_seed('weekday-$wd', c.now, weekly: true));
  final tracks = _shuffled(pool.take(size).toList(), rng);
  return Mix(
    id: 'weekday-$wd',
    title: theme.title,
    kind: MixKind.weekday,
    note: dayHistory >= 10
        ? 'What you play on ${theme.name}, and the songs you love.'
        : 'The songs you play and love most, for a ${_dayName(wd)}.',
    tracks: tracks,
  );
}

String _dayName(int weekday) => const [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
][weekday - 1];

/// A mix of what you actually play in some hours, offered only during them.
Mix? _timeOfDayMix(
  _Context c, {
  required String id,
  required String title,
  required String note,
  required Set<int> hours,
  required bool Function(int hour) showWhen,
  required int minTracks,
  required int size,
}) {
  if (!showWhen(c.now.hour)) return null;
  final inHours = c.playsWhen((at) => hours.contains(at.hour));
  final scored = <({ManifestTrack t, int score})>[];
  for (final t in c.input.tracks) {
    final n = inHours[t.sha] ?? 0;
    if (n == 0) continue;
    scored.add((
      t: t,
      score:
          n * 3 +
          (c.plays[t.sha] ?? 0) +
          (c.input.liked.contains(t.sha) ? 2 : 0),
    ));
  }
  scored.sort((a, b) => b.score.compareTo(a.score));
  final pool = _diversify([for (final s in scored) s.t], size * 2, 3);
  if (pool.length < minTracks) return null;
  final rng = Random(_seed(id, c.now, weekly: false));
  return Mix(
    id: id,
    title: title,
    kind: MixKind.timeOfDay,
    note: note,
    tracks: _shuffled(pool.take(size).toList(), rng),
  );
}

/// Songs you have never played, by the artists you play most.
Mix? _deepCuts(_Context c, int minTracks, int size) {
  final top =
      (c.artistPlays.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .take(6)
          .map((e) => e.key)
          .toSet();
  if (top.isEmpty) return null;
  final unplayed = [
    for (final t in c.input.tracks)
      if (top.contains(t.artistKey) && (c.plays[t.sha] ?? 0) == 0) t,
  ];
  final rng = Random(_seed('deep-cuts', c.now, weekly: false));
  final pool = _diversify(_shuffled(unplayed, rng), size, 4);
  if (pool.length < minTracks) return null;
  return Mix(
    id: 'deep-cuts',
    title: 'Deep Cuts',
    kind: MixKind.deepCuts,
    note: 'Songs by the artists you play most that you have never played.',
    tracks: pool,
  );
}

/// Tags too general to say what a record sounds like.
const vagueTags = {
  'seen live',
  'favorites',
  'favourite',
  'favourites',
  'favorite',
  'american',
  'british',
  'canadian',
  'male vocalists',
  'female vocalists',
  'usa',
  'uk',
  'all',
  'under 2000 listeners',
  'good',
  'awesome',
};

String _tagKey(String tag) =>
    tag.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

String _titleCase(String tag) => tag
    .trim()
    .split(RegExp(r'\s+'))
    .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
    .join(' ');

/// A mix per kind of music the library is made of.
///
/// From the box's clean genres when it sends them: three lanes that differ and
/// rotate weekly (see genre_lanes.dart). Without them, the old way: the two
/// biggest raw tags.
List<Mix> _genreLanes(_Context c, int minTracks, int size) {
  if (c.genresByArtist.isEmpty) return _tagLanes(c, minTracks, size);
  final lanes = pickGenreLanes(
    tracks: c.input.tracks,
    genresByArtist: c.genresByArtist,
    plays: c.plays,
    now: c.now,
    minTracks: max(minTracks, 25),
    minMix: minTracks,
  );
  final out = <Mix>[];
  for (final l in lanes) {
    final key = _tagKey(l.name);
    final m = _laneMix(
      c,
      id: 'genre-$key',
      title: l.name,
      // A quiet lane leads with what she has not heard; the rest with
      // favourites.
      note: l.discovery
          ? 'Your ${l.name}, the part you rarely play.'
          : 'Your ${l.name}, favourites first.',
      pool: l.tracks,
      favouritesFirst: !l.discovery,
      minTracks: minTracks,
      size: size,
    );
    if (m != null) out.add(m);
  }
  return out;
}

/// Before the box sent genres: the two biggest tags. Tags that only differ in
/// how they are spelled ("hip hop", "Hip-Hop") are one tag.
List<Mix> _tagLanes(_Context c, int minTracks, int size) {
  // Per tag: which tracks, and the spellings seen (the commonest is the name).
  final tracksFor = <String, List<ManifestTrack>>{};
  final spellings = <String, Map<String, int>>{};
  for (final t in c.input.tracks) {
    final tags = c.tagsByArtist[t.artistKey] ?? const <String>[];
    final seen = <String>{};
    for (final raw in tags.take(5)) {
      final key = _tagKey(raw);
      if (key.isEmpty || vagueTags.contains(raw.toLowerCase())) continue;
      if (!seen.add(key)) continue;
      tracksFor.putIfAbsent(key, () => []).add(t);
      final sp = spellings.putIfAbsent(key, () => {});
      sp[raw.toLowerCase()] = (sp[raw.toLowerCase()] ?? 0) + 1;
    }
  }
  final big =
      tracksFor.entries
          .where((e) => e.value.length >= max(minTracks, 25))
          .toList()
        ..sort((a, b) => b.value.length.compareTo(a.value.length));

  final out = <Mix>[];
  for (final e in big.take(2)) {
    final name =
        (spellings[e.key]!.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .first
            .key;
    final m = _laneMix(
      c,
      id: 'genre-${e.key}',
      title: _titleCase(name),
      note: 'Your ${name.toLowerCase()}, favourites first.',
      pool: e.value,
      favouritesFirst: true,
      minTracks: minTracks,
      size: size,
    );
    if (m != null) out.add(m);
  }
  return out;
}

Mix? _laneMix(
  _Context c, {
  required String id,
  required String title,
  required String note,
  required List<ManifestTrack> pool,
  required bool favouritesFirst,
  required int minTracks,
  required int size,
}) {
  final rng = Random(_seed(id, c.now, weekly: true));
  // Scored once per track. A random number drawn inside the comparison would
  // give a different answer each time two tracks were compared.
  final scored = [
    for (final t in pool)
      (
        t: t,
        score: favouritesFirst
            ? (c.plays[t.sha] ?? 0) +
                  (c.input.liked.contains(t.sha) ? 4 : 0) +
                  rng.nextDouble() * 2
            // Discovery: unplayed first, hearts still count a little.
            : -(c.plays[t.sha] ?? 0) * 2 +
                  (c.input.liked.contains(t.sha) ? 1 : 0) +
                  rng.nextDouble() * 2,
      ),
  ]..sort((a, b) => b.score.compareTo(a.score));
  final ranked = [for (final x in scored) x.t];
  final tracks = _diversify(ranked, size, 3);
  if (tracks.length < minTracks) return null;
  return Mix(
    id: id,
    title: title,
    kind: MixKind.genre,
    note: note,
    tracks: _shuffled(tracks, rng),
  );
}
