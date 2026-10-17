import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../domain/manifest.dart';
import '../audio/tune_player.dart';
import '../theme/tokens.dart';

/// Swipe between songs, as a carousel rather than a trigger.
///
/// What [builder] draws for the playing song follows the finger the whole
/// way, the song either side slides in behind it, and nothing changes until
/// the finger lets go: far enough (or flicked) and the neighbour settles into
/// place and plays; not far enough and it springs back. The mini bar used to
/// skip at a fixed 80dp mid-drag while its art moved 14dp, so a swipe felt
/// like pulling a cord rather than moving the record aside.
///
/// Used by the mini bar and the top of the lyrics, so the same gesture does
/// the same thing in both. [trailing] sits outside the sliding part -- it
/// belongs to the bar, not the song -- but a swipe that starts on it still
/// counts.
class TrackSwipe extends StatefulWidget {
  const TrackSwipe({
    super.key,
    required this.player,
    required this.track,
    required this.builder,
    this.trailing,
    this.onTap,
    this.onFlingUp,
    this.padding = EdgeInsets.zero,
  });

  final TunePlayer player;

  /// The song in the middle: normally the player's current one.
  final ManifestTrack track;

  /// One song's face. `current` is false for the neighbours peeking in, which
  /// should leave out anything that only makes sense for the playing song
  /// (a shared hero tag, the "playing from" line).
  final Widget Function(BuildContext context, ManifestTrack track, bool current)
  builder;

  final Widget? trailing;
  final VoidCallback? onTap;

  /// A deliberate flick upward, for a bar that opens something above it.
  final VoidCallback? onFlingUp;

  final EdgeInsetsGeometry padding;

  @override
  State<TrackSwipe> createState() => _TrackSwipeState();
}

