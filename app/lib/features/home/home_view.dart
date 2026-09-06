import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/ui/artwork.dart';
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
    required this.recents,
    required this.missingAlbums,
    required this.onRepeat,
    required this.listenAgain,
    required this.onArtistTap,
    required this.onAlbumTap,
    required this.onPlay,
    required this.artUrlFor,
    required this.onRefresh,
  });

  final TunesManifest manifest;
  final List<ManifestTrack> recents;

  /// Albums by acts already here that are absent entirely. Supplied by the
  /// daemon rather than derived locally, because deciding this needs the
  /// artist discographies, which only the daemon holds.
  final List<MissingRelease> missingAlbums;

  /// The tracks played most, and the ones played properly but not lately.
  /// Both are derived from listening rather than chosen, so both are empty
  /// until there is enough history to mean anything -- and empty means the
  /// section is absent, not a rail with two covers in it.
  final List<ManifestTrack> onRepeat;
  final List<ManifestTrack> listenAgain;
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
      return _Refreshable(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
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
        ),
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
    final fresh = releases.where((r) => r.year == '${now.year}').toList()
      ..sort((a, b) => (b.year ?? '').compareTo(a.year ?? ''));

    return _Refreshable(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: Space.lg),
        children: [
          // Stats summary — full-bleed caption, padded.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              _sectionPadding,
              Space.md,
              _sectionPadding,
              0,
            ),
            child: Text(
              '${tracks.length} ${tracks.length == 1 ? 'track' : 'tracks'} · '
              '${artists.length} ${artists.length == 1 ? 'artist' : 'artists'} · '
              '${releases.length} ${releases.length == 1 ? 'release' : 'releases'}',
              style: TypeScale.caption,
            ),
          ),
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
              subtitle: 'What you keep going back to',
              tracks: onRepeat,
              onPlay: onPlay,
              artUrlFor: artUrlFor,
              sectionPadding: _sectionPadding,
              peek: _carouselPeek,
            ),
          if (listenAgain.isNotEmpty)
            _DynamicRail(
              title: 'Listen again',
              subtitle: 'Played properly once, not lately',
              tracks: listenAgain,
              onPlay: onPlay,
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
              manifest: manifest,
              onAlbumTap: onAlbumTap,
              artUrlFor: artUrlFor,
              sectionPadding: _sectionPadding,
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
          if (recents.isNotEmpty)
            _RecentlyPlayed(
              recents: recents,
              onPlay: onPlay,
              artUrlFor: artUrlFor,
              sectionPadding: _sectionPadding,
            ),
        ],
      ),
    );
  }
}

