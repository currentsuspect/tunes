import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/tokens.dart';

/// Tinted Glass's colour: the record's (each song tints the glass its own
/// colour), one of a few picked colours, or any colour from the hue and
/// vividness strips. How light it is, the app decides: the accent is moved
/// to a lightness that reads on the room ([TunesLook.glassed]), so no choice
/// can leave text unreadable.
///
/// The strips preview live in the swatch here; the app takes the colour when
/// the finger lifts, since retinting every screen is too much work for every
/// frame of a drag.
class GlassTintPicker extends StatefulWidget {
  const GlassTintPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// 0xAARRGGBB, or null for the record's colour.
  final int? value;
  final ValueChanged<int?> onChanged;

  static const presets = [
    Color(0xFF7AA2FF), // ice blue
    Color(0xFFB18CFF), // violet
    Color(0xFFFF7EB6), // pink
    Color(0xFFFF8A5B), // coral
    Color(0xFFFFC857), // amber
    Color(0xFF5ED6A0), // mint
    Color(0xFF4FD1E8), // cyan
  ];

  @override
  State<GlassTintPicker> createState() => _GlassTintPickerState();
}

class _GlassTintPickerState extends State<GlassTintPicker> {
  late HSVColor _hsv = _from(widget.value);

  static HSVColor _from(int? v) =>
      HSVColor.fromColor(v == null ? GlassTintPicker.presets[0] : Color(v));

  @override
  void didUpdateWidget(GlassTintPicker old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value && widget.value != null) {
      _hsv = _from(widget.value);
    }
  }

  Color get _colour => _hsv.withValue(1).toColor();

  void _commit() => widget.onChanged(_colour.toARGB32());

  @override
  Widget build(BuildContext context) {
    final record = widget.value == null;
    final hex = _colour
        .toARGB32()
        .toRadixString(16)
        .padLeft(8, '0')
        .substring(2)
        .toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md + 2,
        vertical: Space.md - 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Glass colour',
                  style: TypeScale.title.copyWith(
                    fontSize: 15,
                    fontVariations: const [FontVariation('wght', 500)],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                record ? 'Each record’s own' : '#$hex',
                style: TypeScale.mono.copyWith(color: Tones.textMuted),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Swatch(
                label: 'Match the record',
                selected: record,
                onTap: () => widget.onChanged(null),
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        Color(0xFFFF7EB6),
                        Color(0xFFFFC857),
                        Color(0xFF5ED6A0),
                        Color(0xFF4FD1E8),
                        Color(0xFFB18CFF),
                        Color(0xFFFF7EB6),
                      ],
                    ),
                  ),
                  child: Icon(
                    Icons.music_note_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
              for (final c in GlassTintPicker.presets)
                _Swatch(
                  label: '#${c.toARGB32().toRadixString(16).substring(2)}',
                  selected: !record && widget.value == c.toARGB32(),
                  onTap: () => widget.onChanged(c.toARGB32()),
                  child: DecoratedBox(
                    decoration: BoxDecoration(shape: BoxShape.circle, color: c),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.lg),
          _Strip(
            label: 'Hue',
            value: _hsv.hue / 360,
            colors: [
              for (var h = 0; h <= 360; h += 60)
                HSVColor.fromAHSV(1, h.toDouble(), 0.75, 1).toColor(),
            ],
            onChanged: (v) => setState(() => _hsv = _hsv.withHue(v * 360)),
            onDone: _commit,
          ),
          const SizedBox(height: Space.md),
          _Strip(
            label: 'Vividness',
            value: _hsv.saturation,
            colors: [
              _hsv.withSaturation(0).withValue(1).toColor(),
              _hsv.withSaturation(1).withValue(1).toColor(),
            ],
            onChanged: (v) => setState(() => _hsv = _hsv.withSaturation(v)),
            onDone: _commit,
          ),
          const SizedBox(height: Space.md),
          _Preview(colour: record ? null : _colour),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    child: GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 34,
        height: 34,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Tones.text : Colors.transparent,
            width: 2,
          ),
        ),
        child: child,
      ),
    ),
  );
}

/// A rounded strip of colour with a round handle: drag or tap along it.
class _Strip extends StatelessWidget {
  const _Strip({
    required this.label,
    required this.value,
    required this.colors,
    required this.onChanged,
    required this.onDone,
  });

  final String label;
  final double value;
  final List<Color> colors;
  final ValueChanged<double> onChanged;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TypeScale.caption),
      const SizedBox(height: Space.xs + 2),
      Semantics(
        slider: true,
        label: label,
        value: '${(value * 100).round()}%',
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth;
            void at(double dx) => onChanged((dx / w).clamp(0.0, 1.0));
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => at(d.localPosition.dx),
              onTapUp: (_) => onDone(),
              onHorizontalDragStart: (d) => at(d.localPosition.dx),
              onHorizontalDragUpdate: (d) => at(d.localPosition.dx),
              onHorizontalDragEnd: (_) => onDone(),
              child: SizedBox(
                width: w,
                height: 30,
                child: CustomPaint(painter: _StripPainter(value, colors)),
              ),
            );
          },
        ),
      ),
    ],
  );
}

class _StripPainter extends CustomPainter {
  _StripPainter(this.value, this.colors);

  final double value;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    const r = 9.0;
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(r, size.height / 2 - 7, size.width - 2 * r, 14),
      const Radius.circular(7),
    );
    canvas.drawRRect(
      track,
      Paint()
        ..shader = LinearGradient(colors: colors).createShader(track.outerRect),
    );
    final x = r + value * (size.width - 2 * r);
    final c = Offset(x, size.height / 2);
    canvas
      ..drawCircle(
        c + const Offset(0, 1.5),
        r + 3,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      )
      ..drawCircle(c, r + 3, Paint()..color = Colors.white)
      ..drawCircle(c, r - 1, Paint()..color = _at(value));
  }

  Color _at(double t) {
    final span = t * (colors.length - 1);
    final i = span.floor().clamp(0, colors.length - 2);
    return Color.lerp(colors[i], colors[i + 1], span - i)!;
  }

  @override
  bool shouldRepaint(_StripPainter old) =>
      old.value != value || old.colors != colors;
}

/// What the choice will look like: a capsule of tinted glass with the accent
/// the app would take from it, before the finger lifts.
class _Preview extends StatelessWidget {
  const _Preview({required this.colour});

  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final look = Looks.current;
    final c = colour;
    final accent = c == null
        ? look.primary
        : TunesLook.glassAccent(c, dark: look.isDark);
    final fill = look.glassFill;
    return Container(
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: look.glassEdge),
        gradient: LinearGradient(
          colors: [
            if (c == null)
              fill[0]
            else
              Color.alphaBlend(c.withValues(alpha: 0.3), fill[0]),
            fill[1],
          ],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Space.md),
      child: Row(
        children: [
          Icon(Icons.graphic_eq_rounded, color: accent, size: 20),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              c == null
                  ? 'Glass takes each song’s colour'
                  : 'Glass, and the app’s accent',
              style: TypeScale.caption.copyWith(color: Tones.text),
            ),
          ),
          Text('Aa', style: TypeScale.title.copyWith(color: accent)),
        ],
      ),
    );
  }
}
