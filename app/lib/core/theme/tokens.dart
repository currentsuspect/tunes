import 'package:flutter/material.dart';

/// Tunes design tokens — v0 (M0 provisional).
/// Tonal dark scheme; final palette lands with branding at M5.
/// No earthy defaults, no pastel noise: deep neutral base, one cool violet accent.
abstract final class Tones {
  static const base = Color(0xFF14151A);
  static const surface = Color(0xFF1B1D24);
  static const surfaceRaised = Color(0xFF232630);
  static const hairline = Color(0xFF2E313B);

  static const primary = Color(0xFF9D8CF8);
  static const onPrimary = Color(0xFF14151A);

  static const text = Color(0xFFE9EAF0);
  static const textMuted = Color(0xFF9A9DA8);

  static const badge = Color(0xFF6E7B8B);
}

abstract final class TypeScale {
  static const wordmark = TextStyle(
    fontSize: 34,
    height: 1.05,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: Tones.text,
  );

  static const title = TextStyle(
    fontSize: 17,
    height: 1.25,
    fontWeight: FontWeight.w600,
    color: Tones.text,
  );

  static const body = TextStyle(
    fontSize: 14,
    height: 1.45,
    color: Tones.textMuted,
  );

  static const caption = TextStyle(
    fontSize: 11,
    height: 1.3,
    letterSpacing: 0.4,
    color: Tones.textMuted,
  );

  static const tabular = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 40.0;
}

abstract final class RadiusTokens {
  static const card = 20.0;
  static const control = 14.0;
}