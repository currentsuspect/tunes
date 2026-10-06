import '../platform/device.dart';

import 'package:flutter/material.dart';

import '../data/download_manager.dart';
import '../data/download_store.dart';
import '../theme/tokens.dart';

/// The download control on a song: one widget for every screen that has one.
///
/// It watches the download manager itself. The album page used to be handed a
/// plain "is downloading" flag when it was built, and a page that stays mounted
/// never saw it change, so nothing moved while a song downloaded. Only the
/// track-list rows watched the manager, which is why only they ever showed
/// progress.
///
/// Five states, each its own shape so they read at a glance, and each change a
/// short settled fade rather than a swap:
///  - idle: an outlined arrow
///  - queued: the arrow, pulsing, waiting its turn
///  - running: a ring that fills as bytes arrive (turning if the size is unknown)
///  - held: a green tick, popped in; tap to remove, with Undo
///  - failed: a retry in the warning colour
class DownloadButton extends StatelessWidget {
  const DownloadButton({
    super.key,
    required this.sha,
    required this.title,
    required this.store,
    required this.onDownload,
    this.offline = false,
    this.fallbackActive = false,
  });

  final String sha;
  final String title;
  final DownloadStore store;
  final VoidCallback onDownload;
  final bool offline;

  /// Used only when no download manager is in scope (a screen outside the
  /// app shell, a test): the caller's own idea of whether this is downloading.
  final bool fallbackActive;

  Future<void> _remove(BuildContext context, DownloadManager? manager) async {
    final messenger = ScaffoldMessenger.of(context);
    await store.remove(sha);
    if (!context.mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Removed "$title" from ${Device.thisOne}'),
        duration: const Duration(seconds: 5),
        // An action keeps a snackbar up until dismissed unless told otherwise.
        persist: false,
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
    // Reading the scope here makes this rebuild on every manager change.
    final manager = DownloadScope.maybeOf(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final job = manager?.jobFor(sha);
        final held = store.pathFor(sha) != null;
        final still = MediaQuery.disableAnimationsOf(context);
        final fade = still ? Duration.zero : const Duration(milliseconds: 220);

        final Widget face;
        final String label;
        final VoidCallback? onTap;
        if (held) {
          face = const _Held(key: ValueKey('held'));
          label = 'On ${Device.thisOne}. Tap to remove.';
          onTap = () => _remove(context, manager);
        } else if (job != null && job.phase == DownloadPhase.failed) {
          face = const _Failed(key: ValueKey('failed'));
          label = 'Download failed. Tap to retry.';
          onTap = () {
            manager?.dismiss(sha);
            onDownload();
          };
        } else if (job != null && job.phase == DownloadPhase.running) {
          face = _Running(
            key: const ValueKey('running'),
            progress: job.progress,
          );
          final pct = job.progress == null
              ? ''
              : ' ${(job.progress! * 100).round()} percent';
          label = 'Downloading$pct. Tap to cancel.';
          onTap = () => manager?.cancel(sha);
        } else if (job != null || fallbackActive) {
          face = const _Queued(key: ValueKey('queued'));
          label = 'Waiting to download. Tap to cancel.';
          onTap = manager == null ? null : () => manager.cancel(sha);
        } else {
          face = Icon(
            Icons.arrow_circle_down_outlined,
            key: const ValueKey('idle'),
            size: 22,
            color: offline ? Tones.hairline : Tones.textMuted,
          );
          label = offline
              ? 'Offline. Download unavailable.'
              : 'Download to ${Device.thisOne}.';
          onTap = offline ? null : onDownload;
        }

        return Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: InkResponse(
            onTap: onTap,
            radius: 22,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: AnimatedSwitcher(
                  duration: fade,
                  switchInCurve: Curves.easeOutBack,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  ),
                  child: face,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// On the phone: a tick in the one green the app uses for that.
class _Held extends StatelessWidget {
  const _Held({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Tones.held.withValues(alpha: 0.16),
        border: Border.all(color: Tones.held, width: 1.5),
      ),
      child: const Icon(Icons.check_rounded, size: 14, color: Tones.held),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({super.key});

  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.refresh_rounded, size: 22, color: Tones.warn);
  }
}

/// A ring that fills as the song arrives. The fill is tweened between reports,
/// so ten updates a second read as one smooth sweep.
class _Running extends StatelessWidget {
  const _Running({super.key, required this.progress});

  final double? progress;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (p == null)
            const CircularProgressIndicator(
              strokeWidth: 2.2,
              color: Tones.primary,
              backgroundColor: Tones.hairline,
            )
          else
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: p),
              duration: const Duration(milliseconds: 180),
              builder: (context, value, _) => CircularProgressIndicator(
                value: value,
                strokeWidth: 2.2,
                color: Tones.primary,
                backgroundColor: Tones.hairline,
              ),
            ),
          const Icon(Icons.stop_rounded, size: 11, color: Tones.textMuted),
        ],
      ),
    );
  }
}

/// Waiting its turn: the arrow, breathing.
class _Queued extends StatefulWidget {
  const _Queued({super.key});

  @override
  State<_Queued> createState() => _QueuedState();
}

class _QueuedState extends State<_Queued> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return const Icon(
        Icons.arrow_circle_down_outlined,
        size: 22,
        color: Tones.primary,
      );
    }
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_c),
      child: const Icon(
        Icons.arrow_circle_down_outlined,
        size: 22,
        color: Tones.primary,
      ),
    );
  }
}
