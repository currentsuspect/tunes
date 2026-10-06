import 'package:flutter/material.dart';
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
class TunesNavBar extends StatelessWidget {
  const TunesNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<TunesNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    // Grows with the system font scale, capped: at the largest settings a fixed
    // height clips the labels, and an uncapped bar eats the screen those
    // labels are there to navigate.
    final scale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.4);
    return SizedBox(
      height: 62 * scale,
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: _Tab(
                item: items[i],
                selected: i == selectedIndex,
                onTap: () {
                  if (i != selectedIndex) HapticFeedback.selectionClick();
                  onSelected(i);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.item, required this.selected, required this.onTap});

  final TunesNavItem item;
  final bool selected;
  final VoidCallback onTap;

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
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: fade,
              style: TypeScale.caption.copyWith(
                fontSize: 11,
                color: selected ? Tones.text : Tones.textMuted,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
              child: Text(item.label),
            ),
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
        ),
      ),
    );
  }
}
