import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/ui/artwork.dart';
import '../../core/ui/empty_state.dart';
import '../../core/ui/generated_artwork.dart';
import '../../core/ui/missing_cover.dart';
import '../../core/ui/pressable.dart';
import '../../domain/collection_gaps.dart';
import '../../domain/manifest.dart';
import '../../domain/threads.dart';

/// Where the library stops and the world carries on.
///
/// The first layer of it: the records by acts already here that are not here
/// yet, grouped by act and ranked by what actually gets played. Nothing on
/// this screen can be tapped to acquire anything -- the music comes from
/// elsewhere -- so every card leads to the artist, which is the only place the
/// app can say more about a record it does not hold.
class DiscoverView extends StatelessWidget {
  const DiscoverView({
    super.key,
    required this.gaps,
    required this.threads,
    required this.offline,
    required this.artUrlFor,
    required this.onArtistTap,
    required this.onPlay,
    required this.hasHistory,
  });

  final List<ArtistGap> gaps;

  /// Relationship rails built from the library and the play counts: guest
  /// spots and deep cuts around the acts actually played. Shown above the
  /// gaps -- what you hold comes before what you lack.
  final List<ThreadRail> threads;
  final bool offline;
  final String Function(String sha) artUrlFor;
  final void Function(String artist) onArtistTap;

  /// Plays a rail from the tapped track, so the rest of the suggestion
  /// follows on rather than ending after one song.
  final void Function(List<ManifestTrack> tracks, int index) onPlay;

  /// Whether anything has been listened to yet. Changes what the ranking is
  /// honestly described as, since with no history it is ordered by ownership.
  final bool hasHistory;

  @override
  Widget build(BuildContext context) {
    if (gaps.isEmpty && threads.isEmpty) {
      return EmptyState(
        icon: offline ? Icons.cloud_off_rounded : Icons.travel_explore_rounded,
        title: offline ? 'Nothing to compare against' : 'Nothing missing yet',
        body: offline
            ? 'Suggestions come from the daemon, which is not reachable right '
                  'now. What you already have is all here.'
            : 'This fills in as the daemon works through your artists. It '
                  'only lists records by acts it could confirm, so a new '
                  'library takes a cycle or two to say anything.',
      );
    }
    final releases = gaps.fold<int>(0, (a, g) => a + g.missing.length);
    return ListView(
      padding: const EdgeInsets.only(bottom: Space.xl),
      children: [
        if (threads.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Follow the thread', style: TypeScale.heading),
                SizedBox(height: Space.xs),
                Text(
                  'Guest spots and deep cuts around the acts you actually '
                  'play. Built from your library and your listening, nothing '
                  'else.',
                  style: TypeScale.caption,
                ),
              ],
            ),
          ),
          for (final rail in threads)
            _ThreadRail(rail: rail, artUrlFor: artUrlFor, onPlay: onPlay),
          const SizedBox(height: Space.md),
        ],
        if (gaps.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Complete your collection',
                  style: TypeScale.heading,
                ),
                const SizedBox(height: Space.xs),
                Text(
                  '$releases ${releases == 1 ? 'release' : 'releases'} by '
                  '${gaps.length} ${gaps.length == 1 ? 'artist' : 'artists'} '
                  'already in your library. '
                  '${hasHistory ? 'Ordered by what you actually play.' : 'Ordered by what you own most of, until there is listening to go on.'}',
                  style: TypeScale.caption.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.md),
        ],
        for (final gap in gaps)
          _ArtistSection(
            gap: gap,
            artUrlFor: artUrlFor,
            onArtistTap: onArtistTap,
          ),
        if (gaps.isNotEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, 0),
            child: Text(
              'Only artists whose catalogue could be confirmed against something '
              'you already own appear here. Asking for a common name returns the '
              'wrong act often enough that guessing would be worse than a short '
              'list.',
              style: TypeScale.caption,
            ),
          ),
      ],
    );
  }
}

/// One playable thread rail: a title, a play-all, and a horizontal run of
/// covers. Tapping a track plays the rail from there, so the rest of the
/// suggestion follows on -- a rail that ends after one song is a list, not
/// a discovery.
class _ThreadRail extends StatelessWidget {
  const _ThreadRail({
    required this.rail,
    required this.artUrlFor,
    required this.onPlay,
  });

  final ThreadRail rail;
  final String Function(String sha) artUrlFor;
  final void Function(List<ManifestTrack> tracks, int index) onPlay;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
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
                    Text(rail.title, style: TypeScale.heading),
                    Text(rail.subtitle, style: TypeScale.caption),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => onPlay(rail.tracks, 0),
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
            padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.lg, 0),
            itemCount: rail.tracks.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.md),
            itemBuilder: (context, i) {
              final t = rail.tracks[i];
              return SizedBox(
                width: 132,
                child: Pressable(
                  onTap: () => onPlay(rail.tracks, i),
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

class _ArtistSection extends StatelessWidget {
  const _ArtistSection({
    required this.gap,
    required this.artUrlFor,
    required this.onArtistTap,
  });

  final ArtistGap gap;
  final String Function(String sha) artUrlFor;
  final void Function(String artist) onArtistTap;

  /// The line under the artist name, built only from what is actually known.
  ///
  /// Every clause is dropped rather than defaulted when its number is absent,
  /// so this never reads "0 plays" at someone who simply has no history yet.
  String _subtitle() {
    final parts = <String>[];
    final owned = gap.ownedReleases;
    final total = gap.totalReleases;
    if (owned != null && total != null) {
      parts.add('$owned of $total releases');
    }
    parts.add('${gap.missing.length} missing');
    if (gap.plays > 0) {
      parts.add('${gap.plays} ${gap.plays == 1 ? 'play' : 'plays'}');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final completion = gap.completion;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => onArtistTap(gap.artist),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.sm,
                Space.lg,
                Space.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          gap.artist,
                          style: TypeScale.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(_subtitle(), style: TypeScale.caption),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Tones.textMuted,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          // Absent rather than empty when completion is unknown: a bar at zero
          // would claim the library holds none of this act.
          if (completion != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                0,
                Space.lg,
                Space.sm,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: completion,
                  minHeight: 4,
                  backgroundColor: Tones.surfaceRaised,
                  valueColor: const AlwaysStoppedAnimation(Tones.primary),
                ),
              ),
            ),
          SizedBox(
            height: 190,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              itemCount: gap.missing.length,
              separatorBuilder: (_, _) => const SizedBox(width: Space.md),
              itemBuilder: (context, i) {
                final album = gap.missing[i];
                return SizedBox(
                  width: 140,
                  child: Pressable(
                    onTap: () => onArtistTap(album.artist),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Opacity(
                          // Reads as "not here yet" beside the fully opaque
                          // covers of everything the library does hold.
                          opacity: 0.72,
                          child: MissingCover(
                            album: album,
                            artUrlFor: artUrlFor,
                            size: 140,
                          ),
                        ),
                        const SizedBox(height: Space.xs),
                        Text(
                          album.title,
                          style: TypeScale.body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          [
                            if (album.type != null) album.type!,
                            if (album.year != null) album.year!,
                          ].join(' · '),
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
      ),
    );
  }
}
