import 'discography.dart';
import 'manifest.dart';

/// One act, and what the library is missing of theirs.
///
/// The unit the discover screen is built from: a suggestion on its own is just
/// an album cover, but a suggestion that says "you have five of eighteen of
/// these and you played them forty times" is an argument.
class ArtistGap {
  const ArtistGap({
    required this.artist,
    required this.missing,
    required this.ownedTracks,
    required this.plays,
    required this.ownedReleases,
    required this.totalReleases,
  });

  final String artist;
  final List<MissingRelease> missing;

  /// Tracks by this act already in the library.
  final int ownedTracks;

  /// Times those tracks were actually played through. Zero is common and
  /// honest -- it means owned but not yet listened to, which is a different
  /// thing from disliked.
  final int plays;

  /// Releases held, out of releases that exist. Null together when the daemon
  /// did not report them.
  final int? ownedReleases;
  final int? totalReleases;

  /// How complete the collection is, 0 to 1, or null when unknown.
  ///
  /// Null rather than zero on a missing denominator: an empty progress bar is
  /// a claim, and "we do not know" is not that claim.
  double? get completion {
    final owned = ownedReleases;
    final total = totalReleases;
    if (owned == null || total == null || total <= 0) return null;
    return (owned / total).clamp(0.0, 1.0);
  }
}

/// Plays per act, folded from per-track counts.
///
/// Credited to the primary act rather than the whole credit line, so a guest
/// verse does not make the guest look like someone you listen to. Tracks that
/// were never played simply do not appear.
Map<String, int> playsByArtist(
  Map<String, int> playCountsBySha,
  List<ManifestTrack> tracks,
) {
  final artistOf = <String, String>{for (final t in tracks) t.sha: t.artistKey};
  final out = <String, int>{};
  for (final entry in playCountsBySha.entries) {
    final artist = artistOf[entry.key];
    // A play of a track that has since left the library still happened, but
    // there is no act to credit it to, so it is dropped rather than guessed.
    if (artist == null || artist.isEmpty) continue;
    out[artist] = (out[artist] ?? 0) + entry.value;
  }
  return out;
}

/// Groups missing releases by act, ranked by how much the act is actually
/// listened to.
///
/// Listening first, ownership second. Owning eighty tracks of an act says how
/// a library was assembled; playing them says what to go and find next, and
/// those two answers diverge more often than you would think.
List<ArtistGap> collectionGaps({
  required List<MissingRelease> missing,
  required Map<String, int> plays,
}) {
  final byArtist = <String, List<MissingRelease>>{};
  for (final m in missing) {
    if (m.artist.isEmpty) continue;
    (byArtist[m.artist] ??= []).add(m);
  }

  final gaps = <ArtistGap>[];
  for (final entry in byArtist.entries) {
    final releases = entry.value;
    // Newest first inside an act: the record someone is most likely to be
    // looking for is the one that just came out.
    releases.sort((a, b) {
      final ay = a.year ?? '';
      final by = b.year ?? '';
      final byYear = by.compareTo(ay);
      return byYear != 0 ? byYear : a.title.compareTo(b.title);
    });
    final first = releases.first;
    gaps.add(
      ArtistGap(
        artist: entry.key,
        missing: releases,
        ownedTracks: first.artistTracks,
        plays: plays[entry.key] ?? 0,
        ownedReleases: first.artistOwnedReleases,
        totalReleases: first.artistTotalReleases,
      ),
    );
  }

  gaps.sort((a, b) {
    final byPlays = b.plays.compareTo(a.plays);
    if (byPlays != 0) return byPlays;
    final byOwned = b.ownedTracks.compareTo(a.ownedTracks);
    if (byOwned != 0) return byOwned;
    return a.artist.compareTo(b.artist);
  });
  return gaps;
}
