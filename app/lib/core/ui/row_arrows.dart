import 'package:flutter/material.dart';

import '../platform/device.dart';
import '../theme/tokens.dart';

/// On a computer every sideways row (Just added, Your artists, an artist's
/// albums...) gets arrows at its ends while the pointer is over it. A mouse
/// wheel only scrolls up and down, so without them the rest of a row was
/// out of reach on anything but a trackpad.
///
/// Applied to every horizontal scrollable at once through the app's scroll
/// behaviour, rather than to each of the twenty rows by hand.
class TunesScrollBehavior extends MaterialScrollBehavior {
  const TunesScrollBehavior({this.verticalScrollbar = true});

  /// Off for a feed that draws its own pull-to-refresh: hiding scrollbars
  /// with copyWith(scrollbars: false) there hid them, and the arrows, from
  /// every row inside it too.
  final bool verticalScrollbar;

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final vertical = axisDirectionToAxis(details.direction) == Axis.vertical;
    if (vertical && !verticalScrollbar) return child;
    final inner = super.buildScrollbar(context, child, details);
    final controller = details.controller;
    if (!Device.isDesktop ||
        controller == null ||
        axisDirectionToAxis(details.direction) != Axis.horizontal) {
      return inner;
    }
    return RowArrows(controller: controller, child: inner);
  }
}

class RowArrows extends StatefulWidget {
  const RowArrows({super.key, required this.controller, required this.child});

  final ScrollController controller;
  final Widget child;

  @override
  State<RowArrows> createState() => _RowArrowsState();
}

class _RowArrowsState extends State<RowArrows> {
  bool _hover = false;

  void _step(int dir) {
    final c = widget.controller;
    if (!c.hasClients || c.positions.length != 1) return;
    final p = c.position;
    // Most of a screenful, so a cover at the edge stays in sight.
    final to = (p.pixels + dir * p.viewportDimension * 0.8).clamp(
      p.minScrollExtent,
      p.maxScrollExtent,
    );
    c.animateTo(
      to,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Stack(
        children: [
          widget.child,
          if (_hover)
            ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) {
                final c = widget.controller;
                if (!c.hasClients || c.positions.length != 1) {
                  return const SizedBox.shrink();
                }
                final p = c.position;
                if (!p.hasContentDimensions) return const SizedBox.shrink();
                return Positioned.fill(
                  child: Row(
                    children: [
                      if (p.pixels > p.minScrollExtent + 1)
                        _Arrow(left: true, onTap: () => _step(-1)),
                      const Spacer(),
                      if (p.pixels < p.maxScrollExtent - 1)
                        _Arrow(left: false, onTap: () => _step(1)),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.left, required this.onTap});

  final bool left;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Center(
        child: Material(
          color: Tones.surfaceRaised,
          shape: CircleBorder(side: BorderSide(color: Tones.hairline)),
          elevation: 2,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                left ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                color: Tones.text,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
