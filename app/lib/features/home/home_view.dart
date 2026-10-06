import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/ui/shelf_widgets.dart';
import '../../core/ui/tunes_refresh.dart';
import '../../domain/mixes.dart';
import '../mixes/mix_page.dart';
import '../../core/ui/artwork.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/generated_artwork.dart';
import '../../core/ui/initials.dart';
import '../../core/ui/missing_cover.dart';
import '../../domain/discography.dart';
import '../../domain/manifest.dart';
import '../library/library_widgets.dart';

class HomeView extends StatelessWidget {
  const HomeView({
    super.key,
    required this.manifest,
    required this.missingAlbums,
    required this.onRepeat,
    required this.listenAgain,
    this.mixes = const [],
    this.unheard = const [],
    required this.onMixTap,
    required this.onArtistTap,
    required this.onAlbumTap,
    required this.onPlay,
    required this.artUrlFor,
    required this.onRefresh,
    this.aboveFeed,
  });

  /// Shown before everything else when there is something to say about right
  /// now, such as music playing on another device. Null draws nothing.
  final Widget? aboveFeed;

  final TunesManifest manifest;

  /// Albums by acts already here that are absent entirely. Supplied by the
  /// daemon rather than derived locally, because deciding this needs the
  /// artist discographies, which only the daemon holds.
  final List<MissingRelease> missingAlbums;

  /// What is on loop today, and songs played a while back and not since.
  /// Both are derived from listening rather than chosen, so both are empty
  /// until there is enough history to mean anything -- and empty means the
  /// section is absent, not a rail with two covers in it.
  final List<ManifestTrack> onRepeat;
  final List<ManifestTrack> listenAgain;

  /// Playlists built from how you listen, and records you have never opened.
  /// Both are empty when there is too little to say anything honest, and the
  /// sections are then not drawn at all.
  final List<Mix> mixes;
  final List<UnheardAlbum> unheard;
  final void Function(Mix mix) onMixTap;
  final void Function(String artist) onArtistTap;
  final void Function(ManifestRelease release) onAlbumTap;
  final void Function(List<ManifestTrack> tracks, int index) onPlay;
  final String Function(String sha) artUrlFor;

  /// Pull to refresh. Completes when the sync does, which is what the
  /// indicator waits on -- a refresh that returns immediately and reloads in
  /// the background makes the gesture feel like it did nothing.
  final Future<void> Function() onRefresh;

  // Edge-to-edge: the screen owns the layout. Sections decide whether
  // they need horizontal padding (for legibility) or not (carousels
  // peek at the edge).
  static const double _sectionPadding = Space.lg;
  static const double _carouselPeek = Space.md;

