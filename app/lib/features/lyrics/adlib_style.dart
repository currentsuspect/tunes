import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/lyrics/adlib_kinds.dart';
import '../../core/lyrics/adlib_motion.dart';

/// Each kind of ad-lib in its own voice (adlib_kinds.dart): a growl heavy,
/// an effect bold in the song's colour, a whisper light and spaced out.
/// [base] is the line's own style; ad-libs sit a size below it.
TextStyle adlibTextStyle(TextStyle base, AdlibKind kind, Color accent) {
  final size = (base.fontSize ?? 20) * 0.72;
  return switch (kind) {
    AdlibKind.growl => base.copyWith(
      fontSize: size * 1.06,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
    ),
    AdlibKind.effect => base.copyWith(
      fontSize: size * 1.08,
      fontWeight: FontWeight.w800,
      color: accent,
    ),
    AdlibKind.boom => base.copyWith(
      fontSize: size * 1.2,
      fontWeight: FontWeight.w900,
      color: accent,
      letterSpacing: 0.5,
    ),
    AdlibKind.whisper => base.copyWith(
      fontSize: size * 0.92,
      fontWeight: FontWeight.w300,
      fontStyle: FontStyle.italic,
      letterSpacing: 1.8,
    ),
    AdlibKind.hype => base.copyWith(
      fontSize: size,
      fontWeight: FontWeight.w700,
    ),
    AdlibKind.stutter => base.copyWith(
      fontSize: size,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
    ),
    // A producer's tag, set like a label on the record.
    AdlibKind.tag => base.copyWith(
      fontSize: size * 0.7,
      fontWeight: FontWeight.w700,
      letterSpacing: 3,
      fontStyle: FontStyle.normal,
    ),
    _ => base.copyWith(fontSize: size, fontStyle: FontStyle.italic),
  };
}

/// An ad-lib's motion (adlib_motion.dart): offset, tilt, pop, stretch, fade,
/// and an echo's trailing copies. Transforms only, so a line never reflows.
class AdlibFx extends StatelessWidget {
  const AdlibFx({
    super.key,
    required this.look,
    required this.child,
    this.burstColor,
    this.trailLeft = false,
  });

  /// Which way an echo trails: away from the edge the ad-lib sits against.
  final bool trailLeft;

  final AdlibLook look;
  final Widget child;

  /// A boom's burst colour, the song's accent.
  final Color? burstColor;

  @override
  Widget build(BuildContext context) {
    Widget out = Transform(
      alignment: Alignment.bottomCenter,
      transform: Matrix4.identity()
        ..translateByDouble(look.dx, look.dy, 0, 1)
        ..rotateZ(look.rotate)
        ..scaleByDouble(look.scale * look.stretch, look.scale, 1, 1),
      child: child,
    );
    if (look.burst > 0) {
      // Behind the word, centred on it, flying out as it grows.
      out = CustomPaint(
        painter: _Burst(look.burst, burstColor ?? Colors.white, look.scale),
        child: out,
      );
    }
    if (look.opacity < 1) out = Opacity(opacity: look.opacity, child: out);
    if (look.ghosts > 0 && look.ghostOpacity > 0) {
      out = Stack(
        clipBehavior: Clip.none,
        children: [
          for (var g = look.ghosts; g >= 1; g--)
            // Each copy past the end of the one before, smaller and
            // fainter: a delay trailing off, not a smudge over the word.
            Positioned.fill(
              child: FractionalTranslation(
                translation: Offset((trailLeft ? -1.04 : 1.04) * g, 0),
                child: Transform.scale(
                  scale: 1 - 0.14 * g,
                  alignment: trailLeft
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Opacity(
                    opacity: look.ghostOpacity / g,
                    child: IgnorePointer(child: child),
                  ),
                ),
              ),
            ),
          out,
        ],
      );
    }
    return out;
  }
}

/// A line-timed line's ad-libs, each group in its kind's voice, at rest.
Widget adlibRow(
  List<String> tokens,
  TextStyle base,
  Color accent, {
  WrapAlignment alignment = WrapAlignment.end,
  String main = '',
}) {
  final mask = List.filled(tokens.length, true);
  final groups = adlibGroups(tokens, mask, mainText: main);
  return Wrap(
    alignment: alignment,
    spacing: 10,
    runSpacing: 4,
    children: [for (final g in groups) adlibChip(tokens, g, base, accent)],
  );
}

/// One ad-lib group at rest; a producer's tag drawn as an outlined badge.
Widget adlibChip(
  List<String> tokens,
  ({List<int> words, AdlibKind kind}) g,
  TextStyle base,
  Color accent, {
  AdlibLook? look,
  bool trailLeft = false,
}) {
  final text = [for (final i in g.words) tokens[i]]
      .join(' ')
      .replaceAll(RegExp(r'[)\]][,.;:!?]+$'), ')')
      .replaceAll('[', '(')
      .replaceAll(']', ')');
  final style = adlibTextStyle(base, g.kind, accent);
  if (g.kind == AdlibKind.tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(
          color: (style.color ?? accent).withValues(alpha: 0.6),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text.replaceAll(RegExp(r'[()\[\]]'), '').toUpperCase(),
        style: style,
      ),
    );
  }
  return AdlibFx(
    burstColor: accent,
    trailLeft: trailLeft,
    look: look ?? restingLook(g.kind),
    child: Text(text, style: style),
  );
}

/// A boom's burst: short lines thrown out from the word's centre.
class _Burst extends CustomPainter {
  _Burst(this.progress, this.color, this.scale);

  final double progress;
  final Color color;

  /// How large the word is drawn right now; it grows from its bottom centre.
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    // Rays from just outside the word's edge, flying further out as they
    // fade: an ellipse around the word, not lines through it.
    final rx = size.width * scale / 2;
    final ry = size.height * scale / 2;
    final c = Offset(size.width / 2, size.height - ry);
    final paint = Paint()
      ..color = color.withValues(alpha: (1 - progress) * 0.95)
      ..strokeWidth = 3.5 * (1 - progress) + 1
      ..strokeCap = StrokeCap.round;
    const rays = 12;
    for (var i = 0; i < rays; i++) {
      final a = i / rays * 2 * math.pi + 0.26;
      final dir = Offset(math.cos(a), math.sin(a));
      Offset at(double pad) =>
          c + Offset(dir.dx * (rx + pad), dir.dy * (ry + pad * 0.7));
      canvas.drawLine(at(4 + 18 * progress), at(12 + 34 * progress), paint);
    }
  }

  @override
  bool shouldRepaint(_Burst old) =>
      old.progress != progress || old.scale != scale;
}
