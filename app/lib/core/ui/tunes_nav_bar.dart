import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// The four drawn icons. Thin line glyphs on a 24 grid, the ones from the
/// mood board, in place of the stock Material set.
enum NavGlyph { home, discover, search, library }

/// One tab.
class TunesNavItem {
  const TunesNavItem({required this.glyph, required this.label});

  final NavGlyph glyph;
  final String label;
}

/// A drawn glyph at any size, for places that are not the tab bar (the desktop
/// sidebar).
class NavGlyphIcon extends StatelessWidget {
  const NavGlyphIcon({
    super.key,
    required this.glyph,
    required this.color,
    this.size = 22,
  });

  final NavGlyph glyph;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _GlyphPainter(glyph, color)),
  );
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.glyph, this.color);

  final NavGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    switch (glyph) {
      case NavGlyph.home:
        canvas.drawPath(
          Path()
            ..moveTo(3, 11)
            ..lineTo(12, 4)
            ..lineTo(21, 11)
            ..lineTo(21, 20)
            ..lineTo(15, 20)
            ..lineTo(15, 14)
            ..lineTo(9, 14)
            ..lineTo(9, 20)
            ..lineTo(3, 20)
            ..close(),
          line,
        );
      case NavGlyph.discover:
        canvas.drawCircle(const Offset(12, 12), 9, line);
        canvas.drawPath(
          Path()
            ..moveTo(15.5, 8.5)
            ..lineTo(13.5, 13.5)
            ..lineTo(8.5, 15.5)
            ..lineTo(10.5, 10.5)
            ..close(),
          line,
        );
      case NavGlyph.search:
        canvas.drawCircle(const Offset(10, 10), 6.5, line);
        canvas.drawLine(
          const Offset(14.8, 14.8),
          const Offset(20.5, 20.5),
          line,
        );
      case NavGlyph.library:
        canvas.drawRect(const Rect.fromLTRB(4, 4, 8, 20), line);
        canvas.drawRect(const Rect.fromLTRB(10, 4, 14, 20), line);
        canvas.drawPath(
          Path()
            ..moveTo(16, 6)
            ..lineTo(20, 5)
            ..lineTo(23, 19)
            ..lineTo(19, 20)
            ..close(),
          line,
        );
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.color != color;
}

/// The tabs along the bottom.
///
/// The old bar was Material's stock one on a flat grey surface. This one is the
/// page's own ink, with the current tab marked by an icon in the accent, a
/// paper-coloured label and a small dot, and the rest left quiet. Nothing
/// slides or pulses: the selection moves in a short, settled fade.
///
/// Glass is the exception ([glass]), after iOS 26: the current tab sits in a
/// droplet of glass that springs to the tab you pick, stretching as it goes,
/// and that a finger can drag along the bar to choose.
class TunesNavBar extends StatefulWidget {
  const TunesNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.compact = false,
    this.glass = false,
    this.fold,
    this.minimize = 0,
  });

  final List<TunesNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// Glyphs only, on a lower bar: Glass's dock while the page is being read
  /// downwards. The labels fold away rather than vanish, and come back the
  /// moment the page moves up.
  final bool compact;

  /// The droplet in place of the dot, and no ink splash: glass is lit, not
  /// stamped.
  final bool glass;

  /// How far the labels have folded, 0 to 1, for a dock that animates the
  /// fold itself. Overrides [compact].
  final double? fold;

  /// 0 to 1: every tab but the current one fades out, for a dock that shrinks
  /// the bar down to the current tab alone.
  final double minimize;

  @override
  State<TunesNavBar> createState() => _TunesNavBarState();
}

