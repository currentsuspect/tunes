import 'manifest.dart';

/// One "follow the thread" rail: music adjacent to an act the listener
/// actually plays, through the guest graph rather than the artist page.
///
/// Two rails per act at most: the room around them (tracks they guested on,
/// tracks where they hosted a guest) and their own unplayed deep cuts. Both
/// come only from the library and the play counts -- no producers, no
/// labels, no external graph. When that substrate exists it slots in beside
/// these, per docs/RADIO.md §7.
class ThreadRail {
  const ThreadRail({
    required this.act,
    required this.title,
    required this.subtitle,
    required this.tracks,
  });

  /// The seed act, for keys and taps.
  final String act;
  final String title;
  final String subtitle;
  final List<ManifestTrack> tracks;
}

/// Builds thread rails for the acts with the most completed plays.
///
/// Falls back to ownership (track count) when nothing has been played yet,
/// so the section works from the first day. Acts with fewer than [minTracks]
/// tracks of material get no rail rather than a stub.
List<ThreadRail> followThreads({
  required List<ManifestTrack> library,
  required Map<String, int> plays,
  int maxRails = 3,
  int perRail = 10,
  int minTracks = 3,
}) {
  if (library.isEmpty) return [];
  final counts = <String, int>{};
  for (final t in library) {
    counts[t.artistKey] = (counts[t.artistKey] ?? 0) + 1;
  }
  final acts = counts.keys.toList()
    ..sort((a, b) {
      final byPlays = (plays[b] ?? 0).compareTo(plays[a] ?? 0);
      if (byPlays != 0) return byPlays;
      final byCount = counts[b]!.compareTo(counts[a]!);
      if (byCount != 0) return byCount;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });

  int playsOf(ManifestTrack t) => plays[t.sha] ?? 0;

  final rails = <ThreadRail>[];
  for (final act in acts) {
    if (rails.length >= maxRails * 2) break;
    final key = act.toLowerCase();
    // The room: guest spots in either direction. Unplayed first -- a thread
    // to something already on heavy rotation is not discovery.
    final room =
        library
            .where(
              (t) =>
                  t.artistKey.toLowerCase() != key &&
                  (t.featured.any((g) => g.toLowerCase() == key)),
            )
            .toList()
          ..sort((a, b) {
            final byPlays = playsOf(a).compareTo(playsOf(b));
            if (byPlays != 0) return byPlays;
            return a.title.toLowerCase().compareTo(b.title.toLowerCase());
          });
    // Plus the seed act's own collaborations: their tracks hosting guests.
    final hosted =
        library
            .where(
              (t) => t.artistKey.toLowerCase() == key && t.featured.isNotEmpty,
            )
            .toList()
          ..sort((a, b) {
            final byPlays = playsOf(a).compareTo(playsOf(b));
            if (byPlays != 0) return byPlays;
            return a.title.toLowerCase().compareTo(b.title.toLowerCase());
          });
    final together = [...room, ...hosted].take(perRail).toList();
    if (together.length >= minTracks) {
      rails.add(
        ThreadRail(
          act: act,
          title: 'With $act in the room',
          subtitle: 'Guest spots and collaborations',
          tracks: together,
        ),
      );
    }
    if (rails.length >= maxRails * 2) break;
    // Deep cuts: their own tracks, never properly played, newest first.
    final cuts =
        library
            .where((t) => t.artistKey.toLowerCase() == key && playsOf(t) == 0)
            .toList()
          ..sort((a, b) {
            final aa = a.addedAt, bb = b.addedAt;
            if (aa != null && bb != null) {
              final byAdded = bb.compareTo(aa);
              if (byAdded != 0) return byAdded;
            }
            return a.title.toLowerCase().compareTo(b.title.toLowerCase());
          });
    if (cuts.length >= minTracks) {
      rails.add(
        ThreadRail(
          act: act,
          title: '$act, deep cuts',
          subtitle: 'Theirs, unplayed',
          tracks: cuts.take(perRail).toList(),
        ),
      );
    }
  }
  return rails.take(maxRails * 2).toList();
}
