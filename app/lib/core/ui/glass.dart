import 'dart:math' as math;
import 'dart:ui' show FragmentProgram, FragmentShader, ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/looks.dart';

/// Where the light catches Glass's panes, as a horizontal position from -1
/// (left) to 1 (right). The shell moves it as the page scrolls, so every
/// pane's bright edge glides together, as light does across real glass when
/// what is under it moves. A notifier, not state: the edges repaint, nothing
/// rebuilds.
abstract final class GlassSheen {
  static final x = ValueNotifier<double>(-0.35);

  /// Called with a vertical scroll's offset. A slow sine, so a long read
  /// sweeps the light back and forth rather than pinning it at one end.
  static void follow(double pixels) => x.value = math.sin(pixels / 520) * 0.85;
}

/// Glass's lens shader (shaders/glass_lens.frag): the page bends at a
/// floating pane's rim. Loaded once at start; until it has loaded, and
/// wherever the renderer cannot run a shader as a backdrop filter (Skia,
/// tests), panes are plain frost.
abstract final class GlassLens {
  static FragmentProgram? _program;

  static Future<void> load() async {
    if (!ImageFilter.isShaderFilterSupported) return;
    try {
      _program = await FragmentProgram.fromAsset('shaders/glass_lens.frag');
    } catch (_) {
      // A pane without a lens is still a pane.
    }
  }

  static FragmentShader? shader() => _program?.fragmentShader();
}

/// Glass's one effect: a pane that frosts what is behind it.
///
/// Blur is the most expensive thing this app draws, so panes go only on what
/// floats -- the dock, sheets, Now Playing's backdrop -- never on rows in a
/// scrolling list, where a translucent fill ([glassDecoration] without the
/// blur) reads nearly the same and costs nothing.
///
/// The edge has a highlight that follows [GlassSheen], and the finger while
/// the pane is pressed, when it also swells a little ([pressable]).
class GlassPane extends StatefulWidget {
  const GlassPane({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.blur = 24,
    this.tint,
    this.backing,
    this.pressable = false,
    this.lens = false,
    this.lift = false,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blur;

  /// A dim layer under the frost, for panes that carry text over busy
  /// content: the blur alone leaves it too clear to read on. Changes fade,
  /// so a pane can thicken as content slides under it.
  final Color? backing;

  /// The record's colour, washed faintly into the pane.
  final Color? tint;

  /// Swells under the finger. Only for panes that are themselves a control
  /// (the dock's capsules); a sheet that swelled would read as broken.
  final bool pressable;

  /// Bends the page at the rim ([GlassLens]). Only for small floating panes
  /// (the dock's capsules): it is a pass over every pixel the pane covers,
  /// and a sheet's worth of bending would be hard to read through.
  final bool lens;

  /// Hovers: a soft shadow under the pane, kept off the glass itself (through
  /// a clear pane a shadow reads as a smudge inside). For what floats over the
  /// page, the dock's capsules; a sheet is anchored and stays flat.
  final bool lift;

  @override
  State<GlassPane> createState() => _GlassPaneState();
}

class _GlassPaneState extends State<GlassPane> {
  /// The finger's position across the pane, -1 to 1, while it is down.
  final _touch = ValueNotifier<double?>(null);
  bool _down = false;

  @override
  void dispose() {
    _touch.dispose();
    super.dispose();
  }

  void _at(PointerEvent e) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.width == 0) return;
    _touch.value = (e.localPosition.dx / box.size.width * 2 - 1).clamp(-1, 1);
  }

