import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/lyrics/word_fx_motion.dart';

/// Draws a vocabulary word's effect (word_fx_motion.dart) around [child]:
/// a tint and a halo in the word's colour, haze, a travelling glint, a white
/// flash, a drop falling from it. Transforms and overlays only, so the line
/// never reflows under it.
class WordFxBox extends StatelessWidget {
  const WordFxBox({super.key, required this.look, required this.child});

  final WordFxLook look;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l = look;
    if (identical(l, WordFxLook.still)) return child;
    final tint = l.tint;
    Widget word = child;
    if (tint != null && l.tintAmount > 0) {
      // The word recoloured, laid over itself: srcIn keeps the glyphs' shape.
      word = Stack(
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: l.tintAmount.clamp(0.0, 1.0),
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
                  child: child,
                ),
              ),
            ),
          ),
        ],
      );
    }
    final glowColor = l.flash > 0 ? Colors.white : tint;
    final glow = math.max(l.glow, l.flash);
    final layers = <Widget>[
      if (glowColor != null && glow > 0)
        // A blurred copy behind, in the word's colour: the halo.
        Positioned.fill(
          child: IgnorePointer(
            child: Opacity(
              opacity: (0.75 * glow).clamp(0.0, 1.0),
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: 6 + 6 * glow,
                  sigmaY: 6 + 6 * glow,
                ),
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(glowColor, BlendMode.srcIn),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      if (l.blur > 0.05)
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: l.blur, sigmaY: l.blur * 0.6),
          child: word,
        )
      else
        word,
      if (l.sparkle >= 0)
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _Glint(l.sparkle, tint ?? Colors.white),
            ),
          ),
        ),
      if (l.drop >= 0 && l.drop < 1)
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _Drop(l.drop, tint ?? Colors.white)),
          ),
        ),
    ];
    return Transform(
      alignment: Alignment.bottomCenter,
      transform: Matrix4.identity()
        ..translateByDouble(l.dx, l.dy, 0, 1)
        ..scaleByDouble(l.scale * l.stretch, l.scale, 1, 1),
      child: Stack(clipBehavior: Clip.none, children: layers),
    );
  }
}

/// A four-pointed glint crossing the word left to right.
class _Glint extends CustomPainter {
  _Glint(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width * (0.1 + 0.8 * t);
    final y = size.height * (0.3 + 0.15 * math.sin(t * math.pi * 2));
    final r = 3 + 4 * math.sin(t * math.pi);
    final paint = Paint()
      ..color = Color.lerp(
        color,
        Colors.white,
        0.5,
      )!.withValues(alpha: 0.9 * math.sin(t * math.pi))
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(x - r, y), Offset(x + r, y), paint);
    canvas.drawLine(Offset(x, y - r * 1.4), Offset(x, y + r * 1.4), paint);
    canvas.drawCircle(Offset(x, y), 1.4, paint);
  }

  @override
  bool shouldRepaint(_Glint old) => old.t != t;
}

/// A drop falling from under the word's end, fading as it goes.
class _Drop extends CustomPainter {
  _Drop(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width * 0.82;
    final y = size.height * 0.85 + 22 * t * t;
    final paint = Paint()..color = color.withValues(alpha: 0.9 * (1 - t));
    final path = Path()
      ..moveTo(x, y - 5)
      ..quadraticBezierTo(x + 3.2, y, x, y + 2.6)
      ..quadraticBezierTo(x - 3.2, y, x, y - 5);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_Drop old) => old.t != t;
}
