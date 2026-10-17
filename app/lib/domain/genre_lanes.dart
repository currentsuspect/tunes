/// Which genres get a mix this week. Pure Dart.
///
/// Owner, 17 Oct: the genre mixes were stuck in one genre. They took the two
/// biggest raw tags, which in a mostly hip-hop library were two spellings of
/// hip-hop, every week. With the box's clean genres (tunesd genres.ts) the
/// library holds ~20 genres big enough for a mix; this picks three that
/// differ, and rotates them week by week:
///
/// 1. every genre in turn, biggest first,
/// 2. a genre from another family, on its own rotation,
/// 3. one she has played least for its size, from a third family where there
///    is one: discovery inside what is hers.
///
/// A family's broad genre ("Hip-Hop") only stands in when that family has no
/// specific room big enough.
library;

import 'dart:math';

import 'manifest.dart';

final class GenreLane {
  const GenreLane({
    required this.name,
    required this.family,
    required this.tracks,
    required this.discovery,
  });

  final String name;
  final String family;
  final List<ManifestTrack> tracks;

  /// Picked because she has barely played it.
  final bool discovery;
}

List<GenreLane> pickGenreLanes({
  required List<ManifestTrack> tracks,
  required Map<String, List<ArtistGenre>> genresByArtist,
  required Map<String, int> plays,
  required DateTime now,
  int minTracks = 25,
  int minMix = 15,
  int perArtist = 3,
  int count = 3,
}) {
  final members = <String, List<ManifestTrack>>{};
  final info = <String, ArtistGenre>{};
  for (final t in tracks) {
    final gs = genresByArtist[t.artistKey] ?? const <ArtistGenre>[];
    // An artist's two strongest genres; a third is usually a passing tag.
    for (final g in gs.take(2)) {
      final key = '${g.family}|${g.name}';
      members.putIfAbsent(key, () => []).add(t);
      info.putIfAbsent(key, () => g);
    }
  }
  // A mix takes at most [perArtist] songs from one artist, so a genre that is
  // 40 songs by two artists still only makes a mix of six. Count what a mix
  // could actually use.
  int usable(List<ManifestTrack> ts) {
    final by = <String, int>{};
    for (final t in ts) {
      by[t.artistKey] = (by[t.artistKey] ?? 0) + 1;
    }
    return by.values.fold(0, (sum, n) => sum + min(n, perArtist));
  }

  var candidates = [
    for (final e in members.entries)
      if (e.value.length >= minTracks && usable(e.value) >= minMix) e.key,
  ];
  // A family's broad genre only where it has no specific room of its own.
  final specificFamilies = {
    for (final k in candidates)
      if (!info[k]!.broad) info[k]!.family,
  };
  candidates = [
    for (final k in candidates)
      if (!info[k]!.broad || !specificFamilies.contains(info[k]!.family)) k,
  ]..sort(); // deterministic before any rotation
  if (candidates.isEmpty) return const [];

  final week = _weekOf(now);
  int sizeOf(String k) => members[k]!.length;
  final bySize = [...candidates]
    ..sort((a, b) => sizeOf(b).compareTo(sizeOf(a)));

  final chosen = <String>[];
  final discoveryKeys = <String>{};
  Set<String> familiesChosen() => {for (final k in chosen) info[k]!.family};

  // 1. Every genre takes its turn, biggest first.
  chosen.add(bySize[week % bySize.length]);

  // 2. One from another family, on its own rotation.
  final away = [
    for (final k in bySize)
      if (!familiesChosen().contains(info[k]!.family)) k,
  ];
  if (away.isNotEmpty && chosen.length < count) {
    chosen.add(away[(week * 3 + 1) % away.length]);
  }

  // 3. The least played for its size, not already chosen.
  double share(String k) {
    final ts = members[k]!;
    var n = 0;
    for (final t in ts) {
      n += plays[t.sha] ?? 0;
    }
    return n / ts.length;
  }

  // A third family where there is one, so the three lanes sound different.
  final used = familiesChosen();
  final left = [
    for (final k in candidates)
      if (!chosen.contains(k)) k,
  ];
  final elsewhere = [
    for (final k in left)
      if (!used.contains(info[k]!.family)) k,
  ];
  final quiet = (elsewhere.isNotEmpty ? elsewhere : left)
    ..sort((a, b) => share(a).compareTo(share(b)));
  if (quiet.isNotEmpty && chosen.length < count) {
    // Among the five quietest, rotate, so the slot does not get stuck too.
    final pool = quiet.take(5).toList();
    final pick = pool[week % pool.length];
    chosen.add(pick);
    discoveryKeys.add(pick);
  }

  // Fill to [count] from what is left, largest first, if a slot was empty.
  for (final k in bySize) {
    if (chosen.length >= count) break;
    if (!chosen.contains(k)) chosen.add(k);
  }

  return [
    for (final k in chosen)
      GenreLane(
        name: info[k]!.name,
        family: info[k]!.family,
        tracks: members[k]!,
        discovery: discoveryKeys.contains(k),
      ),
  ];
}

/// Weeks since 2020-01-06 (a Monday), so a lane holds all week.
int _weekOf(DateTime now) =>
    DateTime.utc(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime.utc(2020, 1, 6)).inDays ~/
    7;
