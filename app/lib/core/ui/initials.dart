import 'package:flutter/material.dart';

import '../theme/tokens.dart';

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

class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.size = 40});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: colorFor(name), shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initialsFor(name),
        style: TextStyle(
          color: Tones.onPrimary,
          fontSize: size * 0.34,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
