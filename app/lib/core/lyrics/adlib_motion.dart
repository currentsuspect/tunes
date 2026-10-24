/// How each kind of ad-lib moves as it is sung (adlib_kinds.dart), drawn
/// from its own start and end and the playhead, like word_motion.dart: no
/// controllers, and a seek lands in the right state.
///
///   growl    shakes as it hits and stretches for as long as it is held
///   effect   pops in like a sticker, tilted, in the accent colour
///   whisper  faint and spaced, fading in rather than sweeping
///   echo     trails off in fading copies, like a delay
///   hype     bounces up on its beat
library;

import 'dart:math' as math;

import 'adlib_kinds.dart';

class AdlibLook {
  const AdlibLook({
    this.dx = 0,
    this.dy = 0,
    this.scale = 1,
    this.stretch = 1,
    this.rotate = 0,
    this.opacity = 1,
    this.ghosts = 0,
    this.ghostOpacity = 0,
    this.burst = 0,
  });

  /// A boom's burst, 0 none to 1 spent: lines flying out from the word.
  final double burst;

  /// Offset in logical pixels.
  final double dx;
  final double dy;
  final double scale;

  /// Horizontal stretch, for a held growl.
  final double stretch;

  /// Radians.
  final double rotate;
  final double opacity;

  /// Echo copies trailing to the right, and how strong the first one is.
  final int ghosts;
  final double ghostOpacity;

  static const neutral = AdlibLook();
}

/// At rest: a line not being sung, or lyrics with no word timing.
AdlibLook restingLook(AdlibKind kind) => switch (kind) {
  AdlibKind.effect => const AdlibLook(rotate: -0.07),
  AdlibKind.boom => const AdlibLook(rotate: -0.04),
  AdlibKind.whisper => const AdlibLook(opacity: 0.55),
  _ => AdlibLook.neutral,
};

double _clamp01(double v) => v.clamp(0.0, 1.0);
double _easeOut(double t) => 1 - math.pow(1 - _clamp01(t), 3).toDouble();

/// The look of an ad-lib word sung from [start] to [end], at [position].
AdlibLook adlibLook(
  AdlibKind kind, {
  required Duration start,
  required Duration end,
  required Duration position,
}) {
  final t = (position - start).inMilliseconds.toDouble();
  final dur = math.max(1, (end - start).inMilliseconds).toDouble();
  final after = (position - end).inMilliseconds.toDouble();
  switch (kind) {
    case AdlibKind.growl:
      if (t < 0) return AdlibLook.neutral;
      // A rumble on impact, gone in a third of a second.
      final shake = t < 300 ? math.sin(t / 16) * 2.5 * (1 - t / 300) : 0.0;
      // Stretched while held, eased back after.
      final held = after < 0 ? _clamp01(t / dur) : 1 - _easeOut(after / 220);
      return AdlibLook(dx: shake, stretch: 1 + 0.16 * _clamp01(held));
    case AdlibKind.effect:
      if (t < 0) {
        return const AdlibLook(rotate: -0.07, opacity: 0.3, scale: 0.85);
      }
      // 0.6 -> 1.3 in 120 ms, settle to 1 by 260 ms.
      final double s;
      if (t < 120) {
        s = 0.6 + 0.7 * _easeOut(t / 120);
      } else if (t < 260) {
        s = 1.3 - 0.3 * _easeOut((t - 120) / 140);
      } else {
        s = 1;
      }
      return AdlibLook(
        scale: s,
        rotate: -0.07 - 0.05 * (1 - _clamp01(t / 260)),
      );
    case AdlibKind.boom:
      if (t < 0) return const AdlibLook(opacity: 0.3, scale: 0.8);
      // Blows up to 1.7x in 90 ms, settles by 320; the burst flies out
      // and is gone by 340.
      final double s;
      if (t < 90) {
        s = 0.4 + 1.3 * _easeOut(t / 90);
      } else if (t < 320) {
        s = 1.7 - 0.7 * _easeOut((t - 90) / 230);
      } else {
        s = 1;
      }
      return AdlibLook(
        scale: s,
        rotate: -0.04,
        burst: t < 340 ? _clamp01(t / 340) : 0,
      );
    case AdlibKind.whisper:
      if (t < 0) return const AdlibLook(opacity: 0.3);
      return AdlibLook(opacity: 0.3 + 0.45 * _easeOut(t / 450));
    case AdlibKind.echo:
      if (t < 0) return AdlibLook.neutral;
      // Copies arrive one after another, then fade once the word is done.
      final n = t > 180 ? 2 : (t > 90 ? 1 : 0);
      final fade = after < 0 ? 1.0 : 1 - _clamp01(after / 700);
      return AdlibLook(ghosts: n, ghostOpacity: 0.45 * fade);
    case AdlibKind.hype:
      if (t < 0 || t > 240) return AdlibLook.neutral;
      final b = math.sin(math.pi * t / 240);
      return AdlibLook(dy: -6 * b, scale: 1 + 0.15 * b);
    case AdlibKind.stutter:
      if (t < 0) return const AdlibLook(opacity: 0.5);
      // A chop: it flickers and jumps in steps while it is said, like a
      // sample being retriggered, then holds still.
      if (after < 0 || after < 120) {
        final step = (t / 70).floor();
        return AdlibLook(
          dx: step.isEven ? 0 : 2.5,
          opacity: step % 3 == 2 ? 0.55 : 1,
        );
      }
      return AdlibLook.neutral;
    case AdlibKind.tag:
    case AdlibKind.plain:
      return AdlibLook.neutral;
  }
}