  @override
  Widget build(BuildContext context) {
    final tracks = manifest.tracks;
    if (tracks.isEmpty) {
      // Still pullable: an empty library is the state you most want to be
      // able to retry from, and a screen with nothing on it is the one place
      // a gesture has to be offered rather than discovered.
      return TunesRefreshList(
        onRefresh: onRefresh,
        children: const [
          SizedBox(height: 120),
          Padding(
            padding: EdgeInsets.all(_sectionPadding),
            child: Text(
              'Your library is empty. Music appears here as the daemon '
              'fetches it — pull down to check again.',
              textAlign: TextAlign.center,
              style: TypeScale.body,
            ),
          ),
        ],
      );
    }

    // Group by the act, not the raw credit line. A guest also gets their own
    // entry so tapping them finds the tracks they appear on -- the "Featured
    // on" section will hang off this later.
    final artists = <String, List<ManifestTrack>>{};
    for (final t in tracks) {
      artists.putIfAbsent(t.artistKey, () => []).add(t);
      for (final guest in t.featured) {
        if (guest != t.artistKey) artists.putIfAbsent(guest, () => []).add(t);
      }
    }
    final artistList = artists.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.length.compareTo(a.value.length);
        if (byCount != 0) return byCount;
        return a.key.toLowerCase().compareTo(b.key.toLowerCase());
      });
    final releases = manifest.releases;

    final now = DateTime.now();
    final justAdded = <ManifestTrack>[];
    final cutoff = now.subtract(const Duration(hours: 24));
    for (final t in tracks) {
      if (t.addedAt == null) continue;
      if (t.addedAt!.isAfter(cutoff)) justAdded.add(t);
    }
    final justAddedSorted = [...justAdded]
      ..sort((a, b) => b.addedAt!.compareTo(a.addedAt!));
    final missing =
        releases
            .where(
              (r) =>
                  r.totalTracks != null && r.trackShas.length < r.totalTracks!,
            )
            .toList()
          ..sort(
            (a, b) =>
                ((b.totalTracks ?? 0) - b.trackShas.length) -
                ((a.totalTracks ?? 0) - a.trackShas.length),
          );
    // By the year in the date, not the whole string. The box sends a full date
    // ("2026-09-08") for almost everything, and comparing it to "2026" matched
    // only the handful stored as a bare year, so this list was a stock three
    // that never changed however much new music arrived. ISO dates sort as
    // text, so newest first is a plain comparison.
    final fresh =
        releases.where((r) => (r.year ?? '').startsWith('${now.year}')).toList()
          ..sort((a, b) => (b.year ?? '').compareTo(a.year ?? ''));

    return TunesRefreshList(
      onRefresh: onRefresh,
      padding: const EdgeInsets.only(bottom: Space.lg),
      children: [
        ?aboveFeed,
        if (justAddedSorted.isNotEmpty)
          _JustAddedCarousel(
            tracks: justAddedSorted,
            now: now,
            onPlay: onPlay,
            artUrlFor: artUrlFor,
            sectionPadding: _sectionPadding,
            peek: _carouselPeek,
          ),
        if (onRepeat.isNotEmpty)
          _DynamicRail(
            title: 'On repeat',
            subtitle: 'On loop in the last day',
            tracks: onRepeat,
            onPlay: onPlay,
            artUrlFor: artUrlFor,
            sectionPadding: _sectionPadding,
            peek: _carouselPeek,
          ),
        if (mixes.isNotEmpty)
          _MixesRail(
            mixes: mixes,
            onMixTap: onMixTap,
            artUrlFor: artUrlFor,
            sectionPadding: _sectionPadding,
            peek: _carouselPeek,
          ),
        if (listenAgain.isNotEmpty)
          _DynamicRail(
            title: 'Listen again',
            subtitle: 'Played before, not for a couple of weeks',
            tracks: listenAgain,
            onPlay: onPlay,
            artUrlFor: artUrlFor,
            sectionPadding: _sectionPadding,
            peek: _carouselPeek,
          ),
        if (unheard.isNotEmpty)
          _UnheardRail(
            albums: unheard,
            manifest: manifest,
            onAlbumTap: onAlbumTap,
            artUrlFor: artUrlFor,
            sectionPadding: _sectionPadding,
            peek: _carouselPeek,
          ),
        if (missingAlbums.isNotEmpty)
          _MissingAlbums(
            albums: missingAlbums,
            onArtistTap: onArtistTap,
            artUrlFor: artUrlFor,
            sectionPadding: _sectionPadding,
            peek: _carouselPeek,
          ),
        if (missing.isNotEmpty)
          _MissingList(
            releases: missing,
            onAlbumTap: onAlbumTap,
            artUrlFor: artUrlFor,
            sectionPadding: _sectionPadding,
          ),
        if (fresh.isNotEmpty)
          _ReleasedThisYear(
            releases: fresh,
            onAlbumTap: onAlbumTap,
            artUrlFor: artUrlFor,
            sectionPadding: _sectionPadding,
            peek: _carouselPeek,
          ),
        if (artistList.isNotEmpty)
          _ArtistsRail(
            artistList: artistList,
            manifest: manifest,
            onArtistTap: onArtistTap,
            artUrlFor: artUrlFor,
            sectionPadding: _sectionPadding,
            peek: _carouselPeek,
          ),
        if (releases.isNotEmpty)
          _AlbumsRail(
            releases: releases,
            onAlbumTap: onAlbumTap,
            artUrlFor: artUrlFor,
            sectionPadding: _sectionPadding,
            peek: _carouselPeek,
          ),
      ],
    );
  }
}

/// A rail the app assembled rather than the listener: on repeat, listen
/// again, and whatever comes after them.
///
/// Playable as a whole, which is the difference between a list and a
/// playlist. Tapping one track plays the rail from there, so the rest of what
/// was suggested follows on instead of the queue ending after one song.
class _DynamicRail extends StatelessWidget {
  const _DynamicRail({
    required this.title,
    required this.subtitle,
    required this.tracks,
    required this.onPlay,
    required this.artUrlFor,
    required this.sectionPadding,
    required this.peek,
  });

