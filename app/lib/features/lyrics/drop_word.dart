import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../core/lyrics/drops.dart';
import 'adlib_style.dart';

/// The ad-lib on a drop (drops.dart), drawn over the sheet: it rises from
/// its line to the middle, growing until it is wider than any line, then
/// shrinks back to its place a step per 808 hit, squashing as each lands.
class DropWord extends StatelessWidget {
  const DropWord({
    super.key,
    required this.frame,
    required this.from,
    required this.base,
    required this.accent,
  });

  final DropFrame frame;

  /// Where its line sits on the sheet, or null when it is off screen.
  final Offset? from;
  final TextStyle base;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final m = frame.moment;
    if (m == null || m.kind != DropKind.grow || frame.wordOpacity <= 0) {
      return const SizedBox.shrink();
    }
    final style = adlibTextStyle(base, m.adlib, accent).copyWith(
      fontWeight: FontWeight.w800,
      shadows: [Shadow(color: accent.withValues(alpha: 0.6), blurRadius: 18)],
    );
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        final painter = TextPainter(
          text: TextSpan(text: m.text, style: style),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        final size = painter.size;
        painter.dispose();
        // Big enough to crowd every line out, never off the sheet.
        final most = math.max(
          1.0,
          math.min(6.0, math.min(0.92 * w / size.width, 0.4 * h / size.height)),
        );
        final g = frame.grow;
        final p = frame.punch;
        final scale = lerpDouble(1, most, g)!;
        // To the middle early on; once the 808 is back, home to its line
        // step by step, see-through as it goes so the line being sung reads
        // through it.
        final back = frame.revealFrom != null;
        final travel = back
            ? g
            : Curves.easeOut.transform(math.min(1, g * 1.6));
        final opacity = back
            ? frame.wordOpacity * (0.25 + 0.75 * g)
            : frame.wordOpacity;
        final start = from ?? Offset(w / 2, h * 0.45);
        final at = Offset.lerp(start, Offset(w / 2, h * 0.45), travel)!;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: at.dx - size.width / 2,
              top: at.dy - size.height / 2,
              width: size.width,
              height: size.height,
              child: Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.diagonal3Values(
                    scale * (1 + 0.14 * p),
                    scale * (1 - 0.1 * p),
                    1,
                  ),
                  child: Text(
                    m.text,
                    style: style,
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
