import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Crayon's hand-drawn marks (design approved 23 Oct): a tick, a cloud, a
/// screen, a phone, an arrow, drawn as wobbly ink strokes rather than the
/// Material set, which reads as a different app on paper. Painted from fixed
/// paths, so they cost what an icon costs.
enum CrayonMark { tick, cloud, cloudOff, computer, phone }

/// One mark at [size], in [color].
class CrayonMarkIcon extends StatelessWidget {
  const CrayonMarkIcon(
    this.mark, {
    super.key,
    this.size = 18,
    required this.color,
  });

  final CrayonMark mark;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _MarkPainter(mark, color)),
  );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.mark, this.color);

  final CrayonMark mark;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 20-unit square.
    canvas.scale(size.width / 20);
    final ink = _stroke(color, mark == CrayonMark.tick ? 2.8 : 2.3);
    switch (mark) {
      case CrayonMark.tick:
        canvas.drawPath(_tick20, ink);
      case CrayonMark.cloud:
        canvas.drawPath(_cloud, ink);
      case CrayonMark.cloudOff:
        canvas.drawPath(_cloud, ink);
        canvas.drawLine(const Offset(2.6, 2.8), const Offset(18, 17.6), ink);
      case CrayonMark.computer:
        canvas.drawPath(
          Path()
            ..moveTo(3, 4.6)
            ..cubicTo(7.6, 4.3, 12.4, 4.4, 17, 4.5)
            ..cubicTo(17.1, 7.5, 17, 10.5, 17.1, 13.4)
            ..cubicTo(12.4, 13.6, 7.6, 13.5, 3, 13.4)
            ..cubicTo(2.9, 10.5, 3, 7.5, 3, 4.6)
            ..close()
            ..moveTo(7, 16.9)
            ..lineTo(13, 17.1),
          ink,
        );
      case CrayonMark.phone:
        canvas.drawRRect(
          RRect.fromLTRBR(6, 2.4, 14.2, 17.6, const Radius.circular(2.2)),
          ink,
        );
        canvas.drawLine(const Offset(9, 14.6), const Offset(11.2, 14.6), ink);
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.mark != mark || old.color != color;
}

/// The download control's faces in Crayon, on a wobbly drawn circle:
/// an arrow to fetch, a green ring filling while it arrives, a coloured-in
/// circle with a tick once it is held, a curl to retry.
enum CrayonDownloadState { idle, queued, running, held, failed }

class CrayonDownloadFace extends StatelessWidget {
  const CrayonDownloadFace({
    super.key,
    required this.state,
    this.progress,
    this.dim = false,
    this.size = 28,
  });

  final CrayonDownloadState state;

  /// 0..1 while running; null when the size is unknown.
  final double? progress;

  /// Offline and not held: drawn faint, because it cannot be tapped.
  final bool dim;
  final double size;

  @override
  Widget build(BuildContext context) {
    final look = Looks.current;
    final paint = CustomPaint(
      painter: _FacePainter(
        state: state,
        progress: progress,
        ink: dim ? Tones.hairline : Tones.text,
        paper: Tones.surfaceRaised,
        held: Tones.held,
        // A deeper green for the tick on paper so it still reads against
        // the pale fill; the chalkboard's green is bright enough as it is.
        tick: look.isDark
            ? Tones.held
            : Color.lerp(Tones.held, Tones.text, 0.3)!,
        warn: Tones.warn,
      ),
    );
    final face = SizedBox.square(dimension: size, child: paint);
    if (state == CrayonDownloadState.running && progress == null) {
      // Size unknown: the partial ring turns rather than fills.
      return _Turning(child: face);
    }
    return face;
  }
}

class _FacePainter extends CustomPainter {
  _FacePainter({
    required this.state,
    required this.progress,
    required this.ink,
    required this.paper,
    required this.held,
    required this.tick,
    required this.warn,
  });

