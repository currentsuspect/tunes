import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/looks.dart';

/// Glass's one effect: a pane that frosts what is behind it.
///
/// Blur is the most expensive thing this app draws, so panes go only on what
/// floats -- the dock, sheets, Now Playing's backdrop -- never on rows in a
/// scrolling list, where a translucent fill ([glassDecoration] without the
/// blur) reads nearly the same and costs nothing.
class GlassPane extends StatelessWidget {
  const GlassPane({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.blur = 24,
    this.tint,
    this.backing,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blur;

  /// A dim layer under the frost, for panes that carry body text over busy
  /// content (sheets): the blur alone leaves it too clear to read on.
  final Color? backing;

  /// The record's colour, washed faintly into the pane.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: ColoredBox(
          color: backing ?? Colors.transparent,
          child: DecoratedBox(
            decoration: glassDecoration(borderRadius: borderRadius, tint: tint),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The pane's fill and edge without the blur, for things that sit on a pane
/// already (a blur inside a blur costs twice and shows nothing new) or in a
/// list.
BoxDecoration glassDecoration({
  BorderRadius borderRadius = BorderRadius.zero,
  Color? tint,
  bool edge = true,
}) {
  final look = Looks.current;
  final fill = look.glassFill;
  return BoxDecoration(
    borderRadius: borderRadius,
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        if (tint == null)
          fill[0]
        else
          Color.alphaBlend(tint.withValues(alpha: 0.10), fill[0]),
        fill[1],
      ],
    ),
    border: edge ? Border.all(color: look.glassEdge) : null,
  );
}

/// A bottom sheet's background: [Tones.surface] in every look but Glass,
/// where the sheet is clear and [GlassSheet] frosts it.
Color sheetBackground() => Looks.current.kind == LookKind.glass
    ? Colors.transparent
    : Looks.current.surface;

/// A bottom sheet's body, frosted in Glass and unchanged in every other look.
/// Pair with [sheetBackground] on the `showModalBottomSheet` call.
class GlassSheet extends StatelessWidget {
  const GlassSheet({super.key, required this.radius, required this.child});

  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final look = Looks.current;
    if (look.kind != LookKind.glass) return child;
    return GlassPane(
      borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
      blur: 30,
      backing: look.base.withValues(alpha: look.isDark ? 0.62 : 0.5),
      child: child,
    );
  }
}

/// The light in a Glass room: two soft pools, the accent's top right and a
/// cooler one bottom left, laid over every route like Crayon's paper and
/// Noir's grain. Painted once and cached; it never repaints while you scroll.
class GlassLight extends StatelessWidget {
  const GlassLight({super.key});

  @override
  Widget build(BuildContext context) {
    final look = Looks.current;
    final a = look.isDark ? 0.16 : 0.12;
    return IgnorePointer(
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.9, -0.85),
                  radius: 0.9,
                  colors: [
                    look.primary.withValues(alpha: a),
                    look.primary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.95, 0.75),
                  radius: 0.85,
                  colors: [
                    const Color(0xFF8A7CF0).withValues(alpha: a * 0.8),
                    const Color(0xFF8A7CF0).withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