class _TunesNavBarState extends State<TunesNavBar>
    with SingleTickerProviderStateMixin {
  /// Where the droplet is, in tabs. Unbounded: the spring overshoots.
  late final _at = AnimationController.unbounded(
    vsync: this,
    value: widget.selectedIndex.toDouble(),
  );

  /// The tab under the finger while the droplet is being dragged.
  int? _dragTab;

  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 340,
    damping: 25,
  );

  @override
  void didUpdateWidget(TunesNavBar old) {
    super.didUpdateWidget(old);
    if (widget.selectedIndex != old.selectedIndex && _dragTab == null) {
      _springTo(widget.selectedIndex);
    }
  }

  @override
  void dispose() {
    _at.dispose();
    super.dispose();
  }

  void _springTo(int i) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _at.value = i.toDouble();
      return;
    }
    _at.animateWith(
      SpringSimulation(_spring, _at.value, i.toDouble(), _at.velocity),
    );
  }

  void _drag(double dx, double width) {
    final n = widget.items.length;
    final tabWidth = width / n;
    _at.stop();
    _at.value = (dx / tabWidth - 0.5).clamp(0.0, n - 1.0);
    final tab = (dx / tabWidth).floor().clamp(0, n - 1);
    if (tab != _dragTab) {
      // Picked up, then a tick for every tab it passes over.
      if (_dragTab == null) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.selectionClick();
      }
      setState(() => _dragTab = tab);
    }
  }

  void _drop() {
    final tab = _dragTab;
    if (tab == null) return;
    setState(() => _dragTab = null);
    // Set down.
    HapticFeedback.lightImpact();
    _springTo(tab);
    if (tab != widget.selectedIndex) widget.onSelected(tab);
  }

  @override
  Widget build(BuildContext context) {
    // Grows with the system font scale, capped: at the largest settings a fixed
    // height clips the labels, and an uncapped bar eats the screen those
    // labels are there to navigate.
    final scale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.4);
    final still = MediaQuery.disableAnimationsOf(context);
    final fold = widget.fold;
    if (fold != null) return _bar(fold, scale);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: widget.compact ? 1 : 0),
      duration: still ? Duration.zero : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, folded, _) => _bar(folded, scale),
    );
  }

  Widget _bar(double folded, double scale) {
    final items = widget.items;
    final shown = _dragTab ?? widget.selectedIndex;
    final height = (62 - 18 * folded) * scale;
    final row = Row(
      children: [
        for (var i = 0; i < items.length; i++)
          Expanded(
            child: Opacity(
              opacity: i == shown ? 1 : (1 - widget.minimize).clamp(0.0, 1.0),
              child: _Tab(
                item: items[i],
                selected: i == shown,
                folded: folded,
                glass: widget.glass,
                onTap: () {
                  if (i != widget.selectedIndex) {
                    HapticFeedback.selectionClick();
                  }
                  widget.onSelected(i);
                },
              ),
            ),
          ),
      ],
    );
    if (!widget.glass) return SizedBox(height: height, child: row);
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (d) => _drag(d.localPosition.dx, width),
          onHorizontalDragUpdate: (d) => _drag(d.localPosition.dx, width),
          onHorizontalDragEnd: (_) => _drop(),
          onHorizontalDragCancel: _drop,
          child: SizedBox(
            height: height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _at,
                    builder: (context, _) => CustomPaint(
                      painter: _DropletPainter(
                        at: _at.value,
                        speed: _at.velocity,
                        count: items.length,
                        held: _dragTab != null,
                        fade: 1 - widget.minimize,
                        look: Looks.current,
                      ),
                    ),
                  ),
                ),
                row,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Glass's current-tab droplet: a lighter capsule behind the current tab.
/// Moving, it stretches along the way it is going and thins, as a drop of
/// water does; held under the finger, it swells and its rim brightens.
class _DropletPainter extends CustomPainter {
  _DropletPainter({
    required this.at,
    required this.speed,
    required this.count,
    required this.held,
    required this.fade,
    required this.look,
  });

  final double at;
  final double speed;
  final int count;
  final bool held;
  final double fade;
  final TunesLook look;

  @override
  void paint(Canvas canvas, Size size) {
    if (fade <= 0) return;
    final tab = size.width / count;
    final stretch = (speed.abs() * 0.035).clamp(0.0, 0.45);
    final grow = held ? 1.08 : 1.0;
    final w = (tab - 8) * (1 + stretch) * grow;
    final h = (size.height - 10) * (1 - stretch * 0.3) * (held ? 1.06 : 1);
    final centre = Offset((at + 0.5) * tab, size.height / 2);
    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: centre, width: w, height: h),
      Radius.circular(h / 2),
    );
    final fill = look.isDark
        ? Colors.white.withValues(alpha: (held ? 0.2 : 0.13) * fade)
        : Colors.black.withValues(alpha: (held ? 0.09 : 0.065) * fade);
    canvas.drawRRect(rrect, Paint()..color = fill);
    canvas.drawRRect(
      rrect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = look.glassEdge.withValues(
          alpha: look.glassEdge.a * (held ? 1 : 0.55) * fade,
        ),
    );
  }

  @override
  bool shouldRepaint(_DropletPainter old) =>
      old.at != at ||
      old.speed != speed ||
      old.held != held ||
      old.fade != fade ||
      old.look != look ||
      old.count != count;
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.item,
    required this.selected,
    required this.onTap,
    this.folded = 0,
    this.glass = false,
  });

  final TunesNavItem item;
  final bool selected;
  final VoidCallback onTap;

  /// 0 with its label, 1 glyph only ([TunesNavBar.compact]).
  final double folded;

  /// In Glass's droplet: no splash, no dot, the label in the accent.
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final fade = still ? Duration.zero : const Duration(milliseconds: 180);
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 36,
        highlightShape: BoxShape.circle,
        splashFactory: glass ? NoSplash.splashFactory : null,
        highlightColor: glass ? Colors.transparent : null,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<Color?>(
              tween: ColorTween(
                end: selected ? Tones.primary : Tones.textMuted,
              ),
              duration: fade,
              builder: (context, color, _) => CustomPaint(
                size: const Size(24, 24),
                painter: _GlyphPainter(item.glyph, color ?? Tones.textMuted),
              ),
            ),
            ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: 1 - folded,
                child: Opacity(
                  opacity: 1 - folded,
                  child: Column(
                    children: [
                      const SizedBox(height: 3),
                      AnimatedDefaultTextStyle(
                        duration: fade,
                        style: TypeScale.caption.copyWith(
                          fontSize: 11,
                          color: selected
                              ? (glass ? Tones.primary : Tones.text)
                              : Tones.textMuted,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                        child: Text(item.label),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (!glass) ...[
              const SizedBox(height: 3),
              AnimatedContainer(
                duration: fade,
                width: selected ? 14 : 0,
                height: 2.5,
                decoration: BoxDecoration(
                  color: Tones.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
