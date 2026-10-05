import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/art_store.dart';
import '../theme/tokens.dart';

/// The colour a cover lends to the room around it.
///
/// Averaged over a small decode of the cover, weighted toward pixels that are
/// saturated and neither near-black nor near-white, so a dark sleeve with one
/// red object gives red and not mud. A cover with no real colour (greyscale,
/// monochrome) returns null and the room stays its resting lilac: tinting
/// with grey would only make the screen look dirty.
Color? tintFromRgba(Uint8List rgba) {
  var r = 0.0, g = 0.0, b = 0.0, total = 0.0, satSum = 0.0;
  final pixels = rgba.length ~/ 4;
  if (pixels == 0) return null;
  for (var i = 0; i < rgba.length; i += 4) {
    if (rgba[i + 3] < 200) continue;
    final pr = rgba[i] / 255, pg = rgba[i + 1] / 255, pb = rgba[i + 2] / 255;
    final hi = [pr, pg, pb].reduce((a, c) => a > c ? a : c);
    final lo = [pr, pg, pb].reduce((a, c) => a < c ? a : c);
    final sat = hi == 0 ? 0.0 : (hi - lo) / hi;
    final usable = hi > 0.22 && hi < 0.97 ? 1.0 : 0.15;
    final w = sat * sat * usable + 0.0005;
    r += pr * w;
    g += pg * w;
    b += pb * w;
    total += w;
    satSum += sat;
  }
  if (total == 0) return null;
  // Mean saturation of the whole cover, not of the weighted pixels: the
  // weighting would make any greyscale cover look coloured.
  if (satSum / pixels < 0.14) return null;
  final hsl = HSLColor.fromColor(
    Color.from(alpha: 1, red: r / total, green: g / total, blue: b / total),
  );
  // Held to a band that glows on ink: too dark vanishes, too light washes out
  // the paper-coloured type laid over it.
  return hsl
      .withSaturation(hsl.saturation.clamp(0.4, 0.85))
      .withLightness(hsl.lightness.clamp(0.42, 0.62))
      .toColor();
}

/// Decodes [file] small and returns its tint, remembering the answer by [sha].
class CoverTint {
  CoverTint._();

  static final Map<String, Color?> _memo = {};

  static Color? cached(String sha) => _memo[sha];

  static Future<Color?> of(String sha, File file) async {
    if (_memo.containsKey(sha)) return _memo[sha];
    Color? tint;
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 24);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      frame.image.dispose();
      if (data != null) {
        tint = tintFromRgba(data.buffer.asUint8List());
      }
    } catch (_) {
      tint = null;
    }
    _memo[sha] = tint;
    return tint;
  }
}

/// The accent for this subtree: the playing cover's colour, or lilac.
///
/// Controls that carry the accent (scrubber fill, active shuffle, the lyric
/// bar) read it from here, so the whole screen changes colour together
/// instead of each widget deciding for itself.
class AccentScope extends InheritedWidget {
  const AccentScope({super.key, required this.color, required super.child});

  final Color color;

  static Color of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccentScope>()?.color ??
      Tones.primary;

  @override
  bool updateShouldNotify(AccentScope old) => color != old.color;
}

/// Resolves the tint for [artSha] and hands it to [builder], animating the
/// change over 900 ms so a track change moves the light instead of flipping it.
///
/// Reads the saved cover from the [ArtStore] above it, so it works offline and
/// repaints if the cover lands late.
class TintBuilder extends StatefulWidget {
  const TintBuilder({super.key, required this.artSha, required this.builder});

  final String? artSha;
  final Widget Function(BuildContext context, Color tint) builder;

  @override
  State<TintBuilder> createState() => _TintBuilderState();
}

class _TintBuilderState extends State<TintBuilder> {
  Color? _tint;
  String? _resolvedFor;
  ArtStore? _store;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = ArtScope.maybeOf(context);
    if (store != _store) {
      _store?.removeListener(_resolve);
      _store = store;
      _store?.addListener(_resolve);
    }
    _resolve();
  }

  @override
  void didUpdateWidget(TintBuilder old) {
    super.didUpdateWidget(old);
    if (old.artSha != widget.artSha) _resolve();
  }

  @override
  void dispose() {
    _store?.removeListener(_resolve);
    super.dispose();
  }

  void _resolve() {
    final sha = widget.artSha;
    if (sha == null) {
      if (_tint != null) setState(() => _tint = null);
      _resolvedFor = null;
      return;
    }
    final known = CoverTint.cached(sha);
    if (CoverTint._memo.containsKey(sha)) {
      if (_resolvedFor != sha || _tint != known) {
        setState(() {
          _tint = known;
          _resolvedFor = sha;
        });
      }
      return;
    }
    final path = _store?.pathFor(sha);
    if (path == null) return;
    final file = File(path);
    if (!file.existsSync()) return;
    unawaited(
      CoverTint.of(sha, file).then((c) {
        if (mounted && widget.artSha == sha) {
          setState(() {
            _tint = c;
            _resolvedFor = sha;
          });
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: _tint ?? Tones.primary),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 900),
      curve: Curves.easeInOut,
      builder: (context, color, _) {
        final tint = color ?? Tones.primary;
        return AccentScope(color: tint, child: widget.builder(context, tint));
      },
    );
  }
}

/// A wash of [tint] pouring in from the top of the screen over the ink wall.
/// Nothing else moves: the background does very little, and the cover does the
/// lighting.
class AmbientGlow extends StatelessWidget {
  const AmbientGlow({super.key, required this.tint, this.strength = 0.42});

  final Color tint;
  final double strength;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -1.05),
            radius: 1.15,
            colors: [
              tint.withValues(alpha: strength),
              tint.withValues(alpha: strength * 0.35),
              tint.withValues(alpha: 0),
            ],
            stops: const [0, 0.5, 1],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}
