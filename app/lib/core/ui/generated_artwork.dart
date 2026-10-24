import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/manifest.dart';
import '../../features/library/library_widgets.dart';
import '../theme/looks.dart';
import '../theme/tokens.dart';

/// A sleeve drawn from a name, for tracks that have no cover on this phone.
///
/// The same title and artist always draw the same sleeve, so the identity is
/// stable across restarts and devices. It is meant to look chosen, so a
/// library with gaps still looks like a shelf and not a list of placeholders.
///
/// Each look draws its own (owner, 24 Oct: the drawn covers "still have the
/// old main theme"; crayon them in Crayon, make them professional in the
/// others). Both used to be one diagonal gradient wash, which Crayon has
/// none of anywhere else:
///
/// - **Crayon:** a paper sleeve, one shape coloured in with a crayon (hatched,
///   with a wobbly ink line round it), the name written in the hand font.
/// - **Room and Noir:** a flat colour from a short, muted list, one clean
///   shape in a tone of it, and the title set like type on a printed sleeve.
///   Noir keeps to black, bone and its gold.
///
/// Small tiles show one or two letters; a tile big enough to read carries
/// the title too.
///
/// Callers showing several records by one act pass [label] instead, so the
/// tiles do not all draw the same initial.
class GeneratedArtwork extends StatelessWidget {
  const GeneratedArtwork({
    super.key,
    required this.title,
    required this.artist,
    this.size = 100,
    this.borderRadius = 8,
    this.label,
  });

  /// Convenience: build from a [ManifestTrack] if you have one.
  factory GeneratedArtwork.fromTrack(
    ManifestTrack track, {
    Key? key,
    double size = 100,
    double borderRadius = 8,
  }) {
    return GeneratedArtwork(
      key: key,
      title: track.title,
      artist: track.artist,
      size: size,
      borderRadius: borderRadius,
    );
  }

  final String title;
  final String artist;
  final double size;
  final double borderRadius;

  /// Overrides the letters drawn on the tile.
  ///
  /// The default is the artist's initial, which is what identifies a tile in
  /// a mixed list of tracks. In a rail of one act's records that makes every
  /// card read the same -- six Yeat albums all showing "Y" -- so those callers
  /// pass the album's initials instead. The colours already vary, because the
  /// seed includes the title.
  final String? label;

  /// The drawing for a name. Public so a test can say two tiles agree without
  /// reaching into paint calls.
  static SleeveSpec specFor(String title, String artist) =>
      SleeveSpec._(_seedFor(title, artist));