  void _press(bool down) {
    if (widget.pressable && down != _down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final pane = ClipRRect(
      borderRadius: widget.borderRadius,
      child: _Frost(
        blur: widget.blur,
        lens: widget.lens,
        radius: widget.borderRadius.topLeft.x,
        dpr: MediaQuery.devicePixelRatioOf(context),
        child: AnimatedContainer(
          duration: still ? Duration.zero : const Duration(milliseconds: 260),
          color: widget.backing ?? Colors.transparent,
          child: DecoratedBox(
            decoration: glassDecoration(
              borderRadius: widget.borderRadius,
              tint: widget.tint,
              edge: false,
            ),
            position: DecorationPosition.background,
            child: CustomPaint(
              foregroundPainter: _EdgePainter(
                radius: widget.borderRadius,
                look: Looks.current,
                touch: _touch,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        _at(e);
        _press(true);
      },
      onPointerMove: _at,
      onPointerUp: (_) {
        _touch.value = null;
        _press(false);
      },
      onPointerCancel: (_) {
        _touch.value = null;
        _press(false);
      },
      child: AnimatedScale(
        // Glass under the finger swells, as iOS 26's does: a little more than
        // a button dips, because it is the material moving, not a key.
        scale: _down ? 1.035 : 1,
        duration: still ? Duration.zero : const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        child: widget.lift
            ? CustomPaint(
                painter: _LiftPainter(widget.borderRadius, Looks.current),
                child: pane,
              )
            : pane,
      ),
    );
  }
}

/// The frost behind a pane: a blur, and through [GlassLens] the bend at its
/// rim. A render object rather than a BackdropFilter because the lens needs
/// the pane's place on screen at paint time, mid-animation included (the
/// dock folding, a capsule swelling under the finger).
class _Frost extends SingleChildRenderObjectWidget {
  const _Frost({
    required this.blur,
    required this.lens,
    required this.radius,
    required this.dpr,
    required super.child,
  });

  final double blur;
  final bool lens;
  final double radius;
  final double dpr;

  @override
  _RenderFrost createRenderObject(BuildContext context) =>
      _RenderFrost(blur, lens ? GlassLens.shader() : null, radius, dpr);

  @override
  void updateRenderObject(BuildContext context, _RenderFrost render) {
    render
      ..blur = blur
      ..radius = radius
      ..dpr = dpr;
    if (lens && render.shader == null) render.shader = GlassLens.shader();
    if (!lens) render.shader = null;
  }
}

class _RenderFrost extends RenderProxyBox {
  _RenderFrost(this._blur, this.shader, this._radius, this._dpr);

  FragmentShader? shader;

  double _blur;
  set blur(double v) {
    if (v == _blur) return;
    _blur = v;
    markNeedsPaint();
  }

  double _radius;
  set radius(double v) {
    if (v == _radius) return;
    _radius = v;
    markNeedsPaint();
  }

  double _dpr;
  set dpr(double v) {
    if (v == _dpr) return;
    _dpr = v;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  BackdropFilterLayer? get layer => super.layer as BackdropFilterLayer?;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    final blur = ImageFilter.blur(sigmaX: _blur, sigmaY: _blur);
    final s = shader;
    var filter = blur;
    if (s != null) {
      final origin = localToGlobal(Offset.zero) * _dpr;
      final pane = size * _dpr;
      // Index 0 and 1 are u_size, which the engine sets.
      s
        ..setFloat(2, origin.dx)
        ..setFloat(3, origin.dy)
        ..setFloat(4, pane.width)
        ..setFloat(5, pane.height)
        ..setFloat(6, _radius * _dpr)
        ..setFloat(7, 9 * _dpr) // the rim pulls the page this far, at most
        ..setFloat(8, 14 * _dpr) // over a band this wide
        ..setFloat(9, 1.2 * _dpr); // with this much colour split
      filter = ImageFilter.compose(outer: ImageFilter.shader(s), inner: blur);
    }
    layer = (layer ?? BackdropFilterLayer())..filter = filter;
    context.pushLayer(layer!, super.paint, offset);
  }
}

/// The pane's edge: a hairline in [TunesLook.glassEdge] that brightens
/// toward one point, the finger's while it is down and [GlassSheen]'s
/// otherwise. Brightest along the top, where light lands on glass.
class _EdgePainter extends CustomPainter {
  _EdgePainter({required this.radius, required this.look, required this.touch})
    : super(repaint: Listenable.merge([GlassSheen.x, touch]));

  final BorderRadius radius;
  final TunesLook look;
  final ValueNotifier<double?> touch;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect).deflate(0.5);
    final at = touch.value ?? GlassSheen.x.value;
    final edge = look.glassEdge;
    final hot = Colors.white.withValues(alpha: look.isDark ? 0.85 : 1);
    final centre = ((at + 1) / 2).clamp(0.0, 1.0);
    final spread = touch.value == null ? 0.28 : 0.18;
    final across = LinearGradient(
      colors: [edge, edge, hot, edge, edge],
      stops: [
        0,
        (centre - spread).clamp(0.0, 1.0),
        centre,
        (centre + spread).clamp(0.0, 1.0),
        1,
      ],
    );
    final top = Rect.fromLTRB(0, 0, size.width, size.height / 2);
    // The glass's thickness: a soft glow just inside the rim, strongest at
    // the top, so the pane reads as a slab with volume rather than a cut-out.
    canvas
      ..save()
      ..clipRRect(rrect)
      ..drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: look.isDark ? 0.16 : 0.5),
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: look.isDark ? 0.05 : 0.2),
            ],
            stops: const [0, 0.55, 1],
          ).createShader(rect),
      )
      ..restore();
    // Light comes from above: the travelling highlight is on the top half of
    // the edge, the bottom half a plain, dimmer line.
    canvas
      ..save()
      ..clipRect(top)
      ..drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..shader = across.createShader(rect),
      )
      ..restore()
      ..save()
      ..clipRect(Rect.fromLTRB(0, size.height / 2, size.width, size.height))
      ..drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = edge.withValues(alpha: edge.a * 0.5),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_EdgePainter old) =>
      old.radius != radius || old.look != look || old.touch != touch;
}

