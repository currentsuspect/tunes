import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// A cover that does something on a double tap, and shows what it did: a
/// mark that swells over the picture and fades.
///
/// What the double tap means is the listener's choice in Settings (like the
/// song, or download it), so [onDoubleTap] returns the icon to show, or null
/// when it did nothing.
class DoubleTapCover extends StatefulWidget {
  const DoubleTapCover({
    super.key,
    required this.child,
    required this.onDoubleTap,
    this.onTap,
  });

  final Widget child;
  final IconData? Function() onDoubleTap;
  final VoidCallback? onTap;

  @override
  State<DoubleTapCover> createState() => _DoubleTapCoverState();
}

class _DoubleTapCoverState extends State<DoubleTapCover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  IconData? _icon;

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  void _fire() {
    final icon = widget.onDoubleTap();
    if (icon == null) return;
    HapticFeedback.lightImpact();
    setState(() => _icon = icon);
    _burst.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTap: _fire,
      child: Stack(
        alignment: Alignment.center,
        children: [
          widget.child,
          if (_icon != null)
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _burst,
                builder: (context, _) {
                  final t = _burst.value;
                  // Swell quickly past full size, settle, then fade.
                  final scale = t < 0.35
                      ? Curves.easeOutBack.transform(t / 0.35)
                      : 1.0;
                  final opacity = t < 0.6 ? 1.0 : 1 - (t - 0.6) / 0.4;
                  return Opacity(
                    opacity: opacity.clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: 0.4 + 0.6 * scale,
                      child: Icon(
                        _icon,
                        size: 96,
                        color: Tones.text,
                        shadows: const [
                          Shadow(blurRadius: 24, color: Color(0x88000000)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
