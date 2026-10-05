import 'package:flutter/material.dart';

/// Tunes design tokens.
///
/// A room, not a catalogue: a cool blue-black wall, warm off-white type, and
/// one soft lilac that stands in until a record is playing and lends its own
/// colour. See the mood board this was built from for the reasoning.
abstract final class Tones {
  static const base = Color(0xFF0E0E15);
  static const surface = Color(0xFF16161F);
  static const surfaceRaised = Color(0xFF1E1E2A);
  static const hairline = Color(0xFF2A2A38);

  /// The resting accent. Whatever is playing replaces it with its own.
  static const primary = Color(0xFFB4A2F4);
  static const onPrimary = Color(0xFF0E0E15);

  /// Warm, not white: paper against an ink wall.
  static const text = Color(0xFFECE6DD);
  static const textMuted = Color(0xFFA39FA8);

  /// "Saved on this phone". The only green in the app, so it always means that.
  static const held = Color(0xFF8FD1B0);

  /// Needs attention but is not broken: not on this phone, box unreachable.
  static const warn = Color(0xFFE6B87A);

  static const badge = Color(0xFF6E7B8B);
}

/// Font families bundled in assets/fonts, so type looks the same offline.
abstract final class Faces {
  static const display = 'Newsreader';
  static const body = 'HankenGrotesk';
  static const mono = 'DMMono';
}

/// The bundled serif and grotesque are variable fonts. The weight is asked for
/// on the axis as well as through fontWeight, so a platform that does not map
/// one to the other still draws the right weight rather than the default.
abstract final class TypeScale {
  /// The name over the front door. Serif italic: a signature, not a logo.
  static const wordmark = TextStyle(
    fontFamily: Faces.display,
    fontSize: 38,
    height: 1.0,
    fontWeight: FontWeight.w400,
    fontStyle: FontStyle.italic,
    letterSpacing: -0.6,
    color: Tones.text,
    fontVariations: [FontVariation('wght', 400)],
  );

  /// Section headings -- "Just added", "On repeat", "Complete your
  /// collection". Set larger than [title], so a section and its contents do
  /// not carry equal weight.
  static const heading = TextStyle(
    fontFamily: Faces.display,
    fontSize: 24,
    height: 1.15,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.2,
    color: Tones.text,
    fontVariations: [FontVariation('wght', 500)],
  );

  /// The name of a thing: a track, an album, a row. Interface type, so a long
  /// list reads at a glance.
  static const title = TextStyle(
    fontFamily: Faces.body,
    fontSize: 16,
    height: 1.25,
    fontWeight: FontWeight.w600,
    color: Tones.text,
    fontVariations: [FontVariation('wght', 600)],
  );

  static const body = TextStyle(
    fontFamily: Faces.body,
    fontSize: 14,
    height: 1.45,
    fontWeight: FontWeight.w400,
    color: Tones.textMuted,
    fontVariations: [FontVariation('wght', 400)],
  );

  static const caption = TextStyle(
    fontFamily: Faces.body,
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
    color: Tones.textMuted,
    fontVariations: [FontVariation('wght', 500)],
  );

  /// Big album and artist names, the Now Playing title.
  static const display = TextStyle(
    fontFamily: Faces.display,
    fontSize: 30,
    height: 1.1,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.3,
    color: Tones.text,
    fontVariations: [FontVariation('wght', 500)],
  );

  /// The personal voice: why a track was suggested, a lyric note, a
  /// playlist's description. Handwritten, in the sense that nothing else is.
  static const note = TextStyle(
    fontFamily: Faces.display,
    fontSize: 16,
    height: 1.35,
    fontWeight: FontWeight.w400,
    fontStyle: FontStyle.italic,
    color: Tones.text,
    fontVariations: [FontVariation('wght', 400)],
  );

  /// Durations, bitrates, counts. Tabular, so columns of them line up.
  static const mono = TextStyle(
    fontFamily: Faces.mono,
    fontSize: 12,
    height: 1.3,
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
  static const card = 18.0;
  static const control = 14.0;
}
