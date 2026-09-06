import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Every sleeve in the app, loaded the same way.
///
/// Artwork dominates this interface, so how it arrives is most of how the app
/// feels. Loading it ad hoc at each call site meant a dozen slightly
/// different answers to the same four questions -- what shows while it loads,
/// what happens when it fails, whether it fades, and whether the layout moves
/// when it lands.
///
/// The answers here: the fallback shows immediately, the image fades over it
/// once decoded, a failure leaves the fallback in place, and the box is a
/// fixed size throughout so nothing reflows.
class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.url,
    required this.size,
    required this.fallback,
    this.height,
    this.borderRadius = RadiusTokens.card,
  });

  /// Null when there is no artwork to fetch, which is ordinary -- the daemon
  /// fetches covers on its own cycle and some records never get one.
  final String? url;

  final double size;

  /// Non-square boxes: a wide rail card crops its cover rather than letterboxing
  /// it. Defaults to [size], which is the usual case.
  final double? height;

  /// Shown while loading, and left in place if the fetch fails. Sized by the
  /// caller to the same box, so it cannot change the layout when it swaps.
  final Widget fallback;

  final double borderRadius;

  /// Fills whatever box the parent gives it -- a grid cell, say, whose size
  /// only the layout knows. Measures first so the decode is still sized to
  /// what is actually drawn.
  static Widget fill({
    required String? url,
    required Widget fallback,
    double borderRadius = RadiusTokens.card,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.hasBoundedWidth ? c.maxWidth : 200.0;
        final h = c.hasBoundedHeight ? c.maxHeight : w;
        return Artwork(
          url: url,
          size: w,
          height: h,
          fallback: fallback,
          borderRadius: borderRadius,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final src = url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: size,
        height: height ?? size,
        child: _content(context, src),
      ),
    );
  }

  Widget _content(BuildContext context, String? src) {
    if (src == null) return fallback;
    return Image.network(
      src,
      width: size,
      height: height ?? size,
      fit: BoxFit.cover,
      // Decoded at the size it is drawn at. A rail of twelve covers decoded
      // at their full resolution is tens of megabytes of bitmap for a strip
      // 132 points tall.
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        // Already in the image cache: show it outright. Fading in a cover
        // that was ready before the frame began is a flicker, not a
        // transition, and scrolling a list would be full of them.
        if (wasSynchronouslyLoaded) return child;
        return Stack(
          fit: StackFit.expand,
          children: [
            fallback,
            AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: child,
            ),
          ],
        );
      },
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

/// The neutral tile a sleeve sits on before it arrives.
///
/// Deliberately plain: it stands in for artwork that is about to appear, so
/// anything with character of its own would be the thing that flickers.
class ArtworkPlaceholder extends StatelessWidget {
  const ArtworkPlaceholder({super.key, this.borderRadius = RadiusTokens.card});

  final double borderRadius;

  /// Fills whatever box the parent gives it -- a grid cell, say, whose size
  /// only the layout knows. Measures first so the decode is still sized to
  /// what is actually drawn.
  static Widget fill({
    required String? url,
    required Widget fallback,
    double borderRadius = RadiusTokens.card,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.hasBoundedWidth ? c.maxWidth : 200.0;
        final h = c.hasBoundedHeight ? c.maxHeight : w;
        return Artwork(
          url: url,
          size: w,
          height: h,
          fallback: fallback,
          borderRadius: borderRadius,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Tones.surfaceRaised,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}
