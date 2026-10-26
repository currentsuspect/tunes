import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'glass.dart';
import 'tunes_nav_bar.dart';

/// Glass's dock, after iOS 26's tab bar: the tabs and the mini player as two
/// capsules of glass hovering over the page.
///
/// Reading down the page minimizes it. With something playing, the tabs
/// shrink to one circle holding the current tab and the mini player slides
/// down beside it, so the page gets a whole row back; a tap on the circle, or
/// any move back up the page, opens it again. With nothing playing there is
/// nothing to make room for, and the labels only fold away.
class GlassDock extends StatelessWidget {
  const GlassDock({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.minimized,
    required this.onExpand,
    required this.backing,
    this.tint,
    this.mini,
  });

  final List<TunesNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool minimized;
  final VoidCallback onExpand;

  /// How thick the panes are (the shell thickens them over content).
  final Color backing;

  /// The record's colour, washed into the tabs' pane.
  final Color? tint;

  /// The mini player, at a fold from 0 (its own row) to 1 (inline beside the
  /// minimized tabs). Null when nothing is playing.
  final Widget Function(double fold)? mini;

  /// The minimized tabs: a circle the height of the inline mini player.
  static const _circle = 54.0;
  static const _miniHeight = 62.0;
  static const _gap = Space.sm;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final scale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.4);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.md,
        Space.xs,
        Space.md,
        Space.sm,
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: minimized ? 1 : 0),
        duration: still ? Duration.zero : const Duration(milliseconds: 620),
        curve: const LiquidCurve(),
        builder: (context, t, _) => mini == null
            ? _tabsAlone(t, scale)
            : LayoutBuilder(
                builder: (context, box) => _withMini(t, scale, box.maxWidth),
              ),
      ),
    );
  }

  Widget _pane({required double height, required Widget child}) => GlassPane(
    borderRadius: BorderRadius.circular(height / 2),
    tint: tint,
    backing: backing,
    pressable: true,
    lens: true,
    lift: true,
    child: child,
  );

  Widget _bar({double fold = 0, double minimize = 0}) => TunesNavBar(
    items: items,
    selectedIndex: selectedIndex,
    onSelected: onSelected,
    glass: true,
    fold: fold,
    minimize: minimize,
  );

  // The spring runs a little past 0 and 1: the glass's shape may overshoot
  // (that is the liquid), the fades and folds inside it may not.
  Widget _tabsAlone(double t, double scale) => _pane(
    height: (62 - 18 * t) * scale,
    child: _bar(fold: t.clamp(0.0, 1.0)),
  );

  Widget _withMini(double t, double scale, double width) {
    final full = 62 * scale;
    final f = t.clamp(0.0, 1.0);
    final tabsWidth = math.max(lerpDouble(width, _circle, t)!, _circle * 0.85);
    final tabsHeight = lerpDouble(full, _circle, t)!;
    final height = lerpDouble(_miniHeight + _gap + full, _circle, t)!;
    final miniLeft = lerpDouble(0, _circle + _gap, t)!;
    // The current tab glides into the middle of the circle as the rest of
    // the bar is cut away around it.
    final shift = lerpDouble(
      0,
      _circle / 2 - (selectedIndex + 0.5) * width / items.length,
      t,
    )!;
    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: miniLeft,
            top: 0,
            width: width - miniLeft,
            height: lerpDouble(_miniHeight, _circle, t),
            child: mini!(f),
          ),
          Positioned(
            left: 0,
            top: height - tabsHeight,
            width: tabsWidth,
            height: tabsHeight,
            child: _pane(
              height: tabsHeight,
              child: Stack(
                children: [
                  OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: width,
                    maxWidth: width,
                    child: Transform.translate(
                      offset: Offset(shift, 0),
                      child: _bar(fold: f, minimize: f),
                    ),
                  ),
                  // Minimized, the circle is one button: it opens the tabs.
                  if (minimized)
                    Positioned.fill(
                      child: Semantics(
                        button: true,
                        label: 'Show tabs',
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onExpand,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
