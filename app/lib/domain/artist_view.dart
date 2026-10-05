import 'discography.dart';
import 'manifest.dart';

/// Someone who shows up on this artist's songs, or whose songs this artist
/// shows up on.
class ArtistCollaborator {
  const ArtistCollaborator(this.name, this.songs);

  final String name;

  /// Songs the two share.
  final int songs;
}

/// An artist page, already in the order it is read.
///
/// The page used to render the catalogue gaps first and the songs you own last,
/// below however many releases the artist has, so what you could actually play
/// sat at the bottom of a long scroll. This decides the order in one place and
/// stays free of Flutter so it can be tested: what you have, then what you are
/// part-way through, then what you do not have.
class ArtistView {
  const ArtistView({
    required this.artist,
    required this.ownedSongs,
    required this.leadSongCount,
    required this.ownedReleases,
    required this.unfinished,
    required this.absent,
    required this.collaborators,
    required this.catalogueTotal,
    required this.catalogueOwned,
  });

  final String artist;

  /// Every song you have by or featuring this artist: their own first, newest
  /// release first and in track order within it, then the songs where they are
  /// a guest.
  final List<ManifestTrack> ownedSongs;

  /// How many of [ownedSongs] are the artist's own. The rest are features.
  final int leadSongCount;

  final List<ManifestRelease> ownedReleases;

  /// Records you have some of, nearest to finished first.
  final List<DiscographyGroup> unfinished;

  /// Records you have none of, newest first.
  final List<DiscographyGroup> absent;

  final List<ArtistCollaborator> collaborators;

  /// Null until the catalogue has been fetched, or when it is unavailable.
  /// Callers show nothing rather than a figure that was never received.
  final int? catalogueTotal;
  final int? catalogueOwned;

  bool get hasCatalogue => catalogueTotal != null;

  /// 0 to 1, or null when the catalogue is unknown.
  double? get completion {
    final total = catalogueTotal;
    final owned = catalogueOwned;
    if (total == null || owned == null || total == 0) return null;
    return (owned / total).clamp(0.0, 1.0);
  }

  bool get complete => hasCatalogue && unfinished.isEmpty && absent.isEmpty;
}

ArtistView buildArtistView({
  required String artist,
  required TunesManifest manifest,
  ArtistDiscography? discography,
  int maxCollaborators = 16,
}) {
  final mine = <ManifestTrack>[];
  final guest = <ManifestTrack>[];
  for (final t in manifest.tracks) {
    if (t.artistKey == artist) {
      mine.add(t);
    } else if (t.featured.contains(artist)) {
      guest.add(t);
    }
  }
  mine.sort(_inRecordOrder);
  guest.sort(_inRecordOrder);

  final counts = <String, int>{};
  for (final t in mine) {
    for (final f in t.featured) {
      if (f != artist) counts[f] = (counts[f] ?? 0) + 1;
    }
  }
  for (final t in guest) {
    counts[t.artistKey] = (counts[t.artistKey] ?? 0) + 1;
    for (final f in t.featured) {
      if (f != artist) counts[f] = (counts[f] ?? 0) + 1;
    }
  }
  final collaborators =
      [for (final e in counts.entries) ArtistCollaborator(e.key, e.value)]
        ..sort((a, b) {
          final bySongs = b.songs.compareTo(a.songs);
          return bySongs != 0 ? bySongs : a.name.compareTo(b.name);
        });

  final groups = discography?.groups ?? const <DiscographyGroup>[];
  final unfinished =
      [
        for (final g in groups)
          if (g.owned &&
              g.totalTracks != null &&
              g.ownedTracks < g.totalTracks!)
            g,
      ]..sort((a, b) {
        final left = (a.totalTracks! - a.ownedTracks).compareTo(
          b.totalTracks! - b.ownedTracks,
        );
        return left != 0 ? left : _newestFirst(a.year, b.year);
      });
  final absent =
      [
        for (final g in groups)
          if (!g.owned) g,
      ]..sort((a, b) {
        final byYear = _newestFirst(a.year, b.year);
        return byYear != 0 ? byYear : a.title.compareTo(b.title);
      });

  return ArtistView(
    artist: artist,
    ownedSongs: [...mine, ...guest],
    leadSongCount: mine.length,
    ownedReleases: manifest.releasesFor(artist),
    unfinished: unfinished,
    absent: absent,
    collaborators: collaborators.take(maxCollaborators).toList(),
    catalogueTotal: discography != null && groups.isNotEmpty
        ? groups.length
        : null,
    catalogueOwned: discography != null && groups.isNotEmpty
        ? groups.where((g) => g.owned).length
        : null,
  );
}

/// Newest year first; a record with no year goes last.
int _newestFirst(String? a, String? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return b.compareTo(a);
}

int _inRecordOrder(ManifestTrack a, ManifestTrack b) {
  final byYear = _newestFirst(a.year, b.year);
  if (byYear != 0) return byYear;
  final byAlbum = a.album.compareTo(b.album);
  if (byAlbum != 0) return byAlbum;
  final byDisc = (a.discNumber ?? 1).compareTo(b.discNumber ?? 1);
  if (byDisc != 0) return byDisc;
  final byTrack = (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
  if (byTrack != 0) return byTrack;
  return a.title.compareTo(b.title);
}
