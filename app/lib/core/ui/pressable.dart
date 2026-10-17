import 'package:flutter/material.dart';

import '../theme/looks.dart';
import '../theme/tokens.dart';

/// A card that answers the finger -- through its picture, not all of it.
///
/// Ink ripples are the wrong feedback for artwork: the splash lands on top of
/// the image, or is clipped away by the rounded corner and never seen at all.
/// Scaling the whole card was the next try, and it moved the caption too, so
/// the entire tile lurched. Now the card only listens; the [PressTarget]
/// inside it (the cover) is what gives under a press and lifts under a mouse.
/// The words stay still, the way a sleeve moves in a hand and its label does
/// not.
///
/// Deliberately small and fast -- ninety milliseconds down, a hair over on
/// release. Anything springier turns a library into a toy.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.scale = 0.96,
  });

  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  /// How far the target gives. Four percent is enough to read on a 132-point
  /// cover and not enough to look like it moved.
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  bool _hover = false;

  void _setDown(bool down) {
    if (_down == down) return;
    setState(() => _down = down);
  }

  void _setHover(bool hover) {
    if (_hover == hover) return;
    setState(() => _hover = hover);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: GestureDetector(
        // Opaque, so the gap between a cover and its caption is part of the
        // card rather than a dead strip down the middle of the rail.
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: (_) => _setDown(true),
        onTapUp: (_) => _setDown(false),
        onTapCancel: () => _setDown(false),
        child: PressState(
          down: _down,
          hover: _hover,
          scale: widget.scale,
          child: widget.child,
        ),
      ),
    );
  }
}

/// What the nearest [Pressable] (or a row that behaves like one) is doing
/// right now, for the [PressTarget] inside it.
class PressState extends InheritedWidget {
  const PressState({
    super.key,
    required this.down,
    required this.hover,
    this.scale = 0.96,
    required super.child,
  });

  final bool down;
  final bool hover;
  final double scale;

  static PressState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PressState>();

  @override
  bool updateShouldNotify(PressState old) =>
      down != old.down || hover != old.hover || scale != old.scale;
}

/// The part of a card that moves: gives a little under a press, lifts a
/// little under a mouse. Outside a [PressState] it is just its child.
class PressTarget extends StatelessWidget {
  const PressTarget({super.key, required this.child, this.radius});

  final Widget child;

  /// Corner of the shade drawn over it on hover, to match the cover's own.
  /// Null takes the look's card corner.
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final state = PressState.maybeOf(context);
    if (state == null) return child;
    final still = MediaQuery.disableAnimationsOf(context);
    final kind = Looks.current.kind;
    final scale = state.down
        ? state.scale
        : state.hover
        ? 1.03
        : 1.0;
    // Per room (mood board): Crayon wobbles, a little tilt that springs
    // back; Noir does not move at all, only the shade fades.
    final tilt = kind == LookKind.crayon && state.down ? -0.012 : 0.0;
    return AnimatedRotation(
      turns: still ? 0 : tilt,
      duration: still ? Duration.zero : const Duration(milliseconds: 160),
      curve: Curves.easeOutBack,
      child: AnimatedScale(
        // Someone who has asked the system for less motion has asked for this
        // too. The press still registers through the shade -- it just does not
        // move.
        scale: still || kind == LookKind.noir ? 1 : scale,
        duration: still ? Duration.zero : const Duration(milliseconds: 110),
        curve: kind == LookKind.crayon ? Curves.easeOutBack : Curves.easeOut,
        child: Stack(
          children: [
            child,
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: state.down ? 1 : (state.hover ? 0.5 : 0),
                  duration: const Duration(milliseconds: 110),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Tones.text.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(
                        radius ?? RadiusTokens.card,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A list row that answers like a card: its thumbnail gives and lifts, and
/// the row itself only takes a faint wash rather than flooding edge to edge.
///
/// Put a [PressTarget] around the row's picture.
class PressRow extends StatefulWidget {
  const PressRow({
    super.key,
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.onSecondaryTap,
    this.borderRadius,
  });

  final BorderRadius? borderRadius;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;
  final Widget child;

  @override
  State<PressRow> createState() => _PressRowState();
}

class _PressRowState extends State<PressRow> {
  bool _down = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onSecondaryTap: widget.onSecondaryTap,
      onHighlightChanged: (v) => setState(() => _down = v),
      onHover: (v) => setState(() => _hover = v),
      borderRadius:
          widget.borderRadius ?? BorderRadius.circular(RadiusTokens.control),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Tones.text.withValues(alpha: 0.04),
      hoverColor: Tones.text.withValues(alpha: 0.03),
      child: PressState(down: _down, hover: _hover, child: widget.child),
    );
  }
}
