import 'dart:math';
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import '../theme/looks.dart';

/// The parts of a theme that are more than colour (docs mood board, 9 Oct,
/// "what changes"): Crayon's squiggles, paper and crayon-stroke progress,
/// Noir's grain and gold bead. Each is cheap: painted once and cached, no
/// blur, no per-frame work unless it moves.

/// A hand-drawn wavy underline (Crayon's section headings).
class CrayonSquiggle extends StatelessWidget {
  const CrayonSquiggle({super.key, required this.color, this.height = 9});

  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(painter: _SquigglePainter(color)),
  );
}

class _SquigglePainter extends CustomPainter {
  _SquigglePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final path = Path()..moveTo(1, mid);
    const step = 14.0;
    var x = 1.0;
    var up = true;
    while (x < size.width - 1) {
      final next = min(x + step, size.width - 1);
      path.quadraticBezierTo(
        (x + next) / 2,
        up ? mid - size.height * 0.45 : mid + size.height * 0.45,
        next,
        mid,
      );
      x = next;
      up = !up;
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SquigglePainter old) => old.color != color;
}

/// The page's texture, over everything, never in the way: Crayon's faint dot
/// grid (paper), Noir's film grain. Room has none. Painted once into a
/// picture and cached; it never repaints while you scroll.
class LookGround extends StatelessWidget {
  const LookGround({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final look = Looks.current;
    if (look.kind == LookKind.room) return child;
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: look.kind == LookKind.crayon
                    ? _DotsPainter(look.text.withValues(alpha: 0.10))
                    : _GrainPainter(look.isDark),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DotsPainter extends CustomPainter {
  _DotsPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    const gap = 14.0;
    final points = <Offset>[
      for (var y = gap / 2; y < size.height; y += gap)
        for (var x = gap / 2; x < size.width; x += gap) Offset(x, y),
    ];
    canvas.drawPoints(
      PointMode.points,
      points,
      p
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.color != color;
}

class _GrainPainter extends CustomPainter {
  _GrainPainter(this.dark);
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    // Fixed seed: the same grain every frame, so it reads as film, not noise.
    final r = Random(7);
    final light = Paint()
      ..color = (dark ? Colors.white : Colors.black).withValues(alpha: 0.05)
      ..strokeWidth = 1;
    final n = (size.width * size.height / 90).round();
    canvas.drawPoints(PointMode.points, [
      for (var i = 0; i < n; i++)
        Offset(r.nextDouble() * size.width, r.nextDouble() * size.height),
    ], light);
  }

  @override
  bool shouldRepaint(_GrainPainter old) => old.dark != dark;
}

/// The progress line for each room: Crayon draws a thick wavy crayon
/// stroke, Noir a 1px gold line with a bead, Room keeps its thin bar.
class LookTrackShape extends RoundedRectSliderTrackShape {
  const LookTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final look = Looks.current;
    if (look.kind == LookKind.room) {
      return super.paint(
        context,
        offset,
        parentBox: parentBox,
        sliderTheme: sliderTheme,
        enableAnimation: enableAnimation,
        textDirection: textDirection,
        thumbCenter: thumbCenter,
        secondaryOffset: secondaryOffset,
        isDiscrete: isDiscrete,
        isEnabled: isEnabled,
        additionalActiveTrackHeight: additionalActiveTrackHeight,
      );
    }
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final canvas = context.canvas;
    final active = sliderTheme.activeTrackColor ?? look.primary;
    final rail = sliderTheme.inactiveTrackColor ?? look.hairline;
    if (look.kind == LookKind.noir) {
      final y = rect.center.dy;
      canvas.drawLine(
        Offset(rect.left, y),
        Offset(rect.right, y),
        Paint()
          ..color = rail
          ..strokeWidth = 1,
      );
      canvas.drawLine(
        Offset(rect.left, y),
        Offset(thumbCenter.dx, y),
        Paint()
          ..color = look.primary
          ..strokeWidth = 1,
      );
      canvas.drawCircle(
        Offset(thumbCenter.dx, y),
        3.5,
        Paint()..color = look.primary,
      );
      return;
    }
    // Crayon: a wavy stroke across the page, the played part in colour.
    Path wave(double from, double to) {
      final y = rect.center.dy;
      final p = Path()..moveTo(from, y);
      const step = 22.0;
      var x = from;
      var up = true;
      while (x < to) {
        final next = min(x + step, to);
        p.quadraticBezierTo((x + next) / 2, y + (up ? -2.5 : 2.5), next, y);
        x = next;
        up = !up;
      }
      return p;
    }

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      wave(rect.left, rect.right),
      stroke..color = rail.withValues(alpha: 0.35),
    );
    if (thumbCenter.dx > rect.left) {
      canvas.drawPath(wave(rect.left, thumbCenter.dx), stroke..color = active);
    }
  }
}

/// A burst of crayon confetti, once, when something is liked in Crayon.
/// Call [ConfettiBurst.show] with the tapped widget's context.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key, required this.origin});

  final Offset origin;

  static void show(BuildContext context) {
    if (Looks.current.kind != LookKind.crayon) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.maybeOf(context);
    if (box == null || overlay == null) return;
    final origin = box.localToGlobal(box.size.center(Offset.zero));
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => ConfettiBurst(key: UniqueKey(), origin: origin),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(milliseconds: 900), entry.remove);
  }

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: _c,
      builder: (_, _) => CustomPaint(
        size: Size.infinite,
        painter: _ConfettiPainter(widget.origin, _c.value),
      ),
    ),
  );
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.origin, this.t);
  final Offset origin;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Random(3);
    final colors = Looks.current.crayons;
    final ease = Curves.easeOutCubic.transform(t);
    for (var i = 0; i < 18; i++) {
      final angle = r.nextDouble() * pi * 2;
      final dist = 30 + r.nextDouble() * 50;
      final pos =
          origin +
          Offset(cos(angle), sin(angle)) * dist * ease +
          Offset(0, 40 * t * t);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(angle + t * 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-4, -2, 8, 4),
          const Radius.circular(2),
        ),
        Paint()..color = colors[i % colors.length].withValues(alpha: 1 - t),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

/// A strip of masking tape in a crayon colour, holding a Crayon cover into
/// the notebook. Translucent, so the cover's corner shows through it, with
/// torn ends drawn as faint dotted edges.
class CrayonTape extends StatelessWidget {
  const CrayonTape({
    super.key,
    required this.color,
    required this.angle,
    this.length = 74,
  });

  final Color color;
  final double angle;
  final double length;

  @override
  Widget build(BuildContext context) {
    final dark = Looks.current.isDark;
    return IgnorePointer(
      child: Transform.rotate(
        angle: angle,
        child: CustomPaint(
          size: Size(length, length * 0.32),
          painter: _TapePainter(
            color.withValues(alpha: dark ? 0.7 : 0.78),
            (dark ? const Color(0xFF1C1A2B) : const Color(0xFF22201C))
                .withValues(alpha: 0.28),
          ),
        ),
      ),
    );
  }
}

class _TapePainter extends CustomPainter {
  _TapePainter(this.fill, this.edge);
  final Color fill;
  final Color edge;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = fill);
    final dots = Paint()
      ..color = edge
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var y = 2.0; y < size.height; y += 4) {
      canvas.drawPoints(PointMode.points, [
        Offset(1, y),
        Offset(size.width - 1, y),
      ], dots);
    }
  }

  @override
  bool shouldRepaint(_TapePainter old) => old.fill != fill || old.edge != edge;
}
