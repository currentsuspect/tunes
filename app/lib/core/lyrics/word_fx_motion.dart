/// How a vocabulary word (word_fx.dart) moves while it is sung: from its own
/// start and end and the playhead, like word_motion.dart. Every effect
/// builds while the word is sung and settles within a third of a second of
/// its end, so it reads as the word, not as decoration.
library;

import 'dart:math' as math;
import 'dart:ui' show Color;

import 'word_fx.dart';

class WordFxLook {
  const WordFxLook({
    this.dx = 0,
    this.dy = 0,
    this.scale = 1,
    this.stretch = 1,
    this.tint,
    this.tintAmount = 0,
    this.glow = 0,
    this.blur = 0,
    this.sparkle = -1,
    this.flash = 0,
    this.drop = -1,
  });

  final double dx;
  final double dy;
  final double scale;

  /// Horizontal stretch.
  final double stretch;

  /// The colour the word turns, and how far, 0 to 1.
  final Color? tint;
  final double tintAmount;

  /// A soft halo in the tint, 0 to 1.
  final double glow;

  /// Gaussian blur in logical pixels, for haze.
  final double blur;

  /// A glint travelling across the word, 0 to 1, or below 0 for none.
  final double sparkle;

  /// A white flash, 0 to 1.
  final double flash;

  /// A drop falling from the word's end, 0 to 1, or below 0 for none.
  final double drop;

  static const still = WordFxLook();
}

const _ice = Color(0xFFB8E6FF);
const _gold = Color(0xFFFFC94D);
const _green = Color(0xFF6DFF8F);
const _fire = Color(0xFFFF8A3D);
const _blood = Color(0xFFFF4D5E);
const _rain = Color(0xFF8FC8FF);
const _heart = Color(0xFFFF6B8B);

double _c(double v) => v.clamp(0.0, 1.0);
double _out(double t) => 1 - math.pow(1 - _c(t), 3).toDouble();

WordFxLook wordFxLook(
  WordFx fx, {
  required Duration start,
  required Duration end,
  required Duration position,
}) {
  final t = (position - start).inMilliseconds.toDouble();
  if (t < 0) return WordFxLook.still;
  final dur = math.max(120, (end - start).inMilliseconds).toDouble();
  final after = (position - end).inMilliseconds.toDouble();
  if (after > 320) return WordFxLook.still;
  // 1 while sung (once in), easing to 0 over the 320 ms after its end.
  final on = after < 0 ? _out(t / 120) : 1 - _out(after / 320);
  final p = _c(t / dur);
  switch (fx) {
    case WordFx.frost:
      return WordFxLook(
        tint: _ice,
        tintAmount: 0.85 * on,
        glow: 0.45 * on,
        sparkle: p,
      );
    case WordFx.sparkle:
      return WordFxLook(
        tint: const Color(0xFFFFFFFF),
        tintAmount: 0.4 * on,
        glow: 0.5 * on,
        sparkle: (t / 450) % 1,
      );
    case WordFx.gold:
      return WordFxLook(
        tint: _gold,
        tintAmount: 0.9 * on,
        glow: 0.5 * on,
        sparkle: p,
      );
    case WordFx.cash:
      return WordFxLook(
        tint: _green,
        tintAmount: 0.85 * on,
        glow: 0.4 * on,
        dy: -4 * on,
        flash: t < 160 ? 1 - t / 160 : 0,
      );
    case WordFx.flame:
      final flicker = 0.75 + 0.25 * math.sin(t / 45) * math.sin(t / 73);
      return WordFxLook(
        tint: _fire,
        tintAmount: 0.85 * on,
        glow: 0.7 * on * flicker,
        dy: -1.2 * math.sin(t / 60) * on,
      );
    case WordFx.haze:
      return WordFxLook(
        blur: 1.8 * p * on,
        dx: 6 * p * on,
        glow: 0.2 * on,
        tint: const Color(0xFFD9D9E3),
        tintAmount: 0.3 * on,
      );
    case WordFx.float:
      return WordFxLook(
        dy: -10 * _out(p) * on,
        glow: 0.2 * on,
        tint: const Color(0xFFE8F0FF),
        tintAmount: 0.2 * on,
      );
    case WordFx.sink:
      return WordFxLook(dy: 8 * _out(p) * on, tintAmount: 0);
    case WordFx.shake:
      return WordFxLook(dx: math.sin(t / 18) * 3 * on * (1 - 0.5 * p));
    case WordFx.bounce:
      return WordFxLook(dy: -8 * (math.sin(math.pi * t / 220)).abs() * on);
    case WordFx.flash:
      final kick = t < 180 ? 1 - t / 180 : 0.0;
      return WordFxLook(
        flash: kick,
        scale: 1 + 0.15 * kick,
        dx: math.sin(t / 14) * 2 * kick,
      );
    case WordFx.bleed:
      return WordFxLook(
        tint: _blood,
        tintAmount: 0.9 * p * on,
        glow: 0.3 * p * on,
        drop: p,
      );
    case WordFx.drip:
      return WordFxLook(tint: _rain, tintAmount: 0.5 * on, drop: p);
    case WordFx.pulse:
      final beat = (math.sin(math.pi * t / 300)).abs();
      return WordFxLook(
        scale: 1 + 0.12 * beat * on,
        tint: _heart,
        tintAmount: 0.7 * on,
        glow: 0.4 * beat * on,
      );
    case WordFx.slowmo:
      return WordFxLook(stretch: 1 + 0.22 * _out(p) * on);
    case WordFx.rush:
      final inT = _c(t / 140);
      return WordFxLook(dx: -18 * (1 - _out(inT)), blur: 2.5 * (1 - inT));
  }
}
