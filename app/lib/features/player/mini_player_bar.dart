import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/audio/playhead_clock.dart';
import '../../core/audio/tune_player.dart';
import '../../core/data/download_manager.dart';
import '../../core/data/reachability.dart';
import '../../core/theme/looks.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/cover_tint.dart';
import '../../core/ui/source_pill.dart';
import '../../core/ui/artwork.dart';
import '../../core/ui/generated_artwork.dart';
import '../../core/ui/shared_sleeve.dart';
import '../../core/ui/track_swipe.dart';
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
        // Where the sound comes from, said on the second line. Read from the
        // scopes so the bar needs nothing handed to it, and follows a
        // download finishing or the connection dropping as it happens.
        final held =
            DownloadScope.maybeOf(context)?.store.pathFor(current.sha) != null;
        final offline = ReachabilityScope.maybeOf(context)?.offline ?? false;
        final source = sourceFor(held: held, offline: offline);
        return TintBuilder(
          artSha: current.artSha,
          builder: (context, tint) => Padding(
            // A raised card floating above the tabs, not a strip bolted to
            // them: the bar is the one thing always on screen, so it gets to
            // be an object.
            padding: const EdgeInsets.fromLTRB(
              Space.sm + 2,
              Space.sm,
              Space.sm + 2,
              Space.xs,
            ),
            child: DecoratedBox(
              decoration: _barDecoration(tint),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_barRadius),
                child: Stack(
                  children: [
                    _SwipeableBody(
                      player: widget.player,
                      onTap: widget.onTap,
                      artUrlFor: widget.artUrlFor,
                      track: current,
                      source: source,
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _ProgressSeekBar(
                        player: widget.player,
                        playhead: _playhead,
                        accent: tint,
                      ),
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

/// Thin progress / seek bar across the top of the mini-player. Tap or
/// drag to seek. Renders zero-height when nothing is loaded.
class _ProgressSeekBar extends StatelessWidget {
  const _ProgressSeekBar({
    required this.player,
    required this.playhead,
    required this.accent,
  });

  final Color accent;

  final TunePlayer player;

  /// Read instead of `player.position`, which only changes when the player
  /// reports -- four times a second at best, which is a bar that lurches
  /// rather than moves.
  final PlayheadClock playhead;

  static const _trackHeight = 2.5;

  /// The touch target is taller than the line it draws, and sits over the
  /// bottom edge of the card, so the visible bar stays a hairline.
  static const _swipeSeekThresholdDp = 14.0;

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
                  alignment: Alignment.bottomCenter,
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
                              Container(color: Tones.hairline),
                              FractionallySizedBox(
                                widthFactor: ratio.clamp(0.0, 1.0),
                                child: Container(color: accent),
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

/// Mini-player content row: artwork, title/artist, transport. Swiping it is
/// the shared [TrackSwipe] carousel; the play button stays put.
class _SwipeableBody extends StatelessWidget {
  const _SwipeableBody({
    required this.player,
    required this.onTap,
    required this.artUrlFor,
    required this.track,
    required this.source,
  });

  final TunePlayer player;
  final VoidCallback onTap;
  final String Function(String sha)? artUrlFor;
  final ManifestTrack track;
  final TrackSource source;

  @override
  Widget build(BuildContext context) {
    return TrackSwipe(
      player: player,
      track: track,
      onTap: onTap,
      // Swipe up opens the player. The bar is the handle for a screen that
      // lives above it, so the gesture that reveals it should be the one that
      // matches the direction it comes from.
      onFlingUp: onTap,
      padding: const EdgeInsets.fromLTRB(
        Space.sm,
        Space.sm,
        Space.sm,
        Space.sm + 2,
      ),
      builder: (context, t, current) => _info(context, t, current: current),
      trailing: _TransportButton(
        playing: player.playing,
        onPressed: player.toggle,
      ),
    );
  }

  /// Sleeve and two lines for one song. Only the playing one carries the
  /// shared sleeve (two heroes with one tag would collide) and the source.
  Widget _info(
    BuildContext context,
    ManifestTrack track, {
    required bool current,
  }) {
    final art = Artwork(
      shared: current,
      url: track.artSha != null && artUrlFor != null
          ? artUrlFor!(track.artSha!)
          : null,
      artSha: track.artSha,
      size: 42,
      borderRadius: 9,
      // The same generated tile the list rows use. A blank square in the one
      // bar that is always on screen made tracks without a cover look like a
      // failed load.
      fallback: GeneratedArtwork.fromTrack(track, size: 42, borderRadius: 9),
    );
    return Row(
      children: [
        // The same sleeve the player shows, so opening it is one object
        // growing rather than two screens swapping. Tagged by the track, so a
        // change mid-flight cannot pair the wrong two.
        current ? SharedSleeve(tag: 'sleeve-${track.sha}', child: art) : art,
        const SizedBox(width: Space.md),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track.title,
                style: TypeScale.title.copyWith(
                  fontSize: 14,
                  fontVariations: const [FontVariation('wght', 500)],
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              // Artist, then where the sound is coming from. The second part
              // is the only coloured thing in the bar, so a track that will
              // not play is noticed before it is tapped.
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: track.artistDisplay),
                    if (current) ...[
                      const TextSpan(text: '  ·  '),
                      // Another device's music says so, in the accent: the
                      // sound is not here, and the buttons are a remote.
                      if (player.remoteDeviceLabel != null)
                        TextSpan(
                          text: 'playing on ${player.remoteDeviceLabel}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        )
                      else
                        TextSpan(
                          text: source.label,
                          style: TextStyle(color: source.color),
                        ),
                    ],
                  ],
                ),
                style: TypeScale.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
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
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onPressed();
      },
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        button: true,
        label: widget.playing ? 'Pause' : 'Play',
        child: AnimatedScale(
          scale: _down ? 0.86 : 1,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          child: Padding(
            padding: const EdgeInsets.all(Space.xs),
            child: Container(
              width: 36,
              height: 36,
              // Room: a solid button. Noir: a gold ring. Crayon: ink, with
              // the sun inside.
              decoration: BoxDecoration(
                color: Looks.current.kind == LookKind.noir
                    ? Colors.transparent
                    : Tones.text,
                shape: BoxShape.circle,
                border: Looks.current.kind == LookKind.noir
                    ? Border.all(color: Tones.primary)
                    : null,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 140),
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: Icon(
                  widget.playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  key: ValueKey(widget.playing),
                  size: 22,
                  color: switch (Looks.current.kind) {
                    LookKind.noir => Tones.primary,
                    LookKind.crayon => Looks.current.crayons[1],
                    LookKind.room => Tones.base,
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The bar's shape per room (mood board, 9 Oct). Room: a raised card lit by
/// the cover. Crayon: a sticker on the page, sun yellow on paper, ink edge
/// and a hard offset shadow. Noir: no card at all, a hairline above.
double get _barRadius => switch (Looks.current.kind) {
  LookKind.noir => 0,
  LookKind.crayon => 18,
  LookKind.room => RadiusTokens.card - 2,
};

BoxDecoration _barDecoration(Color tint) {
  final look = Looks.current;
  switch (look.kind) {
    case LookKind.crayon:
      return BoxDecoration(
        // Sun yellow on paper; on the chalkboard the yellow would drown the
        // chalk-coloured words, so the bar stays dark there.
        color: look.isDark ? look.surfaceRaised : look.crayons[1],
        borderRadius: BorderRadius.circular(_barRadius),
        border: Border.all(color: look.text, width: 2.5),
        boxShadow: [BoxShadow(color: look.text, offset: const Offset(3, 4))],
      );
    case LookKind.noir:
      return BoxDecoration(
        color: look.base,
        border: Border(top: BorderSide(color: look.hairline)),
      );
    case LookKind.room:
      return BoxDecoration(
        color: Tones.surfaceRaised,
        borderRadius: BorderRadius.circular(_barRadius),
        border: Border.all(color: Tones.hairline),
        boxShadow: [
          BoxShadow(
            color: tint.withValues(alpha: 0.28),
            blurRadius: 26,
            spreadRadius: -6,
            offset: const Offset(0, 8),
          ),
        ],
      );
  }
}
