import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/ui/artwork.dart';
import '../../core/ui/empty_state.dart';
import '../../core/ui/generated_artwork.dart';
import '../../core/ui/missing_cover.dart';
import '../../core/ui/initials.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/radio_modes.dart';
import '../../core/ui/shelf_widgets.dart';
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
        _Hero(threads: threads.length, records: releases),
        const _ReachDial(),
        if (threads.isNotEmpty) ...[
          const SectionHeader(
            'Follow the thread',
            padding: Space.lg,
            note:
                'Guest spots and deep cuts around the acts you play. Built '
                'from your library and your listening, nothing else.',
          ),
          for (final rail in threads)
            _ThreadRail(rail: rail, artUrlFor: artUrlFor, onPlay: onPlay),
          const SizedBox(height: Space.md),
        ],
        if (gaps.isNotEmpty) ...[
          SectionHeader(
            'Complete your collection',
            padding: Space.lg,
            note:
                '$releases ${releases == 1 ? 'release' : 'releases'} by '
                '${gaps.length} ${gaps.length == 1 ? 'artist' : 'artists'} you '
                'already have. '
                '${hasHistory ? 'Ordered by what you actually play.' : 'Ordered by what you own most of, until there is listening to go on.'}',
          ),
        ],
        for (final gap in gaps)
          _ArtistSection(
            gap: gap,
            artUrlFor: artUrlFor,
            onArtistTap: onArtistTap,
          ),
        if (gaps.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, 0),
            child: Text(
              'Only artists whose catalogue could be confirmed against something '
              'you already own appear here. Asking for a common name returns the '
              'wrong act often enough that guessing would be worse than a short '
              'list.',
              style: TypeScale.note.copyWith(
                fontSize: 13,
                color: Tones.textMuted,
              ),
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
/// What this page is for, and how much there is, before any of it.
class _Hero extends StatelessWidget {
  const _Hero({required this.threads, required this.records});

  final int threads;
  final int records;

  @override
  Widget build(BuildContext context) {
    final facts = [
      if (threads > 0) '$threads ${threads == 1 ? 'thread' : 'threads'}',
      if (records > 0)
        '$records ${records == 1 ? 'record' : 'records'} to find',
    ].join('  ·  ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Discover', style: TypeScale.display.copyWith(fontSize: 34)),
          const SizedBox(height: Space.xs),
          Text(
            'What is already yours that you have not found yet, and what is '
            'missing from the artists you love.',
            style: TypeScale.note.copyWith(
              fontSize: 15,
              color: Tones.textMuted,
            ),
          ),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            Text(facts, style: TypeScale.mono),
          ],
        ],
      ),
    );
  }
}

/// A dashed rounded outline around [child], for something that is not here yet.
class _Ghost extends StatelessWidget {
  const _Ghost({required this.size, required this.child});

  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: const _DashedBorder(),
      child: SizedBox(width: size, height: size, child: child),
    );
  }
}

class _DashedBorder extends CustomPainter {
  const _DashedBorder();

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(RadiusTokens.card),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Tones.textMuted.withValues(alpha: 0.55);
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => false;
}

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
        SectionHeader(
          rail.title,
          padding: Space.lg,
          note: rail.subtitle,
          trailing: PlayPill(onTap: () => onPlay(rail.tracks, 0)),
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
                      PressTarget(
                        child: SizedBox(
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
                  InitialsAvatar(name: gap.artist, size: 44),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          gap.artist,
                          style: TypeScale.display.copyWith(fontSize: 20),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(_subtitle(), style: TypeScale.mono),
                      ],
                    ),
                  ),
                  // Absent rather than empty when the catalogue is unknown: a
                  // ring at zero would claim the library holds none of this act.
                  if (gap.ownedReleases != null &&
                      gap.totalReleases != null) ...[
                    const SizedBox(width: Space.sm),
                    ProgressRing(
                      have: gap.ownedReleases!,
                      total: gap.totalReleases!,
                    ),
                  ],
                  const SizedBox(width: Space.xs),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Tones.textMuted,
                    size: 20,
                  ),
                ],
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
                        // A dashed outline and a dimmer sleeve: a place on the shelf
                        // that is empty, not a picture that failed to load.
                        PressTarget(
                          child: _Ghost(
                            size: 140,
                            child: Opacity(
                              opacity: 0.7,
                              child: MissingCover(
                                album: album,
                                artUrlFor: artUrlFor,
                                size: 140,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: Space.xs),
                        Text(
                          album.title,
                          style: cardTitleStyle(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          [
                            if (album.type != null) album.type!,
                            if (album.year != null) album.year!,
                          ].join('  ·  '),
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
      ),
    );
  }
}

/// The radio's modes, the same ones the queue shows: what plays when the
/// queue runs out. Replaced the old familiar-to-further-out dial (17 Oct).
class _ReachDial extends StatelessWidget {
  const _ReachDial();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.sm,
        Space.lg,
        Space.md,
      ),
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          color: Tones.surface,
          borderRadius: BorderRadius.circular(RadiusTokens.card),
          border: Border.all(color: Tones.hairline),
        ),
        child: const RadioModes(),
      ),
    );
  }
}
