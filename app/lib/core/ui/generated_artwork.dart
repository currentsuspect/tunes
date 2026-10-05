import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/manifest.dart';
import '../../features/library/library_widgets.dart';
import '../theme/tokens.dart';

/// A sleeve drawn from a name, for tracks that have no cover on this phone.
///
/// The same title and artist always draw the same sleeve, so the identity is
/// stable across restarts and devices. Two hues are derived from a hash and
/// laid on a diagonal wash, with one shape in the complementary hue (a sun,
/// a horizon, or a tilted frame) and the initial set small in the corner, the
/// way a record sleeve carries its name. It is meant to look chosen, so a
/// library with gaps still looks like a shelf and not a list of placeholders.
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
    final tiny = size < 56;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _SleevePainter(spec),
          child: Padding(
            padding: EdgeInsets.all(size * 0.09),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                letter,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: Faces.display,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                  fontVariations: const [FontVariation('wght', 500)],
                  color: Tones.text.withValues(alpha: 0.9),
                  // Two letters at the one-letter size overflow a small tile.
                  fontSize: size * (letter.characters.length > 1 ? 0.24 : 0.32),
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

class _SleevePainter extends CustomPainter {
  const _SleevePainter(this.spec);

  final SleeveSpec spec;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final u = w / 100;
    final h = spec.seed;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [spec.from, spec.to],
        ).createShader(rect),
    );
    final accent = Paint()..color = spec.accent.withValues(alpha: 0.82);
    switch (spec.shape) {
      case 0:
        canvas.drawCircle(
          Offset((30 + (h >> 3) % 40) * u, (35 + (h >> 6) % 30) * u),
          (22 + (h >> 9) % 16) * u,
          accent,
        );
      case 1:
        final path = Path()
          ..moveTo(0, (60 + (h >> 3) % 25) * u)
          ..quadraticBezierTo(
            50 * u,
            (30 + (h >> 6) % 30) * u,
            w,
            (55 + (h >> 9) % 30) * u,
          )
          ..lineTo(w, w)
          ..lineTo(0, w)
          ..close();
        canvas.drawPath(path, accent);
      default:
        canvas.save();
        canvas.translate(50 * u, 50 * u);
        canvas.rotate(((h >> 5) % 40) * math.pi / 180);
        canvas.translate(-50 * u, -50 * u);
        canvas.drawRect(
          Rect.fromLTWH(
            (15 + (h >> 3) % 30) * u,
            (15 + (h >> 6) % 30) * u,
            (34 + (h >> 9) % 20) * u,
            (34 + (h >> 11) % 20) * u,
          ),
          accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5 * u,
        );
        canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_SleevePainter old) => old.spec != spec;
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