  final String title;
  final String subtitle;
  final List<ManifestTrack> tracks;
  final void Function(List<ManifestTrack>, int) onPlay;
  final String Function(String sha) artUrlFor;
  final double sectionPadding;
  final double peek;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title,
          padding: sectionPadding,
          note: subtitle,
          trailing: PlayPill(onTap: () => onPlay(tracks, 0)),
        ),
        SizedBox(
          height: 176,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(peek, 0, sectionPadding, 0),
            itemCount: tracks.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.md),
            itemBuilder: (context, i) {
              final t = tracks[i];
              return SizedBox(
                width: 132,
                child: Pressable(
                  onTap: () => onPlay(tracks, i),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 132,
                        height: 132,
                        child: Artwork(
                          url: t.artSha == null ? null : artUrlFor(t.artSha!),
                          artSha: t.artSha,
                          size: 132,
                          fallback: GeneratedArtwork.fromTrack(
                            t,
                            size: 132,
                            borderRadius: RadiusTokens.card,
                          ),
                        ),
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        t.title,
                        style: cardTitleStyle(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        t.artistDisplay,
                        style: TypeScale.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Playlists the app built for you, as a rail of covers.
class _MixesRail extends StatelessWidget {
  const _MixesRail({
    required this.mixes,
    required this.onMixTap,
    required this.artUrlFor,
    required this.sectionPadding,
    required this.peek,
  });

  final List<Mix> mixes;
  final void Function(Mix) onMixTap;
  final String Function(String sha) artUrlFor;
  final double sectionPadding;
  final double peek;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Made for you',
          padding: sectionPadding,
          note: 'Built from how you listen',
        ),
        SizedBox(
          height: 206,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(peek, 0, sectionPadding, 0),
            itemCount: mixes.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.md),
            itemBuilder: (context, i) {
              final m = mixes[i];
              final covers = <String>[];
              for (final t in m.tracks) {
                final a = t.artSha;
                if (a != null && !covers.contains(a)) covers.add(a);
                if (covers.length == 4) break;
              }
              return SizedBox(
                width: 140,
                child: Pressable(
                  onTap: () => onMixTap(m),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MixMosaic(
                        name: m.title,
                        covers: covers,
                        tint: Tones.primary,
                        artUrlFor: artUrlFor,
                        side: 140,
                      ),
                      const SizedBox(height: Space.sm),
                      Text(
                        m.title,
                        style: cardTitleStyle(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text('${m.tracks.length} songs', style: TypeScale.mono),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Records in your library that nobody has opened.
class _UnheardRail extends StatelessWidget {
  const _UnheardRail({
    required this.albums,
    required this.manifest,
    required this.onAlbumTap,
    required this.artUrlFor,
    required this.sectionPadding,
    required this.peek,
  });

  final List<UnheardAlbum> albums;
  final TunesManifest manifest;
  final void Function(ManifestRelease) onAlbumTap;
  final String Function(String sha) artUrlFor;
  final double sectionPadding;
  final double peek;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Unheard in your library',
          padding: sectionPadding,
          note: 'Records you have, and have never played',
        ),
        SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(peek, 0, sectionPadding, 0),
            itemCount: albums.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.md),
            itemBuilder: (context, i) {
              final a = albums[i];
              final r = a.release;
              return SizedBox(
                width: 132,
                child: Pressable(
                  onTap: () => onAlbumTap(r),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Artwork(
                        url: r.artSha == null ? null : artUrlFor(r.artSha!),
                        artSha: r.artSha,
                        size: 132,
                        fallback: GeneratedArtwork(
                          title: r.title,
                          artist: r.artist,
                          size: 132,
                          borderRadius: RadiusTokens.card,
                        ),
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        r.title,
                        style: cardTitleStyle(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        r.artist,
                        style: TypeScale.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        a.why,
                        style: TypeScale.mono.copyWith(fontSize: 10),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Horizontal carousel of "just added" tracks. Edges peek so the user
/// can tell it's scrollable.
class _JustAddedCarousel extends StatelessWidget {
  const _JustAddedCarousel({
    required this.tracks,
    required this.now,
    required this.onPlay,
    required this.artUrlFor,
    required this.sectionPadding,
    required this.peek,
  });

  final List<ManifestTrack> tracks;
  final DateTime now;
  final void Function(List<ManifestTrack>, int) onPlay;
  final String Function(String sha) artUrlFor;
  final double sectionPadding;
  final double peek;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Just added',
          padding: sectionPadding,
          note: 'In the last day',
        ),
        SizedBox(
          height: 176,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // Leading edge shows a small peek of the next item; trailing
            // edge respects the section padding so the last card aligns
            // with the rest of the page.
            padding: EdgeInsets.fromLTRB(peek, 0, sectionPadding, 0),
            itemCount: tracks.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.md),
            itemBuilder: (context, i) {
              final t = tracks[i];
              return SizedBox(
                width: 132,
                child: Pressable(
                  onTap: () => onPlay([t], 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Artwork(
                        url: t.artSha == null ? null : artUrlFor(t.artSha!),
                        artSha: t.artSha,
                        size: 132,
                        // Square, like every other sleeve on this page. It was
                        // cropped to a letterbox here, so the same record
                        // looked different in this rail than anywhere else.
                        fallback: GeneratedArtwork(
                          title: t.title,
                          artist: t.artistDisplay,
                          size: 132,
                          borderRadius: RadiusTokens.card,
                        ),
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        t.title,
                        style: cardTitleStyle(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _addedAgo(t.addedAt!, now),
                        style: TypeScale.mono,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _addedAgo(DateTime addedAt, DateTime now) {
    final diff = now.difference(addedAt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

/// Albums by acts already in the library that are absent entirely.
///
/// There is no artwork to show — we do not have the release — so every card
/// uses the generated cover. That is honest: a placeholder that looked like
/// real art would imply we hold something we do not.
class _MissingAlbums extends StatelessWidget {
  const _MissingAlbums({
    required this.albums,
    required this.onArtistTap,
    required this.artUrlFor,
    required this.sectionPadding,
    required this.peek,
  });

  final List<MissingRelease> albums;
  final void Function(String artist) onArtistTap;
  final String Function(String sha) artUrlFor;
  final double sectionPadding;
  final double peek;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Missing from your collection',
          padding: sectionPadding,
          note: 'Records by artists you already have',
        ),
        SizedBox(
          height: 176,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(peek, 0, sectionPadding, 0),
            itemCount: albums.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.md),
            itemBuilder: (context, i) {
              final a = albums[i];
              return SizedBox(
                width: 132,
                child: Pressable(
                  // Tapping goes to the artist, which is the only place we can
                  // actually say anything more about a record we do not have.
                  onTap: () => onArtistTap(a.artist),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Opacity(
                        // Reads as "not here yet" beside the fully-opaque
                        // covers of everything the library actually holds.
                        opacity: 0.72,
                        child: MissingCover(album: a, artUrlFor: artUrlFor),
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        a.title,
                        style: cardTitleStyle(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        a.year == null ? a.artist : '${a.artist} · ${a.year}',
                        style: TypeScale.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MissingList extends StatelessWidget {
  const _MissingList({
    required this.releases,
    required this.onAlbumTap,
    required this.artUrlFor,
    required this.sectionPadding,
  });

  final List<ManifestRelease> releases;
  final void Function(ManifestRelease) onAlbumTap;
  final String Function(String sha) artUrlFor;
  final double sectionPadding;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Distinct from "Missing from your collection" above: this is an album
        // that is here but incomplete, which is a different thing to do about
        // it. Sharing one heading made a partial album and an absent one look
        // like the same problem.
        SectionHeader(
          'Finish these albums',
          padding: sectionPadding,
          note: 'You have part of each',
        ),
        for (final r in releases.take(4)) ...[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: sectionPadding),
            child: InkWell(
              onTap: () => onAlbumTap(r),
              borderRadius: BorderRadius.circular(RadiusTokens.control),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: Space.sm,
                  horizontal: Space.xs,
                ),
                child: Row(
                  children: [
                    ArtThumb(
                      sha: r.artSha,
                      artUrlFor: artUrlFor,
                      size: 48,
                      title: r.title,
                      artist: r.artist,
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.title,
                            style: TypeScale.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            r.artist,
                            style: TypeScale.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${(r.totalTracks ?? 0) - r.trackShas.length} to go',
                            style: TypeScale.mono.copyWith(color: Tones.warn),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    ProgressRing(
                      have: r.trackShas.length,
                      total: r.totalTracks ?? 0,
                    ),
                    const SizedBox(width: Space.xs),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Tones.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (r != releases.take(4).last)
            const Divider(height: 1, thickness: 0.5, color: Tones.hairline),
        ],
      ],
    );
  }
}

/// "Released this year" — for each release, show a year/artist row with
/// a completion bar showing how many of the release's tracks are in
/// the library. Replaces the unreadable giant-pill version.
class _ReleasedThisYear extends StatelessWidget {
  const _ReleasedThisYear({
    required this.releases,
    required this.onAlbumTap,
    required this.artUrlFor,
    required this.sectionPadding,
    required this.peek,
  });

  final List<ManifestRelease> releases;
  final void Function(ManifestRelease) onAlbumTap;
  final String Function(String sha) artUrlFor;
  final double sectionPadding;
  final double peek;

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

  /// "Sep 8" from "2026-09-08"; just the year when that is all there is.
  static String _when(String? date) {
    final parts = (date ?? '').split('-');
    if (parts.length < 3) return parts.first;
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (m == null || d == null || m < 1 || m > 12) return parts.first;
    return '${_months[m - 1]} $d';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Released this year',
          padding: sectionPadding,
          note: '${releases.length} new in your library, newest first',
        ),
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(peek, 0, sectionPadding, 0),
            itemCount: releases.length > 14 ? 14 : releases.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.md),
            itemBuilder: (context, i) {
              final r = releases[i];
              return SizedBox(
                width: 132,
                child: Pressable(
                  onTap: () => onAlbumTap(r),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Artwork(
                        url: r.artSha == null ? null : artUrlFor(r.artSha!),
                        artSha: r.artSha,
                        size: 132,
                        fallback: GeneratedArtwork(
                          title: r.title,
                          artist: r.artist,
                          size: 132,
                          borderRadius: RadiusTokens.card,
                        ),
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        r.title,
                        style: cardTitleStyle(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        r.artist,
                        style: TypeScale.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(_when(r.year), style: TypeScale.mono),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ArtistsRail extends StatelessWidget {
  const _ArtistsRail({
    required this.artistList,
    required this.manifest,
    required this.onArtistTap,
    required this.artUrlFor,
    required this.sectionPadding,
    required this.peek,
  });

  final List<MapEntry<String, List<ManifestTrack>>> artistList;
  final TunesManifest manifest;
  final void Function(String) onArtistTap;
  final String Function(String sha) artUrlFor;
  final double sectionPadding;
  final double peek;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader('Artists', padding: sectionPadding),
        SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(peek, 0, sectionPadding, 0),
            itemCount: artistList.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.md),
            itemBuilder: (context, i) {
              final e = artistList[i];
              final artSha = manifest.artistArt(e.key);
              return SizedBox(
                width: 76,
                child: InkWell(
                  onTap: () => onArtistTap(e.key),
                  borderRadius: BorderRadius.circular(RadiusTokens.control),
                  child: Column(
                    children: [
                      Artwork(
                        url: artSha == null ? null : artUrlFor(artSha),
                        artSha: artSha,
                        size: 64,
                        borderRadius: 32,
                        fallback: InitialsAvatar(name: e.key, size: 64),
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        e.key,
                        style: TypeScale.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AlbumsRail extends StatelessWidget {
  const _AlbumsRail({
    required this.releases,
    required this.onAlbumTap,
    required this.artUrlFor,
    required this.sectionPadding,
    required this.peek,
  });

  final List<ManifestRelease> releases;
  final void Function(ManifestRelease) onAlbumTap;
  final String Function(String sha) artUrlFor;
  final double sectionPadding;
  final double peek;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader('Albums', padding: sectionPadding),
        SizedBox(
          height: 178,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(peek, 0, sectionPadding, 0),
            itemCount: releases.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.md),
            itemBuilder: (context, i) {
              final r = releases[i];
              return SizedBox(
                width: 130,
                child: Pressable(
                  onTap: () => onAlbumTap(r),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Artwork(
                        url: r.artSha == null ? null : artUrlFor(r.artSha!),
                        artSha: r.artSha,
                        size: 130,
                        fallback: GeneratedArtwork(
                          title: r.title,
                          artist: r.artist,
                          size: 130,
                          borderRadius: RadiusTokens.card,
                        ),
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        r.title,
                        style: cardTitleStyle(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${r.artist} · ${r.trackShas.length} '
                        '${r.trackShas.length == 1 ? 'track' : 'tracks'}',
                        style: TypeScale.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
