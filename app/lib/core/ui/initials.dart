import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'generated_artwork.dart';

String initialsFor(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) return words.first[0].toUpperCase();
  return (words.first[0] + words.last[0]).toUpperCase();
}

Color colorFor(String name) {
  const palette = [
    Color(0xFF9D8CF8),
    Color(0xFF64B5F6),
    Color(0xFF4DB6AC),
    Color(0xFFFFB74D),
    Color(0xFFF06292),
    Color(0xFF81C784),
  ];
  var h = 7;
  for (final c in name.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return palette[h % palette.length];
}

/// A circle for someone with no photo: the same deterministic wash the sleeves
/// use, with their initials set in the serif. Drawn from the name, so the same
/// person always looks the same.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.size = 40});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final spec = GeneratedArtwork.specFor(name, '');
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [spec.from, spec.to],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initialsFor(name),
        style: TextStyle(
          fontFamily: Faces.display,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w500,
          fontVariations: const [FontVariation('wght', 500)],
          color: Tones.text.withValues(alpha: 0.92),
          fontSize: size * 0.4,
          height: 1,
        ),
      ),
    );
  }
}
