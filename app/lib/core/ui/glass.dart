import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/looks.dart';

/// Where the light catches Glass's panes, as a horizontal position from -1
/// (left) to 1 (right). The shell moves it as the page scrolls, so every
/// pane's bright edge glides together, as light does across real glass when
/// what is under it moves. A notifier, not state: the edges repaint, nothing
/// rebuilds.
abstract final class GlassSheen {
  static final x = ValueNotifier<double>(-0.35);

  /// Called with a vertical scroll's offset. A slow sine, so a long read
  /// sweeps the light back and forth rather than pinning it at one end.
  static void follow(double pixels) => x.value = math.sin(pixels / 520) * 0.85;
}

/// Glass's one effect: a pane that frosts what is behind it.
///
/// Blur is the most expensive thing this app draws, so panes go only on what
/// floats -- the dock, sheets, Now Playing's backdrop -- never on rows in a
/// scrolling list, where a translucent fill ([glassDecoration] without the
/// blur) reads nearly the same and costs nothing.
///
/// The edge has a highlight that follows [GlassSheen], and the finger while
/// the pane is pressed, when it also swells a little ([pressable]).
class GlassPane extends StatefulWidget {
  const GlassPane({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.blur = 24,
    this.tint,
    this.backing,
    this.pressable = false,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blur;

  /// A dim layer under the frost, for panes that carry text over busy
  /// content: the blur alone leaves it too clear to read on. Changes fade,
  /// so a pane can thicken as content slides under it.
  final Color? backing;

  /// The record's colour, washed faintly into the pane.
  final Color? tint;

  /// Swells under the finger. Only for panes that are themselves a control
  /// (the dock's capsules); a sheet that swelled would read as broken.
  final bool pressable;

  @override
  State<GlassPane> createState() => _GlassPaneState();
}

class _GlassPaneState extends State<GlassPane> {
  /// The finger's position across the pane, -1 to 1, while it is down.
  final _touch = ValueNotifier<double?>(null);
  bool _down = false;

  @override
  void dispose() {
    _touch.dispose();
    super.dispose();
  }

  void _at(PointerEvent e) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.width == 0) return;
    _touch.value = (e.localPosition.dx / box.size.width * 2 - 1).clamp(-1, 1);
  }

  void _press(bool down) {
    if (widget.pressable && down != _down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final pane = ClipRRect(
      borderRadius: widget.borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur),
        child: AnimatedContainer(
          duration: still ? Duration.zero : const Duration(milliseconds: 260),
          color: widget.backing ?? Colors.transparent,
          child: DecoratedBox(
            decoration: glassDecoration(
              borderRadius: widget.borderRadius,
              tint: widget.tint,
              edge: false,
            ),
            position: DecorationPosition.background,
            child: CustomPaint(
              foregroundPainter: _EdgePainter(
                radius: widget.borderRadius,
                look: Looks.current,
                touch: _touch,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        _at(e);
        _press(true);
      },
      onPointerMove: _at,
      onPointerUp: (_) {
        _touch.value = null;
        _press(false);
      },
      onPointerCancel: (_) {
        _touch.value = null;
        _press(false);
      },
      child: AnimatedScale(
        scale: _down ? 1.02 : 1,
        duration: still ? Duration.zero : const Duration(milliseconds: 160),
        curve: Curves.easeOutBack,
        child: pane,
      ),
    );
  }
}

/// The pane's edge: a hairline in [TunesLook.glassEdge] that brightens
/// toward one point, the finger's while it is down and [GlassSheen]'s
/// otherwise. Brightest along the top, where light lands on glass.
class _EdgePainter extends CustomPainter {
  _EdgePainter({required this.radius, required this.look, required this.touch})
    : super(repaint: Listenable.merge([GlassSheen.x, touch]));

  final BorderRadius radius;
  final TunesLook look;
  final ValueNotifier<double?> touch;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect).deflate(0.5);
    final at = touch.value ?? GlassSheen.x.value;
    final edge = look.glassEdge;
    final hot = Colors.white.withValues(alpha: look.isDark ? 0.85 : 1);
    final centre = ((at + 1) / 2).clamp(0.0, 1.0);
    final spread = touch.value == null ? 0.28 : 0.18;
    final across = LinearGradient(
      colors: [edge, edge, hot, edge, edge],
      stops: [
        0,
        (centre - spread).clamp(0.0, 1.0),
        centre,
        (centre + spread).clamp(0.0, 1.0),
        1,
      ],
    );
    final top = Rect.fromLTRB(0, 0, size.width, size.height / 2);
    // Light comes from above: the travelling highlight is on the top half of
    // the edge, the bottom half a plain, dimmer line.
    canvas
      ..save()
      ..clipRect(top)
      ..drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..shader = across.createShader(rect),
      )
      ..restore()
      ..save()
      ..clipRect(Rect.fromLTRB(0, size.height / 2, size.width, size.height))
      ..drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = edge.withValues(alpha: edge.a * 0.5),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_EdgePainter old) =>
      old.radius != radius || old.look != look || old.touch != touch;
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