/// The shadow a hovering pane casts on the page: soft, a little below, and
/// only outside the pane.
class _LiftPainter extends CustomPainter {
  _LiftPainter(this.radius, this.look);

  final BorderRadius radius;
  final TunesLook look;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = radius.toRRect(Offset.zero & size);
    canvas
      ..save()
      ..clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect((Offset.zero & size).inflate(40))
          ..addRRect(rrect),
      )
      ..drawRRect(
        rrect.shift(const Offset(0, 6)),
        Paint()
          ..color = Colors.black.withValues(alpha: look.isDark ? 0.42 : 0.14)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_LiftPainter old) =>
      old.radius != radius || old.look != look;
}

/// The pane's fill and edge without the blur, for things that sit on a pane
/// already (a blur inside a blur costs twice and shows nothing new) or in a
/// list.
BoxDecoration glassDecoration({
  BorderRadius borderRadius = BorderRadius.zero,
  Color? tint,
  bool edge = true,
}) {
  final look = Looks.current;
  final fill = look.glassFill;
  return BoxDecoration(
    borderRadius: borderRadius,
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        if (tint == null)
          fill[0]
        else
          Color.alphaBlend(tint.withValues(alpha: 0.10), fill[0]),
        fill[1],
      ],
    ),
    border: edge ? Border.all(color: look.glassEdge) : null,
  );
}

/// A bottom sheet's background: [solid] ([Tones.surface] unless given) in
/// every look but Glass, where the sheet is clear and [GlassSheet] frosts it.
Color sheetBackground([Color? solid]) => Looks.current.kind == LookKind.glass
    ? Colors.transparent
    : solid ?? Looks.current.surface;

/// A sheet's builder inside [GlassSheet]:
/// `builder: glassSheet(radius, (context) => ...)`.
WidgetBuilder glassSheet(double radius, WidgetBuilder builder) =>
    (context) => GlassSheet(radius: radius, child: builder(context));

/// A bottom sheet's body, frosted in Glass and unchanged in every other look.
/// Pair with [sheetBackground] on the `showModalBottomSheet` call.
class GlassSheet extends StatelessWidget {
  const GlassSheet({super.key, required this.radius, required this.child});

  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final look = Looks.current;
    if (look.kind != LookKind.glass) return child;
    return GlassPane(
      borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
      blur: 30,
      backing: look.base.withValues(alpha: look.isDark ? 0.62 : 0.5),
      child: child,
    );
  }
}

/// The top of a Glass screen: the page fades into the room's base under the
/// status bar, as iOS 26's scroll edge does, so rows scrolling up go soft
/// before they reach the clock instead of running into it.
class GlassTopEdge extends StatelessWidget {
  const GlassTopEdge({super.key});

  @override
  Widget build(BuildContext context) {
    final base = Looks.current.base;
    return IgnorePointer(
      child: SizedBox(
        height: MediaQuery.paddingOf(context).top + 18,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                base.withValues(alpha: 0.92),
                base.withValues(alpha: 0.6),
                base.withValues(alpha: 0),
              ],
              stops: const [0, 0.55, 1],
            ),
          ),
        ),
      ),
    );
  }
}

/// The light in a Glass room: two soft pools, the accent's top right and a
/// cooler one bottom left, laid over every route like Crayon's paper and
/// Noir's grain. Painted once and cached; it never repaints while you scroll.
class GlassLight extends StatelessWidget {
  const GlassLight({super.key});

  @override
  Widget build(BuildContext context) {
    final look = Looks.current;
    final a = look.isDark ? 0.16 : 0.12;
    return IgnorePointer(
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.9, -0.85),
                  radius: 0.9,
                  colors: [
                    look.primary.withValues(alpha: a),
                    look.primary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.95, 0.75),
                  radius: 0.85,
                  colors: [
                    const Color(0xFF8A7CF0).withValues(alpha: a * 0.8),
                    const Color(0xFF8A7CF0).withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
