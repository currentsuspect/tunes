import 'dart:io';

import 'package:flutter/material.dart';

import '../data/art_store.dart';
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
    this.shared = false,
    this.artSha,
  });

  /// Null when there is no artwork to fetch, which is ordinary -- the daemon
  /// fetches covers on its own cycle and some records never get one.
  final String? url;

  /// The cover's content sha, when the caller knows it. A sleeve with a sha
  /// prefers the on-disk copy from the [ArtScope] store and repaints if the
  /// cover lands later -- this is what keeps downloaded libraries dressed
  /// offline. Without it the sleeve is network-only, as before.
  final String? artSha;

  final double size;

  /// Non-square boxes: a wide rail card crops its cover rather than letterboxing
  /// it. Defaults to [size], which is the usual case.
  final double? height;

  /// Shown while loading, and left in place if the fetch fails. Sized by the
  /// caller to the same box, so it cannot change the layout when it swaps.
  final Widget fallback;

  final double borderRadius;

  /// This sleeve flies between screens, so it must not be decoded per size.
  ///
  /// cacheWidth is part of an image's cache key: a cover decoded at 44 and
  /// the same cover decoded at 312 are two entries, neither warm for the
  /// other. The destination would then decode from scratch mid-flight and
  /// show its fallback while it did. Shared sleeves decode once, at natural
  /// size, and both ends hit the same entry.
  final bool shared;

  /// Fills whatever box the parent gives it -- a grid cell, say, whose size
  /// only the layout knows. Measures first so the decode is still sized to
  /// what is actually drawn.
  static Widget fill({
    required String? url,
    required Widget fallback,
    double borderRadius = RadiusTokens.card,
    bool shared = false,
    String? artSha,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.hasBoundedWidth ? c.maxWidth : 200.0;
        final h = c.hasBoundedHeight ? c.maxHeight : w;
        return Artwork(
          url: url,
          artSha: artSha,
          size: w,
          height: h,
          fallback: fallback,
          borderRadius: borderRadius,
          shared: shared,
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
    // A sleeve that knows its art sha prefers the on-disk copy and repaints
    // if the cover lands later. Without a sha (or without a store above)
    // this is exactly the network sleeve it always was.
    final sha = artSha;
    final store = sha == null ? null : ArtScope.maybeOf(context);
    if (store == null || sha == null) return _network(context, src);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final path = store.pathFor(sha);
        if (path != null && File(path).existsSync()) {
          return _painted(context, FileImage(File(path)));
        }
        // Not on this phone yet. Ask for it, so the sleeve heals itself the
        // next time the server answers instead of staying a fallback until a
        // restart. The store dedupes, and pauses after a failure, so asking on
        // every build is safe.
        WidgetsBinding.instance.addPostFrameCallback((_) => store.fetch(sha));
        return _network(context, src);
      },
    );
  }

  Widget _network(BuildContext context, String? src) {
    if (src == null) return fallback;
    return _painted(context, NetworkImage(src));
  }

  Widget _painted(BuildContext context, ImageProvider provider) {
    // Decoded at the size it is drawn at. A rail of twelve covers decoded
    // at their full resolution is tens of megabytes of bitmap for a strip
    // 132 points tall. Image.network does this internally via its cacheWidth;
    // the shared Image constructor below needs the same ResizeImage wrapper
    // spelled out, or shared sleeves (which decode once at natural size)
    // excepted.
    final decodeWidth = shared
        ? null
        : (size * MediaQuery.devicePixelRatioOf(context)).round();
    final sized = decodeWidth == null
        ? provider
        : ResizeImage(provider, width: decodeWidth);
    return Image(
      image: sized,
      width: size,
      height: height ?? size,
      fit: BoxFit.cover,
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
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
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
