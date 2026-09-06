import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/ui/missing_cover.dart';
import '../../domain/collection_gaps.dart';

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
    required this.offline,
    required this.artUrlFor,
    required this.onArtistTap,
    required this.hasHistory,
  });

  final List<ArtistGap> gaps;
  final bool offline;
  final String Function(String sha) artUrlFor;
  final void Function(String artist) onArtistTap;

  /// Whether anything has been listened to yet. Changes what the ranking is
  /// honestly described as, since with no history it is ordered by ownership.
  final bool hasHistory;

  @override
  Widget build(BuildContext context) {
    if (gaps.isEmpty) return _Empty(offline: offline);
    final releases = gaps.fold<int>(0, (a, g) => a + g.missing.length);
    return ListView(
      padding: const EdgeInsets.only(bottom: Space.xl),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Complete your collection', style: TypeScale.title),
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
        for (final gap in gaps)
          _ArtistSection(
            gap: gap,
            artUrlFor: artUrlFor,
            onArtistTap: onArtistTap,
          ),
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
                  child: InkWell(
                    onTap: () => onArtistTap(album.artist),
                    borderRadius: BorderRadius.circular(RadiusTokens.card),
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

class _Empty extends StatelessWidget {
  const _Empty({required this.offline});

  final bool offline;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              offline ? Icons.cloud_off_rounded : Icons.travel_explore_rounded,
              size: 48,
              color: Tones.textMuted,
            ),
            const SizedBox(height: Space.md),
            Text(
              offline ? 'Nothing to compare against' : 'Nothing missing yet',
              style: TypeScale.title,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.sm),
            Text(
              offline
                  ? 'Suggestions come from the daemon, which is not reachable '
                        'right now.'
                  : 'This fills in as the daemon works through your artists. '
                        'It only lists records by acts it could confirm, so a '
                        'new library takes a cycle or two to say anything.',
              style: TypeScale.caption.copyWith(height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
