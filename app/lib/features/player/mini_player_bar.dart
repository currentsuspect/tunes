import 'package:flutter/material.dart';

import '../../core/audio/playhead_clock.dart';
import '../../core/audio/tune_player.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/artwork.dart';
import '../../domain/manifest.dart';

class MiniPlayerBar extends StatefulWidget {
  const MiniPlayerBar({
    super.key,
    required this.player,
    required this.onTap,
    this.artUrlFor,
  });

  final TunePlayer player;
  final VoidCallback onTap;
  final String Function(String sha)? artUrlFor;

  @override
  State<MiniPlayerBar> createState() => _MiniPlayerBarState();
}

class _MiniPlayerBarState extends State<MiniPlayerBar>
    with SingleTickerProviderStateMixin {
  /// Owned here rather than inside the progress bar, so the bar rebuilding
  /// for a new track does not restart the clock mid-play.
  late final PlayheadClock _playhead;

  @override
  void initState() {
    super.initState();
    _playhead = PlayheadClock(player: widget.player, vsync: this);
  }

  @override
  void dispose() {
    _playhead.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.player,
      builder: (context, _) {
        final current = widget.player.current;
        if (current == null) return const SizedBox.shrink();
        return Container(
          // No border of its own: the bar and the navigation share one
          // surface now, and the top edge is drawn once by the container
          // that holds both. Two hairlines a pixel apart read as a seam.
          decoration: const BoxDecoration(color: Tones.surface),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ProgressSeekBar(player: widget.player, playhead: _playhead),
              _SwipeableBody(
                player: widget.player,
                onTap: widget.onTap,
                artUrlFor: widget.artUrlFor,
                track: current,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Thin progress / seek bar across the top of the mini-player. Tap or
/// drag to seek. Renders zero-height when nothing is loaded.
class _ProgressSeekBar extends StatelessWidget {
  const _ProgressSeekBar({required this.player, required this.playhead});

  final TunePlayer player;

  /// Read instead of `player.position`, which only changes when the player
  /// reports -- four times a second at best, which is a bar that lurches
  /// rather than moves.
  final PlayheadClock playhead;

  static const _trackHeight = 3.0;
  static const _swipeSeekThresholdDp = 24.0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final current = player.current;
        if (current == null) return const SizedBox.shrink();
        final duration = player.duration.inMilliseconds > 0
            ? player.duration
            : Duration(milliseconds: current.durationMs ?? 0);
        final total = duration.inMilliseconds;
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) =>
                  _seekTo(details.localPosition.dx, width, duration),
              onHorizontalDragStart: (details) =>
                  _seekTo(details.localPosition.dx, width, duration),
              onHorizontalDragUpdate: (details) =>
                  _seekTo(details.localPosition.dx, width, duration),
              child: SizedBox(
                height: _trackHeight + _swipeSeekThresholdDp,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      height: _trackHeight,
                      // Only this repaints per frame. The row below it --
                      // artwork, text, buttons -- is outside the builder and
                      // stays put.
                      child: ValueListenableBuilder<Duration>(
                        valueListenable: playhead,
                        builder: (context, position, _) {
                          final pos = position.inMilliseconds.clamp(0, total);
                          final ratio = total > 0 ? pos / total : 0.0;
                          return Stack(
                            children: [
                              Container(color: Tones.surfaceRaised),
                              FractionallySizedBox(
                                widthFactor: ratio.clamp(0.0, 1.0),
                                child: Container(color: Tones.primary),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _seekTo(double dx, double width, Duration duration) {
    if (width <= 0 || duration.inMilliseconds <= 0) return;
    final clamped = dx.clamp(0.0, width);
    final ms = ((clamped / width) * duration.inMilliseconds).round();
    player.seek(Duration(milliseconds: ms));
  }
}

/// Mini-player content row: artwork, title/artist, transport.
/// Wraps the body in a horizontal-drag detector so swipes feel like
/// "moving the current track aside" — small horizontal translate of
/// the artwork while dragging, snaps back on release. Threshold gates
/// accidental triggers from vertical scrolling.
class _SwipeableBody extends StatefulWidget {
  const _SwipeableBody({
    required this.player,
    required this.onTap,
    required this.artUrlFor,
    required this.track,
  });

  final TunePlayer player;
  final VoidCallback onTap;
  final String Function(String sha)? artUrlFor;
  final ManifestTrack track;

  @override
  State<_SwipeableBody> createState() => _SwipeableBodyState();
}

class _SwipeableBodyState extends State<_SwipeableBody> {
  double _dragDx = 0;
  bool _resolved = false;
  // 80dp threshold past which we commit to "skip"; under that, the
  // gesture is treated as a tap-and-cancel.
  static const _commitDp = 80.0;

  /// Fast enough to be a deliberate flick rather than a scroll that drifted
  /// upward on release.
  static const _flingUpVelocity = 300.0;

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      // Swipe up opens the player. The bar is the handle for a screen that
      // lives above it, so the gesture that reveals it should be the one that
      // matches the direction it comes from.
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity != null &&
            details.primaryVelocity! < -_flingUpVelocity) {
          widget.onTap();
        }
      },
      onHorizontalDragStart: (_) {
        _dragDx = 0;
        _resolved = false;
      },
      onHorizontalDragUpdate: (details) {
        _dragDx += details.delta.dx;
        if (!_resolved && _dragDx.abs() > _commitDp) {
          _resolved = true;
          if (_dragDx < 0) {
            widget.player.next();
          } else {
            widget.player.previous();
          }
        }
        // Show translation only while we're still deciding; once we
        // commit, snap back so the new artwork appears in place.
        setState(() {});
      },
      onHorizontalDragEnd: (_) {
        _dragDx = 0;
        _resolved = false;
        if (mounted) setState(() {});
      },
      onHorizontalDragCancel: () {
        _dragDx = 0;
        _resolved = false;
        if (mounted) setState(() {});
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          Space.md,
          Space.sm,
          Space.md,
          Space.sm,
        ),
        child: Row(
          children: [
            Transform.translate(
              offset: Offset(
                _resolved ? 0 : _dragDx.clamp(-24.0, 24.0) * 0.6,
                0,
              ),
              // The same sleeve the player shows, so opening it is one
              // object growing rather than two screens swapping. Tagged by
              // the track, so a change mid-flight cannot pair the wrong two.
              child: Hero(
                tag: 'sleeve-${track.sha}',
                child: Artwork(
                  url: track.artSha != null && widget.artUrlFor != null
                      ? widget.artUrlFor!(track.artSha!)
                      : null,
                  size: 44,
                  borderRadius: 8,
                  fallback: const _MiniArtPlaceholder(),
                ),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              // Keyed on the track, so a change cross-fades rather than
              // snapping. Two hundred milliseconds: long enough to read as a
              // change, short enough that it never delays the next tap.
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Column(
                  key: ValueKey(track.sha),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      style: TypeScale.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artistDisplay,
                      style: TypeScale.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            _TransportButton(
              playing: widget.player.playing,
              onPressed: widget.player.toggle,
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniArtPlaceholder extends StatelessWidget {
  const _MiniArtPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      color: Tones.surfaceRaised,
      child: const Icon(
        Icons.music_note_rounded,
        size: 18,
        color: Tones.textMuted,
      ),
    );
  }
}

/// Play/pause with a press it can be felt through.
///
/// The icon swaps under a scale rather than being replaced outright: on a
/// control this small, an instant swap reads as a glitch, and a bounce reads
/// as a toy. This is a short, flat dip and back.
class _TransportButton extends StatefulWidget {
  const _TransportButton({required this.playing, required this.onPressed});

  final bool playing;
  final VoidCallback onPressed;

  @override
  State<_TransportButton> createState() => _TransportButtonState();
}

class _TransportButtonState extends State<_TransportButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onPressed,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _down ? 0.86 : 1,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: Padding(
          padding: const EdgeInsets.all(Space.sm),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 140),
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: Icon(
              widget.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              key: ValueKey(widget.playing),
              size: 30,
              color: Tones.primary,
            ),
          ),
        ),
      ),
    );
  }
}
