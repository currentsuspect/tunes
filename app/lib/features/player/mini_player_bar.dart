import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/theme/tokens.dart';
import '../../domain/manifest.dart';

class MiniPlayerBar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final current = player.current;
        if (current == null) return const SizedBox.shrink();
        return Container(
          decoration: const BoxDecoration(
            color: Tones.surface,
            border: Border(top: BorderSide(color: Tones.hairline)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ProgressSeekBar(player: player),
              _SwipeableBody(
                player: player,
                onTap: onTap,
                artUrlFor: artUrlFor,
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
  const _ProgressSeekBar({required this.player});

  final TunePlayer player;

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
        final pos = player.position.inMilliseconds.clamp(0, total);
        final ratio = total > 0 ? pos / total : 0.0;
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
                      child: LayoutBuilder(
                        builder: (context, c) => Stack(
                          children: [
                            Container(color: Tones.surfaceRaised),
                            FractionallySizedBox(
                              widthFactor: ratio.clamp(0.0, 1.0),
                              child: Container(color: Tones.primary),
                            ),
                          ],
                        ),
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

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: track.artSha != null && widget.artUrlFor != null
                    ? Image.network(
                        widget.artUrlFor!(track.artSha!),
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const _MiniArtPlaceholder(),
                      )
                    : const _MiniArtPlaceholder(),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
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
                    track.artist,
                    style: TypeScale.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: widget.player.toggle,
              icon: Icon(
                widget.player.playing
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 30,
                color: Tones.primary,
              ),
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