class _TrackSwipeState extends State<TrackSwipe>
    with SingleTickerProviderStateMixin {
  /// Horizontal offset of the song in the middle, in logical pixels.
  late final AnimationController _slide = AnimationController.unbounded(
    vsync: this,
  )..addListener(() => setState(() {}));

  /// Width of the sliding area, read at layout.
  double _width = 1;

  /// The song a swipe just landed on, shown until the player catches up, so
  /// the old one does not flash back into the middle for the few frames the
  /// decoder takes to report the change.
  ManifestTrack? _landed;
  Timer? _landedExpiry;

  /// Set for the one rebuild where the middle changes because of a swipe:
  /// the neighbour is already in place, so a cross-fade would be a stutter.
  bool _instant = false;

  /// Whether the drag is past the point where letting go commits, so the
  /// crossing can be felt once rather than every frame.
  bool _armed = false;

  /// Fast enough to be a deliberate flick rather than a scroll that drifted
  /// upward on release.
  static const _flingUpVelocity = 300.0;

  /// A flick this fast commits even if it travelled a short way.
  static const _flingSideVelocity = 650.0;

  /// Past this share of the width, letting go commits.
  static const _commitShare = 0.3;

  @override
  void dispose() {
    _landedExpiry?.cancel();
    _slide.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TrackSwipe old) {
    super.didUpdateWidget(old);
    if (_landed != null && widget.track.sha == _landed!.sha) {
      _landed = null;
      _landedExpiry?.cancel();
    }
  }

  /// The song one step forward (+1) or back (-1) in the queue as it will
  /// actually play, or null when there is none to show.
  ManifestTrack? _neighbour(int dir) {
    final q = widget.player.queue;
    if (q.isEmpty) return null;
    final j = widget.player.index + dir;
    if (j >= 0 && j < q.length) return q[j];
    if (widget.player.repeat == PlaybackRepeat.all && q.length > 1) {
      return q[(j + q.length) % q.length];
    }
    return null;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_slide.isAnimating) _slide.stop();
    final next = _slide.value + details.delta.dx;
    final dir = next < 0 ? 1 : -1;
    // Nothing that way: it gives, but grudgingly, so it is clear there is no
    // song there rather than the swipe being ignored.
    final open = _neighbour(dir) != null;
    _slide.value = open ? next : _slide.value + details.delta.dx * 0.3;
    final armed = open && _slide.value.abs() > _width * _commitShare;
    if (armed != _armed) {
      _armed = armed;
      if (armed) HapticFeedback.selectionClick();
    }
  }

  void _onDragEnd(DragEndDetails details) {
    _armed = false;
    final dx = _slide.value;
    final v = details.primaryVelocity ?? 0;
    final dir = dx < 0 ? 1 : -1;
    final target = _neighbour(dir);
    final far = dx.abs() > _width * _commitShare;
    final flung = v.abs() > _flingSideVelocity && v.sign == dx.sign;
    if (dx != 0 && (far || flung)) {
      if (target != null) {
        _commit(dir, target);
        return;
      }
      // Off the end of the queue going forward is still "next": the radio
      // may pick something up from there, and there is nothing to show until
      // it does.
      if (dir == 1) widget.player.next();
    }
    _settleBack(v);
  }

  void _commit(int dir, ManifestTrack target) {
    final end = -dir * (_width + Space.md);
    final remaining = (end - _slide.value).abs() / _width;
    _slide
        .animateTo(
          end,
          // The further it has to go the longer it takes, but never so quick
          // it reads as a cut.
          duration: Duration(
            milliseconds: (240 * remaining).clamp(90, 240).round(),
          ),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
          if (!mounted) return;
          setState(() {
            _landed = target;
            _instant = true;
            _slide.value = 0;
          });
          _landedExpiry?.cancel();
          _landedExpiry = Timer(const Duration(seconds: 2), () {
            if (mounted) setState(() => _landed = null);
          });
          final q = widget.player.queue;
          final j = widget.player.index + dir;
          // By index rather than next()/previous(): previous restarts the
          // song when it is a few seconds in, and repeat-one makes next a
          // restart too. A swipe always means the song that was showing.
          widget.player.playAt((j + q.length) % q.length);
        });
  }

  void _settleBack(double velocity) {
    _slide.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 520, damping: 34),
        _slide.value,
        0,
        velocity,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _landed ?? widget.track;
    final instant = _instant;
    _instant = false;
    final dx = _slide.value;
    final next = dx < 0 ? _neighbour(1) : null;
    final prev = dx > 0 ? _neighbour(-1) : null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onVerticalDragEnd: widget.onFlingUp == null
          ? null
          : (details) {
              final v = details.primaryVelocity;
              if (v != null && v < -_flingUpVelocity) widget.onFlingUp!();
            },
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: () => _settleBack(0),
      child: Padding(
        padding: widget.padding,
        child: Row(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _width = constraints.maxWidth <= 0 ? 1 : constraints.maxWidth;
                  // A little gap between the two songs, so they read as two
                  // things passing rather than one strip.
                  final pitch = _width + Space.md;
                  return ClipRect(
                    child: Stack(
                      children: [
                        Transform.translate(
                          offset: Offset(dx, 0),
                          child: AnimatedSwitcher(
                            duration: instant
                                ? Duration.zero
                                : const Duration(milliseconds: 200),
                            // The default stacks its children centred, which
                            // floated the title to the middle instead of
                            // beside the sleeve.
                            layoutBuilder: (current, previous) => Stack(
                              alignment: Alignment.centerLeft,
                              children: [...previous, ?current],
                            ),
                            child: KeyedSubtree(
                              key: ValueKey(shown.sha),
                              child: widget.builder(context, shown, true),
                            ),
                          ),
                        ),
                        if (next != null)
                          Positioned.fill(
                            child: Transform.translate(
                              offset: Offset(dx + pitch, 0),
                              child: widget.builder(context, next, false),
                            ),
                          ),
                        if (prev != null)
                          Positioned.fill(
                            child: Transform.translate(
                              offset: Offset(dx - pitch, 0),
                              child: widget.builder(context, prev, false),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            ?widget.trailing,
          ],
        ),
      ),
    );
  }
}
