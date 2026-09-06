import 'package:flutter/material.dart';

/// A card that answers the finger.
///
/// Ink ripples are the wrong feedback for artwork: the splash lands on top of
/// the image, or is clipped away by the rounded corner and never seen at all.
/// A short scale under the touch is felt rather than watched, which suits an
/// interface whose subject is the picture being pressed.
///
/// Deliberately small and fast -- ninety milliseconds down, a hair over on
/// release. Anything springier turns a library into a toy.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.onTap,
    required this.child,
    this.scale = 0.97,
  });

  final VoidCallback onTap;
  final Widget child;

  /// How far it gives. Three percent is enough to read on a 132-point card
  /// and not enough to look like it moved.
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (_down == down) return;
    setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Opaque, so the gap between a cover and its caption is part of the
      // card rather than a dead strip down the middle of the rail.
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
