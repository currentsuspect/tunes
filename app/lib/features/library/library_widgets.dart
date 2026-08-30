import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/download_store.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/tokens.dart'
    show Tones, TypeScale, Space, RadiusTokens;
import '../../domain/manifest.dart';
import '../../core/ui/generated_artwork.dart';
import '../../core/ui/track_actions_sheet.dart';

class TrackRow extends StatelessWidget {
  const TrackRow({
    super.key,
    required this.track,
    required this.onTap,
    required this.player,
    required this.store,
    required this.downloading,
    required this.onDownload,
    required this.offline,
    required this.artUrlFor,
    this.onPlayNext,
    this.onAddToQueue,
    this.onEdit,
  });

  final ManifestTrack track;
  final VoidCallback onTap;
  final TunePlayer player;
  final DownloadStore store;
  final bool downloading;
  final VoidCallback onDownload;
  final bool offline;
  final String Function(String sha) artUrlFor;
  final Future<void> Function()? onPlayNext;
  final Future<void> Function()? onAddToQueue;
  final Future<void> Function({
    String? title,
    String? artist,
    String? album,
    String? year,
  })?
  onEdit;

  bool get _hasActions =>
      onPlayNext != null && onAddToQueue != null && onEdit != null;

  @override
  Widget build(BuildContext context) {
    final local = store.pathFor(track.sha) != null;
    final dimmed = offline && !local;
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final active = player.current?.sha == track.sha;
        final titleColor = active ? Tones.primary : null;
        return Opacity(
          opacity: dimmed ? 0.45 : 1,
          child: IgnorePointer(
            ignoring: dimmed,
            child: InkWell(
              onTap: onTap,
              onLongPress: _hasActions
                  ? () => TrackActionsSheet.show(
                      context,
                      track: track,
                      onPlayNext: onPlayNext!,
                      onAddToQueue: onAddToQueue!,
                      onEdit: onEdit!,
                    )
                  : null,
              borderRadius: BorderRadius.circular(RadiusTokens.control),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: Space.sm,
                  horizontal: Space.xs,
                ),
                child: Row(
                  children: [
                    ArtThumb(
                      sha: track.artSha,
                      artUrlFor: artUrlFor,
                      title: track.title,
                      artist: track.artist,
                    ),
                    if (active && player.playing) ...[
                      const SizedBox(width: Space.sm),
                      const Icon(
                        Icons.graphic_eq_rounded,
                        size: 16,
                        color: Tones.primary,
                      ),
                    ],
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            style: TypeScale.title.copyWith(color: titleColor),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${track.artist} — ${track.album}',
                            style: TypeScale.body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Space.md),
                    QualityBadge(label: track.qualityLabel),
                    const SizedBox(width: Space.md),
                    Text(
                      track.durationLabel,
                      style: TypeScale.caption.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    ListenableBuilder(
                      listenable: store,
                      builder: (context, _) {
                        if (downloading) {
                          return const Padding(
                            padding: EdgeInsets.all(Space.sm),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Tones.primary,
                              ),
                            ),
                          );
                        }
                        final dl = store.pathFor(track.sha) != null;
                        return IconButton(
                          onPressed: dl || offline ? null : onDownload,
                          icon: Icon(
                            dl
                                ? Icons.offline_pin_rounded
                                : Icons.download_rounded,
                            color: dl ? Tones.primary : Tones.textMuted,
                            size: 20,
                          ),
                          tooltip: dl
                              ? 'Downloaded — offline ready'
                              : 'Download to device',
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class QualityBadge extends StatelessWidget {
  const QualityBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 3),
      decoration: BoxDecoration(
        color: Tones.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TypeScale.caption),
    );
  }
}

class ArtThumb extends StatelessWidget {
  const ArtThumb({
    super.key,
    required this.sha,
    required this.artUrlFor,
    this.size = 40,
    this.title = '',
    this.artist = '',
    this.borderRadius = 8,
  });

  final String? sha;
  final String Function(String sha) artUrlFor;
  final double size;
  final String title;
  final String artist;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    if (sha != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.network(
          artUrlFor(sha!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => GeneratedArtwork(
            title: title,
            artist: artist,
            size: size,
            borderRadius: borderRadius,
          ),
        ),
      );
    }
    if (title.isNotEmpty || artist.isNotEmpty) {
      return GeneratedArtwork(
        title: title,
        artist: artist,
        size: size,
        borderRadius: borderRadius,
      );
    }
    return const ArtPlaceholder();
  }
}

class ArtPlaceholder extends StatelessWidget {
  const ArtPlaceholder({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      color: Tones.surfaceRaised,
      child: Icon(
        Icons.music_note_rounded,
        size: size * 0.45,
        color: Tones.textMuted,
      ),
    );
  }
}