  @override
  Widget build(BuildContext context) {
    final spec = specFor(title, artist);
    final letter =
        label ??
        _initial(
          artist.isNotEmpty && artist != 'unknown artist' ? artist : title,
        );
    final look = Looks.current;
    final crayon = look.kind == LookKind.crayon;
    final palette = crayon
        ? _crayonPalette(spec)
        : _printPalette(spec, noir: look.kind == LookKind.noir);
    final tiny = size < 56;
    // Big enough to read a title: a sleeve, not a monogram.
    // A caller that names the letters wants letters.
    final titled = label == null && size >= 120 && title.trim().isNotEmpty;
    final inset = size * 0.09;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: crayon
              ? _CrayonSleevePainter(spec, palette)
              : _PrintSleevePainter(spec, palette),
          child: Padding(
            padding: EdgeInsets.all(inset),
            child: titled
                // Painted, not Text widgets: the title is printed on the
                // sleeve, and the caption under the card already says it,
                // so a screen reader (or a finder) should meet it once.
                ? CustomPaint(
                    size: Size.infinite,
                    painter: _Lettering(
                      title: title.trim(),
                      artist: artist.isNotEmpty && artist != 'unknown artist'
                          ? (crayon ? artist : artist.toUpperCase())
                          : null,
                      size: size,
                      crayon: crayon,
                      ink: palette.ink,
                      display: Faces.display,
                      small: crayon ? Faces.display : Faces.mono,
                    ),
                  )
                : Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      letter,
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: Faces.display,
                        fontStyle: crayon ? FontStyle.normal : FontStyle.italic,
                        fontWeight: crayon ? FontWeight.w700 : FontWeight.w500,
                        fontVariations: [
                          FontVariation('wght', crayon ? 700 : 500),
                        ],
                        color: palette.ink,
                        // Two letters at the one-letter size overflow a small tile.
                        fontSize:
                            size * (letter.characters.length > 1 ? 0.24 : 0.32),
                        height: 1.0,
                        letterSpacing: tiny ? 0 : -0.4,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  String _initial(String s) {
    final trimmed = s.trim();
    if (trimmed.isEmpty) return '?';
    // First grapheme cluster -- handles "E" / "L" with accents without
    // splitting surrogate pairs.
    final first = trimmed.characters.first;
    return first.toUpperCase();
  }

  /// FNV-1a over UTF-16 code units: stable across platforms and runs, unlike
  /// String.hashCode.
  static int _seedFor(String t, String a) {
    var h = 0x811c9dc5;
    for (final code in '$t|$a'.codeUnits) {
      h ^= code;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h;
  }
}

/// What a sleeve looks like, derived entirely from its seed.
@immutable
class SleeveSpec {
  const SleeveSpec._(this.seed);

  final int seed;

  double get hue => (seed % 360).toDouble();
  double get hue2 => (hue + 40 + ((seed >> 8) % 80)) % 360;
  double get shapeHue => (hue + 180) % 360;
  int get shape => (seed >> 4) % 3;

  Color get from => HSLColor.fromAHSL(1, hue, 0.45, 0.32).toColor();
  Color get to => HSLColor.fromAHSL(1, hue2, 0.50, 0.18).toColor();
  Color get accent => HSLColor.fromAHSL(1, shapeHue, 0.55, 0.68).toColor();

  @override
  bool operator ==(Object other) => other is SleeveSpec && other.seed == seed;

  @override
  int get hashCode => seed.hashCode;
}

/// A titled sleeve's lettering: the title, up to three lines, and the
/// artist under it.
class _Lettering extends CustomPainter {
  const _Lettering({
    required this.title,
    required this.artist,
    required this.size,
    required this.crayon,
    required this.ink,
    required this.display,
    required this.small,
  });

  final String title;
  final String? artist;
  final double size;
  final bool crayon;
  final Color ink;
  final String display;
  final String small;

  @override
  void paint(Canvas canvas, Size box) {
    final t = TextPainter(
      text: TextSpan(
        text: title,
        style: TextStyle(
          fontFamily: display,
          fontWeight: crayon ? FontWeight.w700 : FontWeight.w600,
          fontVariations: [FontVariation('wght', crayon ? 700 : 600)],
          color: ink,
          fontSize: size * 0.13,
          height: 1.05,
          letterSpacing: crayon ? 0 : -0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: box.width);
    t.paint(canvas, Offset.zero);
    final a = artist;
    if (a == null) return;
    final p = TextPainter(
      text: TextSpan(
        text: a,
        style: TextStyle(
          fontFamily: small,
          color: ink.withValues(alpha: 0.85),
          fontSize: size * (crayon ? 0.075 : 0.058),
          letterSpacing: crayon ? 0 : size * 0.008,
          height: 1.1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: box.width);
    p.paint(canvas, Offset(0, t.height + size * 0.03));
  }

  @override
  bool shouldRepaint(_Lettering old) =>
      old.title != title || old.artist != artist || old.ink != ink;
}

/// The colours one sleeve is drawn in.
@immutable
class SleevePalette {
  const SleevePalette({
    required this.ground,
    required this.shape,
    required this.ink,
    this.line,
  });

  final Color ground;
  final Color shape;

  /// Lettering.
  final Color ink;

  /// Crayon's outline round the shape; none on a printed sleeve.
  final Color? line;
}

// Covers are objects, not screen chrome: a Crayon sleeve is paper with the
// light crayons on it in either mode, the way a sticker stays a sticker on a
// dark page.
const _paper = Color(0xFFFFFBF2);
const _ink = Color(0xFF22201C);
const _crayonsOnPaper = [
  Color(0xFFFF5A4E),
  Color(0xFFFFC93C),
  Color(0xFF3FA7FF),
  Color(0xFF3DBE6B),
  Color(0xFF9B6BFF),
];

SleevePalette _crayonPalette(SleeveSpec spec) {
  final c = _crayonsOnPaper[spec.seed % _crayonsOnPaper.length];
  // One in three is coloured all over, with the shape left as paper.
  final flooded = (spec.seed >> 7) % 3 == 0;
  return SleevePalette(
    ground: flooded ? c : _paper,
    shape: flooded ? _paper : c,
    ink: _ink,
    line: _ink,
  );
}

/// Muted, printed colours: the sort a record sleeve is actually printed in,
/// none so loud that a shelf of them shouts over the real covers beside it.
const _printGrounds = [
  Color(0xFF1F3A5F), // ink blue
  Color(0xFF8C3B2E), // terracotta
  Color(0xFF4B5A2E), // olive
  Color(0xFF4A2C4F), // plum
  Color(0xFFB7862F), // ochre
  Color(0xFF2F4F4F), // slate green
  Color(0xFFD9CFC0), // stone
  Color(0xFF6B2737), // oxblood
];

const _noirGrounds = [
  Color(0xFF141413),
  Color(0xFF1E1D1A),
  Color(0xFFF2EEE6),
  Color(0xFF0B0B0B),
];
const _noirGold = Color(0xFFC9B37E);

SleevePalette _printPalette(SleeveSpec spec, {required bool noir}) {
  if (noir) {
    final g = _noirGrounds[spec.seed % _noirGrounds.length];
    final light = g.computeLuminance() > 0.5;
    return SleevePalette(
      ground: g,
      shape: (spec.seed >> 6) % 2 == 0
          ? _noirGold
          : (light ? const Color(0xFF111111) : const Color(0xFF3A3833)),
      ink: light ? const Color(0xFF111111) : const Color(0xFFF2EEE6),
    );
  }
  final g = _printGrounds[spec.seed % _printGrounds.length];
  final hsl = HSLColor.fromColor(g);
  final light = g.computeLuminance() > 0.45;
  // A tone of the ground, not its opposite: one family of colour per sleeve.
  final shape = hsl
      .withLightness(
        (light ? hsl.lightness - 0.22 : hsl.lightness + 0.18).clamp(0.0, 1.0),
      )
      .toColor();
  return SleevePalette(
    ground: g,
    shape: shape,
    ink: light ? const Color(0xFF1B1922) : const Color(0xFFF4F0E9),
  );
}

/// A small, seeded random, so a wobble is the same every time it is drawn.
class _Wobble {
  _Wobble(int seed) : _s = seed == 0 ? 1 : seed;
  int _s;
  double next() {
    _s = (_s * 1103515245 + 12345) & 0x7fffffff;
    return _s / 0x7fffffff;
  }

  double around(double v, double by) => v + (next() * 2 - 1) * by;
}

class _CrayonSleevePainter extends CustomPainter {
  const _CrayonSleevePainter(this.spec, this.palette);

  final SleeveSpec spec;
  final SleevePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final u = w / 100;
    final h = spec.seed;
    final rnd = _Wobble(h);
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.ground);

    final Path shape;
    switch (spec.shape) {
      case 0:
        // A sun, drawn by hand: a circle that does not quite close.
        final c = Offset((56 + (h >> 3) % 20) * u, (64 + (h >> 6) % 10) * u);
        final r = (18 + (h >> 9) % 10) * u;
        shape = Path();
        const steps = 28;
        for (var i = 0; i <= steps; i++) {
          final a = i / steps * 2 * math.pi;
          final rr = rnd.around(r, 1.6 * u);
          final p = c + Offset(math.cos(a) * rr, math.sin(a) * rr);
          i == 0 ? shape.moveTo(p.dx, p.dy) : shape.lineTo(p.dx, p.dy);
        }
        shape.close();
      case 1:
        // A hill.
        shape = Path()..moveTo(0, (70 + (h >> 3) % 12) * u);
        const steps = 10;
        for (var i = 1; i <= steps; i++) {
          final x = i / steps * w;
          final y =
              (62 + (h >> 6) % 10) * u +
              math.sin(i / steps * math.pi + (h % 7)) * 8 * u;
          shape.lineTo(x, rnd.around(y, 1.4 * u));
        }
        shape
          ..lineTo(w, w)
          ..lineTo(0, w)
          ..close();
      default:
        // A tilted card.
        final x = (44 + (h >> 3) % 16) * u, y = (46 + (h >> 6) % 10) * u;
        final s = (30 + (h >> 9) % 10) * u;
        shape = Path()
          ..moveTo(rnd.around(x, u), rnd.around(y, u))
          ..lineTo(rnd.around(x + s, u), rnd.around(y + 4 * u, u))
          ..lineTo(rnd.around(x + s - 4 * u, u), rnd.around(y + s + 4 * u, u))
          ..lineTo(rnd.around(x - 4 * u, u), rnd.around(y + s, u))
          ..close();
    }

    // Coloured in with a crayon: hatching, clipped to the shape, over a
    // light fill so the paper shows through a little.
    canvas.save();
    canvas.clipPath(shape);
    canvas.drawPath(
      shape,
      Paint()..color = palette.shape.withValues(alpha: 0.55),
    );
    final hatch = Paint()
      ..color = palette.shape
      ..strokeWidth = 2.6 * u
      ..strokeCap = StrokeCap.round;
    for (var d = -w; d < 2 * w; d += 5 * u) {
      canvas.drawLine(
        Offset(d, rnd.around(w, u)),
        Offset(d + w, rnd.around(0, u)),
        hatch,
      );
    }
    canvas.restore();

    final line = palette.line;
    if (line != null) {
      canvas.drawPath(
        shape,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.2, 1.8 * u)
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_CrayonSleevePainter old) =>
      old.spec != spec || old.palette.ground != palette.ground;
}

class _PrintSleevePainter extends CustomPainter {
  const _PrintSleevePainter(this.spec, this.palette);

  final SleeveSpec spec;
  final SleevePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final u = w / 100;
    final h = spec.seed;
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.ground);
    final fill = Paint()..color = palette.shape;
    switch (spec.shape) {
      case 0:
        // A large disc leaving the sleeve at the lower right.
        canvas.drawCircle(
          Offset((70 + (h >> 3) % 20) * u, (72 + (h >> 6) % 18) * u),
          (34 + (h >> 9) % 12) * u,
          fill,
        );
      case 1:
        // Bands across the lower half, like a printed rule set.
        final top = (56 + (h >> 3) % 10) * u;
        final band = (5 + (h >> 6) % 4) * u;
        for (var i = 0; i < 4; i++) {
          canvas.drawRect(
            Rect.fromLTWH(0, top + i * band * 1.9, w, band),
            fill,
          );
        }
      default:
        // A quarter circle from the lower left corner.
        canvas.drawCircle(Offset(0, w), (58 + (h >> 9) % 18) * u, fill);
    }
  }

  @override
  bool shouldRepaint(_PrintSleevePainter old) =>
      old.spec != spec || old.palette.ground != palette.ground;
}

/// Drop-in for places that want art-or-generated, picking the
/// available one. Pre-rendered to a fixed 200x200 tile.
class ArtworkForTrack extends StatelessWidget {
  const ArtworkForTrack({
    super.key,
    required this.track,
    required this.artUrlFor,
    this.size = 100,
    this.borderRadius = 8,
  });

  final ManifestTrack track;
  final String Function(String sha) artUrlFor;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return ArtThumb(
      sha: track.artSha,
      artUrlFor: artUrlFor,
      title: track.title,
      artist: track.artist,
      size: size,
      borderRadius: borderRadius,
    );
  }
}
