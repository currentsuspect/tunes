import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/download_manager.dart';
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
                      artist: track.artistDisplay,
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
                            '${track.artistDisplay} — ${track.album}',
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
                    Text(
                      track.durationLabel,
                      style: TypeScale.caption.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    _DownloadControl(
                      sha: track.sha,
                      title: track.title,
                      store: store,
                      offline: offline,
                      downloading: downloading,
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

/// The per-row download affordance: idle, queued, running with real progress,
/// failed, or downloaded.
///
/// Previously this was a bare spinner with no percentage and no way out — a
/// 20 MB FLAC looked identical to a hang, and a finished download could only
/// be removed from Now Playing.
class _DownloadControl extends StatelessWidget {
  const _DownloadControl({
    required this.sha,
    required this.title,
    required this.store,
    required this.offline,
    required this.downloading,
    required this.onDownload,
  });

  final String sha;
  final String title;
  final DownloadStore store;
  final bool offline;
  final bool downloading;
  final VoidCallback onDownload;

  Future<void> _remove(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final manager = DownloadScope.maybeOf(context);
    await store.remove(sha);
    if (!context.mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Removed $title from downloads'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () =>
              manager == null ? onDownload() : manager.enqueue(sha),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final manager = DownloadScope.maybeOf(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final job = manager?.jobFor(sha);

        if (job != null && job.phase == DownloadPhase.failed) {
          return IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
            padding: EdgeInsets.zero,
            onPressed: () {
              manager?.dismiss(sha);
              onDownload();
            },
            icon: const Icon(
              Icons.refresh_rounded,
              color: Tones.textMuted,
              size: 20,
            ),
            tooltip: 'Download failed — tap to retry',
          );
        }

        final active =
            downloading ||
            (job != null &&
                (job.phase == DownloadPhase.queued ||
                    job.phase == DownloadPhase.running));

        if (active) {
          final progress = job?.progress;
          final queued = job?.phase == DownloadPhase.queued;
          return Tooltip(
            message: queued ? 'Queued — tap to cancel' : 'Tap to cancel',
            child: InkWell(
              onTap: manager == null ? null : () => manager.cancel(sha),
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: queued ? null : progress,
                        color: Tones.primary,
                      ),
                    ),
                    const Icon(
                      Icons.close_rounded,
                      size: 12,
                      color: Tones.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final dl = store.pathFor(sha) != null;
        if (dl) {
          return IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
            padding: EdgeInsets.zero,
            onPressed: () => _remove(context),
            icon: const Icon(
              Icons.offline_pin_rounded,
              color: Tones.primary,
              size: 20,
            ),
            tooltip: 'Downloaded — tap to remove',
          );
        }

        return IconButton(
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          padding: EdgeInsets.zero,
          onPressed: offline ? null : onDownload,
          icon: const Icon(
            Icons.download_rounded,
            color: Tones.textMuted,
            size: 20,
          ),
          tooltip: 'Download to device',
        );
      },
    );
  }
}
