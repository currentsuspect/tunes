import 'package:flutter/material.dart';

import 'looks.dart';

export 'looks.dart' show Looks, TunesLook, TunesThemeSpec, CoverStyle;

/// Tunes design tokens.
///
/// A room, not a catalogue: a cool blue-black wall, warm off-white type, and
/// one soft lilac that stands in until a record is playing and lends its own
/// colour. See the mood board this was built from for the reasoning.
abstract final class Tones {
  static Color get base => Looks.current.base;
  static Color get surface => Looks.current.surface;
  static Color get surfaceRaised => Looks.current.surfaceRaised;
  static Color get hairline => Looks.current.hairline;

  /// The resting accent. Whatever is playing replaces it with its own.
  static Color get primary => Looks.current.primary;
  static Color get onPrimary => Looks.current.onPrimary;

  /// Warm, not white: paper against an ink wall.
  static Color get text => Looks.current.text;
  static Color get textMuted => Looks.current.textMuted;

  /// "Saved on this phone". The only green in the app, so it always means that.
  static Color get held => Looks.current.held;

  /// Needs attention but is not broken: not on this phone, box unreachable.
  static Color get warn => Looks.current.warn;

  static Color get badge => Looks.current.badge;
}

/// Font families bundled in assets/fonts, so type looks the same offline.
abstract final class Faces {
  static String get display => Looks.current.display;
  static String get body => Looks.current.body;
  static String get mono => Looks.current.mono;
}

/// The bundled serif and grotesque are variable fonts. The weight is asked for
/// on the axis as well as through fontWeight, so a platform that does not map
/// one to the other still draws the right weight rather than the default.
abstract final class TypeScale {
  /// The name over the front door. Serif italic: a signature, not a logo.
  static TextStyle get wordmark => TextStyle(
    fontFamily: Faces.display,
    fontSize: 38,
    height: 1.0,
    fontWeight: FontWeight.w400,
    fontStyle: FontStyle.italic,
    letterSpacing: -0.6,
    color: Tones.text,
    fontVariations: [...Looks.current.displayAxes, FontVariation('wght', 400)],
  );

  /// Section headings -- "Just added", "On repeat", "Complete your
  /// collection". Set larger than [title], so a section and its contents do
  /// not carry equal weight.
  static TextStyle get heading => TextStyle(
    fontFamily: Faces.display,
    fontSize: 24,
    height: 1.15,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.2,
    color: Tones.text,
    fontVariations: [...Looks.current.displayAxes, FontVariation('wght', 500)],
  );

  /// The name of a thing: a track, an album, a row. Interface type, so a long
  /// list reads at a glance.
  static TextStyle get title => TextStyle(
    fontFamily: Faces.body,
    fontSize: 16,
    height: 1.25,
    fontWeight: FontWeight.w600,
    color: Tones.text,
    fontVariations: [...Looks.current.bodyAxes, FontVariation('wght', 600)],
  );

  static TextStyle get body => TextStyle(
    fontFamily: Faces.body,
    fontSize: 14,
    height: 1.45,
    fontWeight: FontWeight.w400,
    color: Tones.textMuted,
    fontVariations: [...Looks.current.bodyAxes, FontVariation('wght', 400)],
  );

  static TextStyle get caption => TextStyle(
    fontFamily: Faces.body,
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
    color: Tones.textMuted,
    fontVariations: [...Looks.current.bodyAxes, FontVariation('wght', 500)],
  );

  /// Big album and artist names, the Now Playing title.
  static TextStyle get display => TextStyle(
    fontFamily: Faces.display,
    fontSize: 30,
    height: 1.1,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.3,
    color: Tones.text,
    fontVariations: [...Looks.current.displayAxes, FontVariation('wght', 500)],
  );

  /// The personal voice: why a track was suggested, a lyric note, a
  /// playlist's description. Handwritten, in the sense that nothing else is.
  static TextStyle get note => TextStyle(
    fontFamily: Faces.display,
    fontSize: 16,
    height: 1.35,
    fontWeight: FontWeight.w400,
    fontStyle: FontStyle.italic,
    color: Tones.text,
    fontVariations: [...Looks.current.displayAxes, FontVariation('wght', 400)],
  );

  /// Durations, bitrates, counts. Tabular, so columns of them line up.
  static TextStyle get mono => TextStyle(
    fontFamily: Faces.mono,
    fontSize: 12,
    height: 1.3,
    color: Tones.textMuted,
  );

  static TextStyle get tabular =>
      TextStyle(fontFeatures: [FontFeature.tabularFigures()]);
}

abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 40.0;
}

abstract final class RadiusTokens {
  static double get card => Looks.current.cardRadius;
  static double get control => Looks.current.controlRadius;
}
