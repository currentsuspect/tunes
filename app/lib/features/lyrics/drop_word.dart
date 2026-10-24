import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../core/lyrics/drops.dart';
import 'adlib_style.dart';

/// The ad-lib on a drop (drops.dart), drawn over the sheet: it rises from
/// its line to the middle, growing until it is wider than any line, then
/// shrinks back to its place a step per 808 hit, squashing as each lands.
///
/// Cheap per frame: the word is measured once per moment and drawn once, at
/// its largest, behind a RepaintBoundary; a frame only moves and scales
/// that picture down. Laying it out and drawing it (glow included) at up to
/// six times its size every frame made the moment stutter on a phone.
class DropWord extends StatefulWidget {
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
  State<DropWord> createState() => _DropWordState();
}

class _DropWordState extends State<DropWord> {
  /// The word as drawn at its largest, for the moment and sheet size it was
  /// worked out for.
  ({DropMoment moment, Size box, TextStyle style, Size size, double most})?
  _cache;

  ({TextStyle style, Size size, double most}) _measure(DropMoment m, Size box) {
    final c = _cache;
    if (c != null && identical(c.moment, m) && c.box == box) {
      return (style: c.style, size: c.size, most: c.most);
    }
    final rest = adlibTextStyle(
      widget.base,
      m.adlib,
      widget.accent,
    ).copyWith(fontWeight: FontWeight.w800);
    final one = _layout(m.text, rest);
    // Big enough to crowd every line out, never off the sheet.
    final most = math.max(
      1.0,
      math.min(
        6.0,
        math.min(0.92 * box.width / one.width, 0.4 * box.height / one.height),
      ),
    );
    final style = rest.copyWith(
      fontSize: (rest.fontSize ?? 16) * most,
      shadows: [
        Shadow(
          color: widget.accent.withValues(alpha: 0.6),
          blurRadius: 18 * most,
        ),
      ],
    );
    final size = _layout(m.text, style);
    _cache = (moment: m, box: box, style: style, size: size, most: most);
    return (style: style, size: size, most: most);
  }

  static Size _layout(String text, TextStyle style) {
    final p = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final size = p.size;
    p.dispose();
    return size;
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.frame;
    final m = f.moment;
    if (m == null || m.kind != DropKind.grow || f.wordOpacity <= 0) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        final big = _measure(m, Size(w, h));
        final g = f.grow;
        final p = f.punch;
        // Drawn at its largest; 1/most is its own size.
        final scale = lerpDouble(1, big.most, g)! / big.most;
        // To the middle early on; once the 808 is back, home to its line
        // step by step, see-through as it goes so the line being sung reads
        // through it.
        final back = f.revealFrom != null;
        final travel = back
            ? g
            : Curves.easeOut.transform(math.min(1, g * 1.6));
        final opacity = back
            ? f.wordOpacity * (0.25 + 0.75 * g)
            : f.wordOpacity;
        final start = widget.from ?? Offset(w / 2, h * 0.45);
        final at = Offset.lerp(start, Offset(w / 2, h * 0.45), travel)!;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: at.dx - big.size.width / 2,
              top: at.dy - big.size.height / 2,
              width: big.size.width,
              height: big.size.height,
              child: Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.diagonal3Values(
                    scale * (1 + 0.14 * p),
                    scale * (1 - 0.1 * p),
                    1,
                  ),
                  child: RepaintBoundary(
                    child: Text(
                      m.text,
                      style: big.style,
                      maxLines: 1,
                      softWrap: false,
                    ),
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