  final CrayonDownloadState state;
  final double? progress;
  final Color ink;
  final Color paper;
  final Color held;
  final Color tick;
  final Color warn;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 40-unit square.
    canvas.scale(size.width / 40);
    if (state == CrayonDownloadState.held) {
      // Coloured in, a little off the line, the way crayon goes.
      canvas.save();
      canvas.translate(1.4, 1.4);
      canvas.drawPath(_ring, Paint()..color = held.withValues(alpha: 0.32));
      canvas.restore();
    } else {
      canvas.drawPath(_ring, Paint()..color = paper);
    }
    canvas.drawPath(_ring, _stroke(ink, 2.4));
    switch (state) {
      case CrayonDownloadState.idle:
      case CrayonDownloadState.queued:
        canvas.drawPath(_arrow, _stroke(ink, 2.6));
      case CrayonDownloadState.running:
        final p = progress ?? 0.25;
        canvas.drawArc(
          Rect.fromCircle(center: const Offset(20, 20), radius: 11),
          -math.pi / 2,
          2 * math.pi * p.clamp(0.02, 1.0),
          false,
          _stroke(held, 5),
        );
      case CrayonDownloadState.held:
        canvas.drawPath(_tick40, _stroke(tick, 3.2));
      case CrayonDownloadState.failed:
        final curl = _stroke(warn, 2.8);
        canvas.drawArc(
          Rect.fromCircle(center: const Offset(20, 20.5), radius: 8.5),
          -math.pi * 0.35,
          math.pi * 1.6,
          false,
          curl,
        );
        canvas.drawPath(
          Path()
            ..moveTo(23.4, 8.6)
            ..lineTo(27.4, 12.6)
            ..lineTo(22.2, 14.2),
          curl,
        );
    }
  }

  @override
  bool shouldRepaint(_FacePainter old) =>
      old.state != state ||
      old.progress != progress ||
      old.ink != ink ||
      old.paper != paper ||
      old.held != held ||
      old.tick != tick ||
      old.warn != warn;
}

class _Turning extends StatefulWidget {
  const _Turning({required this.child});
  final Widget child;

  @override
  State<_Turning> createState() => _TurningState();
}

class _TurningState extends State<_Turning>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return RotationTransition(turns: _c, child: widget.child);
  }
}

Paint _stroke(Color c, double w) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

// 20-unit tick: a short dip, then a long confident stroke up.
final Path _tick20 = Path()
  ..moveTo(3.2, 10.4)
  ..cubicTo(4.6, 11.5, 5.9, 12.8, 7.2, 14.3)
  ..cubicTo(9.8, 10.0, 12.6, 6.7, 16.6, 3.7);

final Path _cloud = Path()
  ..moveTo(6, 15.5)
  ..cubicTo(3.4, 15.6, 1.8, 13.9, 2, 11.9)
  ..cubicTo(2.2, 9.9, 3.9, 8.7, 5.8, 8.9)
  ..cubicTo(6.2, 5.7, 8.6, 3.7, 11.4, 3.9)
  ..cubicTo(14.0, 4.1, 15.8, 5.9, 16.2, 8.3)
  ..cubicTo(18.6, 8.1, 20.3, 9.7, 20.2, 11.9)
  ..cubicTo(20.1, 14.1, 18.4, 15.5, 16.2, 15.5)
  ..close();

// 40-unit circle, drawn by hand: never quite round, never quite closed flat.
final Path _ring = Path()
  ..moveTo(20, 3.6)
  ..cubicTo(29.6, 3.7, 36.6, 10.6, 36, 20.2)
  ..cubicTo(35.5, 29.4, 28.4, 36.5, 19.1, 36.0)
  ..cubicTo(10, 35.5, 3.3, 28.4, 3.8, 19.2)
  ..cubicTo(4.3, 10, 10.7, 3.5, 20, 3.6)
  ..close();

final Path _arrow = Path()
  ..moveTo(20, 11.5)
  ..cubicTo(19.8, 15.9, 20.1, 20.1, 20, 24.9)
  ..moveTo(14.6, 20.4)
  ..cubicTo(16.5, 22.0, 18.2, 23.6, 20, 25.6)
  ..cubicTo(21.8, 23.6, 23.6, 22.0, 25.4, 20.4);

final Path _tick40 = Path()
  ..moveTo(12.2, 20.6)
  ..cubicTo(14.0, 22.0, 15.6, 23.6, 17.2, 25.5)
  ..cubicTo(20.4, 20.2, 23.6, 16.3, 28.0, 12.9);
