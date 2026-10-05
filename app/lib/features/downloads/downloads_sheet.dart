import 'package:flutter/material.dart';

import '../../core/data/download_manager.dart';
import '../../core/theme/tokens.dart';
import '../../domain/manifest.dart';

/// Everything downloading, queued or failed, with a way out of each.
class DownloadsSheet extends StatelessWidget {
  const DownloadsSheet({
    super.key,
    required this.manager,
    required this.trackFor,
  });

  final DownloadManager manager;

  /// Resolves a sha to what the library calls it; null when it has left.
  final ManifestTrack? Function(String sha) trackFor;

  static Future<void> show(
    BuildContext context, {
    required DownloadManager manager,
    required ManifestTrack? Function(String sha) trackFor,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Tones.base,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(RadiusTokens.card),
        ),
      ),
      builder: (_) => DownloadsSheet(manager: manager, trackFor: trackFor),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scroll) => SafeArea(
        child: ListenableBuilder(
          listenable: manager,
          builder: (context, _) {
            final jobs = manager.jobs.values.toList()
              ..sort((a, b) => a.phase.index.compareTo(b.phase.index));
            // Running first, then waiting, then failed.
            final running = jobs
                .where((j) => j.phase == DownloadPhase.running)
                .toList();
            final queued = jobs
                .where((j) => j.phase == DownloadPhase.queued)
                .toList();
            final failed = jobs
                .where((j) => j.phase == DownloadPhase.failed)
                .toList();
            final ordered = [...running, ...queued, ...failed];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    Space.lg,
                    Space.md,
                    Space.sm,
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('Downloads', style: TypeScale.heading),
                      ),
                      if (manager.activeCount > 0)
                        TextButton(
                          onPressed: manager.cancelAll,
                          child: const Text('Cancel all'),
                        ),
                      if (failed.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            for (final j in failed) {
                              manager.dismiss(j.sha);
                              manager.enqueue(j.sha);
                            }
                          },
                          child: const Text('Retry failed'),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ordered.isEmpty
                      ? Center(
                          child: Text(
                            'Nothing downloading.',
                            style: TypeScale.note.copyWith(
                              fontSize: 15,
                              color: Tones.textMuted,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: scroll,
                          itemCount: ordered.length,
                          itemBuilder: (context, i) => _JobRow(
                            job: ordered[i],
                            track: trackFor(ordered[i].sha),
                            manager: manager,
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _JobRow extends StatelessWidget {
  const _JobRow({
    required this.job,
    required this.track,
    required this.manager,
  });

  final DownloadJob job;
  final ManifestTrack? track;
  final DownloadManager manager;

  @override
  Widget build(BuildContext context) {
    final failed = job.phase == DownloadPhase.failed;
    final running = job.phase == DownloadPhase.running;
    final status = failed
        ? 'Failed'
        : running
        ? (job.progress == null
              ? 'Downloading'
              : '${(job.progress! * 100).round()}%')
        : 'Waiting';
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track?.title ?? 'A track no longer in the library',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TypeScale.title.copyWith(fontSize: 15),
                ),
                Text(
                  track?.artistDisplay ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TypeScale.caption,
                ),
                if (running) ...[
                  const SizedBox(height: Space.xs),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: job.progress,
                      minHeight: 3,
                      backgroundColor: Tones.hairline,
                      color: Tones.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Space.md),
          Text(
            status,
            style: TypeScale.mono.copyWith(
              color: failed ? Tones.warn : Tones.textMuted,
            ),
          ),
          IconButton(
            tooltip: failed ? 'Retry' : 'Cancel',
            onPressed: () {
              if (failed) {
                manager.dismiss(job.sha);
                manager.enqueue(job.sha);
              } else {
                manager.cancel(job.sha);
              }
            },
            icon: Icon(
              failed ? Icons.refresh_rounded : Icons.close_rounded,
              size: 20,
              color: failed ? Tones.warn : Tones.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
