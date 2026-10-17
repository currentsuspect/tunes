import '../platform/device.dart';

import 'package:flutter/material.dart';

import '../data/download_manager.dart';
import '../theme/tokens.dart';

/// Downloading, shown from anywhere.
///
/// A slim bar that appears above the mini bar while anything is downloading and
/// leaves when it is done: how many, how far, and one tap to the full list. It
/// is the answer to "did that start?" on the album's Download button, which
/// queues a dozen songs with nothing on screen to say so.
///
/// Failures stay on it ("2 failed") until dismissed, because a download that
/// quietly did not happen is the worst kind.
class DownloadsBar extends StatelessWidget {
  const DownloadsBar({super.key, required this.manager, required this.onTap});

  final DownloadManager manager;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final active = manager.activeCount;
        final failed = manager.failedCount;
        final show = active > 0 || failed > 0;
        // Only the height animates, by a factor, which is fine at a duration of
        // zero. AnimatedSize is not: with animations off its zero-length run
        // asserts in the middle of layout.
        return SizedBox(
          width: double.infinity,
          child: ClipRect(
            child: AnimatedAlign(
              duration: still
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomCenter,
              heightFactor: show ? 1 : 0,
              child: show
                  ? _Body(manager: manager, onTap: onTap)
                  : const SizedBox(width: double.infinity),
            ),
          ),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.manager, required this.onTap});

  final DownloadManager manager;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = manager.activeCount;
    final failed = manager.failedCount;
    final progress = manager.overallProgress;
    final total = manager.batchTotal;
    final done = manager.batchDone;

    final String text;
    final Color color;
    if (active > 0) {
      // "3 of 12": the song in progress counts as the next one.
      final at = (done + 1).clamp(1, total <= 0 ? 1 : total);
      text = total <= 1
          ? 'Saving to ${Device.thisOne}'
          : 'Saving $at of $total';
      color = Tones.text;
    } else {
      text = failed == 1 ? '1 download failed' : '$failed downloads failed';
      color = Tones.warn;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.sm + 2,
        Space.sm,
        Space.sm + 2,
        0,
      ),
      child: Material(
        color: Tones.surfaceRaised,
        borderRadius: BorderRadius.circular(RadiusTokens.control),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Tones.hairline),
              borderRadius: BorderRadius.circular(RadiusTokens.control),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.md,
                    vertical: Space.sm,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        active > 0
                            ? Icons.arrow_circle_down_rounded
                            : Icons.error_outline_rounded,
                        size: 18,
                        color: active > 0 ? Tones.primary : Tones.warn,
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Text(
                          text,
                          style: TypeScale.caption.copyWith(color: color),
                        ),
                      ),
                      if (active > 0 && progress != null)
                        Text(
                          '${(progress * 100).round()}%',
                          style: TypeScale.mono.copyWith(color: Tones.text),
                        ),
                      const SizedBox(width: Space.xs),
                      Icon(
                        Icons.keyboard_arrow_up_rounded,
                        size: 18,
                        color: Tones.textMuted,
                      ),
                    ],
                  ),
                ),
                if (active > 0)
                  if (progress == null)
                    LinearProgressIndicator(
                      minHeight: 2.5,
                      backgroundColor: Tones.hairline,
                      color: Tones.primary,
                    )
                  else
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: progress),
                      duration: const Duration(milliseconds: 220),
                      builder: (context, value, _) => LinearProgressIndicator(
                        value: value,
                        minHeight: 2.5,
                        backgroundColor: Tones.hairline,
                        color: Tones.primary,
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
