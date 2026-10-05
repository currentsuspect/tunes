import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/download_store.dart';
import '../../core/data/likes_store.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/tokens.dart'
    show Tones, TypeScale, Space, RadiusTokens;
import '../../domain/manifest.dart';
import '../../core/ui/artwork.dart';
import '../../core/ui/download_button.dart';
import '../../core/ui/generated_artwork.dart';
import '../../core/ui/playing_bars.dart';
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
                      artist: track.artistDisplay,
                    ),
                    // Whenever this is the song that is on, moving while it plays
                    // and standing still while it is paused.
                    if (active) ...[
                      const SizedBox(width: Space.sm),
                      PlayingBars(playing: player.playing),
                    ],
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
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
                            track.artistAlbumLine,
                            style: TypeScale.body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // The title is the thing you read. A fixed-width quality
                    // badge here squeezed it down to about six characters
                    // ("SMUC…", "2SEAT…"); the full quality breakdown already
                    // lives in Now Playing's info panel, where detail belongs.
                    const SizedBox(width: Space.sm),
                    // A mark, not a control. Every row already carries a
                    // download button; a second tap target on each one would
                    // make the list harder to scroll than it is to read.
                    // Liking happens in the player and the long-press menu.
                    if (LikesScope.maybeOf(context)?.isLiked(track.sha) ??
                        false) ...[
                      const Icon(
                        Icons.favorite_rounded,
                        size: 14,
                        color: Tones.primary,
                      ),
                      const SizedBox(width: Space.sm),
                    ],
                    Text(
                      track.durationLabel,
                      style: TypeScale.caption.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    DownloadButton(
                      sha: track.sha,
                      title: track.title,
                      store: store,
                      offline: offline,
                      fallbackActive: downloading,
                      onDownload: onDownload,
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
    // The generated tile is both the stand-in and the failure case: it is
    // derived from the title and artist, so it is never a blank square, and a
    // cover arriving later fades over the top of it.
    final generated = (title.isNotEmpty || artist.isNotEmpty)
        ? GeneratedArtwork(
            title: title,
            artist: artist,
            size: size,
            borderRadius: borderRadius,
          )
        : ArtworkPlaceholder(borderRadius: borderRadius);
    return Artwork(
      url: sha == null ? null : artUrlFor(sha!),
      artSha: sha,
      size: size,
      borderRadius: borderRadius,
      fallback: generated,
    );
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
