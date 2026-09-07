import 'package:flutter/material.dart';

/// Artwork that flies from where it was tapped to where it lands.
///
/// A plain [Hero] gets two things wrong here, and both of them are visible.
///
/// The flight happens in the Overlay, which has no [Material] ancestor. Text
/// with no inherited style there is drawn in Flutter's debug appearance --
/// yellow, double-underlined -- so a generated tile's letter changes
/// appearance for exactly the length of the animation and changes back.
///
/// And the default flight cross-fades the two ends, so a sleeve whose small
/// copy has loaded and whose large copy has not shows the placeholder
/// underneath the real cover as it grows.
///
/// This draws one widget for the whole flight -- the end being travelled
/// towards -- inside a transparent Material, so the sleeve simply changes
/// size.
class SharedSleeve extends StatelessWidget {
  const SharedSleeve({super.key, required this.tag, required this.child});

  /// Must be unique within a route. Two sleeves on one screen sharing a tag
  /// is an error Flutter throws at flight time, so rails that can show the
  /// same record twice do not tag at all.
  final Object tag;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: tag,
      flightShuttleBuilder: (context, animation, direction, fromCtx, toCtx) {
        final endpoint = direction == HeroFlightDirection.push
            ? toCtx
            : fromCtx;
        final hero = endpoint.widget as Hero;
        return Material(type: MaterialType.transparency, child: hero.child);
      },
      child: child,
    );
  }
}