/// Pull to refresh, in the app's own colours.
///
/// Always scrollable, so the gesture works even when the content is shorter
/// than the screen -- a feed you cannot pull because it happens to be short
/// is a feed whose refresh is a coin toss.
class _Refreshable extends StatelessWidget {
  const _Refreshable({required this.onRefresh, required this.child});

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: Tones.primary,
      backgroundColor: Tones.surfaceRaised,
      displacement: 28,
      strokeWidth: 2.5,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: child,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {required this.padding});
  final String title;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(padding, Space.lg, padding, Space.sm),
      child: Text(title, style: TypeScale.title),
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
        Padding(
          padding: EdgeInsets.fromLTRB(
            sectionPadding,
            Space.lg,
            Space.sm,
            Space.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TypeScale.title),
                    Text(subtitle, style: TypeScale.caption),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => onPlay(tracks, 0),
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('Play'),
              ),
            ],
          ),
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
                child: InkWell(
                  onTap: () => onPlay(tracks, i),
                  borderRadius: BorderRadius.circular(RadiusTokens.card),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 132,
                        height: 132,
                        child: Artwork(
                          url: t.artSha == null ? null : artUrlFor(t.artSha!),
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
                        style: TypeScale.body,
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
        _SectionHeader('Just added', padding: sectionPadding),
        SizedBox(
          height: 156,
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
                child: InkWell(
                  onTap: () => onPlay([t], 0),
                  borderRadius: BorderRadius.circular(RadiusTokens.card),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Artwork(
                        url: t.artSha == null ? null : artUrlFor(t.artSha!),
                        size: 132,
                        height: 100,
                        fallback: GeneratedArtwork(
                          title: t.title,
                          artist: t.artistDisplay,
                          size: 100,
                          borderRadius: RadiusTokens.card,
                        ),
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        t.title,
                        style: TypeScale.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _addedAgo(t.addedAt!, now),
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
        _SectionHeader('Missing from your collection', padding: sectionPadding),
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
                child: InkWell(
                  // Tapping goes to the artist, which is the only place we can
                  // actually say anything more about a record we do not have.
                  onTap: () => onArtistTap(a.artist),
                  borderRadius: BorderRadius.circular(RadiusTokens.card),
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
                        style: TypeScale.body,
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
        _SectionHeader('Finish these albums', padding: sectionPadding),
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
                            '${r.artist} · ${r.trackShas.length}/${r.totalTracks} · '
                            '${(r.totalTracks ?? 0) - r.trackShas.length} missing',
                            style: TypeScale.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
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
    required this.manifest,
    required this.onAlbumTap,
    required this.artUrlFor,
    required this.sectionPadding,
  });

  final List<ManifestRelease> releases;
  final TunesManifest manifest;
  final void Function(ManifestRelease) onAlbumTap;
  final String Function(String sha) artUrlFor;
  final double sectionPadding;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('Released this year', padding: sectionPadding),
        for (final r in releases.take(5))
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
                      size: 40,
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
                            style: TypeScale.body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          _CompletionBar(release: r),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CompletionBar extends StatelessWidget {
  const _CompletionBar({required this.release});
  final ManifestRelease release;

  @override
  Widget build(BuildContext context) {
    final total = release.totalTracks;
    final have = release.trackShas.length;

    // A full-width unlabelled bar under every row reads as a rendering
    // artifact, and on a complete album it says nothing: a bar at 100% and a
    // bar at "we don't know the length" look identical. Say something only
    // when there is something to say — an album you are missing tracks from.
    if (total == null || total <= 0 || have >= total) {
      return const SizedBox.shrink();
    }

    final ratio = ((have / total).clamp(0.0, 1.0)).toDouble();
    return Padding(
      padding: const EdgeInsets.only(top: Space.xs),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 3,
                child: Stack(
                  children: [
                    Container(color: Tones.surfaceRaised),
                    FractionallySizedBox(
                      widthFactor: ratio,
                      child: Container(color: Tones.primary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: Space.sm),
          Text('$have/$total', style: TypeScale.caption),
        ],
      ),
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
        _SectionHeader('Artists', padding: sectionPadding),
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
        _SectionHeader('Albums', padding: sectionPadding),
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
                child: InkWell(
                  onTap: () => onAlbumTap(r),
                  borderRadius: BorderRadius.circular(RadiusTokens.card),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Artwork(
                        url: r.artSha == null ? null : artUrlFor(r.artSha!),
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
                        style: TypeScale.body,
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

class _RecentlyPlayed extends StatelessWidget {
  const _RecentlyPlayed({
    required this.recents,
    required this.onPlay,
    required this.artUrlFor,
    required this.sectionPadding,
  });

  final List<ManifestTrack> recents;
  final void Function(List<ManifestTrack>, int) onPlay;
  final String Function(String sha) artUrlFor;
  final double sectionPadding;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('Recently played', padding: sectionPadding),
        for (final t in recents.take(5))
          Padding(
            padding: EdgeInsets.symmetric(horizontal: sectionPadding),
            child: InkWell(
              onTap: () => onPlay(recents, recents.indexOf(t)),
              borderRadius: BorderRadius.circular(RadiusTokens.control),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: Space.sm,
                  horizontal: Space.xs,
                ),
                child: Row(
                  children: [
                    ArtThumb(
                      sha: t.artSha,
                      artUrlFor: artUrlFor,
                      title: t.title,
                      artist: t.artistDisplay,
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.title,
                            style: TypeScale.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            t.artistDisplay,
                            style: TypeScale.body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
