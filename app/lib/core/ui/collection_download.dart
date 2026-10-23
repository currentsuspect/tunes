import 'package:flutter/material.dart';

import '../data/download_manager.dart';
import '../data/download_store.dart';
import '../platform/device.dart';
import '../theme/looks.dart';
import '../theme/tokens.dart';
import 'crayon_marks.dart';
import '../../domain/manifest.dart';

/// Download the whole album, and say how it is going.
///
/// This was an outlined button that queued every track and then did nothing: the
/// rows underneath had their own state, but nothing on the button said anything
/// had started. It now shows the album as one: an arrow when none of it is on
/// the phone, a ring filling with the count while it comes down, and a green
/// tick when all of it is.
class CollectionDownload extends StatelessWidget {
  const CollectionDownload({
    super.key,
    required this.tracks,
    required this.store,
    required this.offline,
    required this.onDownload,
    this.noun = 'album',
  });

  /// What the set is called in the button's words: album, playlist, mix.
  final String noun;

  final List<ManifestTrack> tracks;
  final DownloadStore store;
  final bool offline;
  final void Function(ManifestTrack) onDownload;

  @override
  Widget build(BuildContext context) {
    final manager = DownloadScope.maybeOf(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final held = tracks.where((t) => store.pathFor(t.sha) != null).length;
        final total = tracks.length;
        final inFlight = manager == null
            ? 0
            : tracks.where((t) => manager.isActive(t.sha)).length;
        var partial = 0.0;
        if (manager != null) {
          for (final t in tracks) {
            final j = manager.jobFor(t.sha);
            if (j != null && j.phase == DownloadPhase.running) {
              partial += j.progress ?? 0;
            }
          }
        }
        final all = total > 0 && held == total;
        final working = inFlight > 0;
        final value = total == 0
            ? 0.0
            : ((held + partial) / total).clamp(0.0, 1.0);

        final crayon = Looks.current.kind == LookKind.crayon;
        final Widget face;
        final String label;
        if (all && crayon) {
          face = const CrayonDownloadFace(
            key: ValueKey('all'),
            state: CrayonDownloadState.held,
          );
          label = 'All $total songs are on ${Device.thisOne}';
        } else if (all) {
          face = Icon(
            Icons.check_circle_rounded,
            key: ValueKey('all'),
            size: 22,
            color: Tones.held,
          );
          label = 'All $total songs are on ${Device.thisOne}';
        } else if (working && crayon) {
          face = TweenAnimationBuilder<double>(
            key: const ValueKey('working'),
            tween: Tween<double>(begin: 0, end: value),
            duration: const Duration(milliseconds: 220),
            builder: (context, v, _) => CrayonDownloadFace(
              state: CrayonDownloadState.running,
              progress: v,
            ),
          );
          label = 'Downloading, $held of $total done';
        } else if (working) {
          face = Stack(
            key: const ValueKey('working'),
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: value),
                  duration: const Duration(milliseconds: 220),
                  builder: (context, v, _) => CircularProgressIndicator(
                    value: v,
                    strokeWidth: 2.4,
                    color: Tones.primary,
                    backgroundColor: Tones.hairline,
                  ),
                ),
              ),
              Text('$held', style: TypeScale.mono.copyWith(fontSize: 9)),
            ],
          );
          label = 'Downloading, $held of $total done';
        } else {
          face = crayon
              ? CrayonDownloadFace(
                  key: const ValueKey('idle'),
                  state: CrayonDownloadState.idle,
                  dim: offline,
                )
              : Icon(
                  Icons.arrow_circle_down_outlined,
                  key: const ValueKey('idle'),
                  size: 22,
                  color: offline ? Tones.hairline : Tones.text,
                );
          label = held == 0
              ? 'Download the $noun'
              : 'Download the other ${total - held} songs';
        }

        return Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: Tooltip(
            message: label,
            child: InkResponse(
              radius: 26,
              onTap: offline && !all
                  ? null
                  : () {
                      if (all) {
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            SnackBar(
                              content: Text(
                                'All $total songs are on ${Device.thisOne}. Remove '
                                'them one at a time from the tick beside each.',
                              ),
                            ),
                          );
                        return;
                      }
                      for (final t in tracks) {
                        if (store.pathFor(t.sha) == null &&
                            !(manager?.isActive(t.sha) ?? false)) {
                          onDownload(t);
                        }
                      }
                    },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: all ? Tones.held : Tones.hairline),
                ),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutBack,
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: ScaleTransition(scale: a, child: child),
                    ),
                    child: face,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
