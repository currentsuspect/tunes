import 'package:flutter/material.dart';

import '../../domain/manifest.dart';
import '../../features/library/library_widgets.dart';

/// A deterministic gradient + initial-tile artwork for tracks that
/// have no artSha. The same input always produces the same colors
/// and label, so the visual identity stays stable across app
/// restarts and devices.
///
/// We pick two colours from a fixed palette by hashing the title,
/// gradient them diagonally, and overlay the first letter of the
/// primary artist (or the first letter of the title if no artist).
class GeneratedArtwork extends StatelessWidget {
  const GeneratedArtwork({
    super.key,
    required this.title,
    required this.artist,
    this.size = 100,
    this.borderRadius = 8,
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

  static const _palette = <Color>[
    Color(0xFF8E44AD),
    Color(0xFF2C3E50),
    Color(0xFF16A085),
    Color(0xFFD35400),
    Color(0xFF7F8C8D),
    Color(0xFF2C82C9),
    Color(0xFFE74C3C),
    Color(0xFF27AE60),
    Color(0xFFB7950B),
  ];

  @override
  Widget build(BuildContext context) {
    final seed = _seedFor(title, artist);
    final a = _palette[seed % _palette.length];
    final b = _palette[(seed ~/ _palette.length) % _palette.length];
    final letter = _initial(
      artist.isNotEmpty && artist != 'unknown artist' ? artist : title,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [a, b],
          ),
        ),
        child: Center(
          child: Text(
            letter,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: size * 0.45,
              fontWeight: FontWeight.w600,
              height: 1.0,
              letterSpacing: -0.5,
            ),
          ),
        ),
      ),
    );
  }

  String _initial(String s) {
    final trimmed = s.trim();
    if (trimmed.isEmpty) return '?';
    // First grapheme cluster — handles "É" / "Ł" / etc. without
    // splitting surrogate pairs.
    final first = trimmed.characters.first;
    return first.toUpperCase();
  }

  int _seedFor(String t, String a) {
    final s = '$t|$a';
    var h = 0;
    for (final code in s.codeUnits) {
      h = (h * 31 + code) & 0x7fffffff;
    }
    return h;
  }
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
