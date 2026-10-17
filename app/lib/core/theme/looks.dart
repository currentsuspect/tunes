import 'package:flutter/material.dart';

/// How covers are treated in a look. The screens ask, and each does what its
/// look says; a new look picks one rather than adding branches everywhere.
enum CoverStyle {
  /// Rounded, and the room is lit by the cover's colour (Room).
  glow,

  /// Square-cornered, full colour, no glow (Noir).
  flat,

  /// Sticker-like, with ink outlines (Crayon).
  crayon,
}

/// Everything one theme decides, for one brightness.
///
/// A theme is a pair of these (light and dark). Adding a theme is adding a
/// [TunesThemeSpec] to [Looks.all]: no screen changes, because every screen
/// reads its colours, faces and radii through `Tones`, `Faces`, `TypeScale`
/// and `RadiusTokens`, which all read [Looks.current].
@immutable
class TunesLook {
  const TunesLook({
    required this.themeId,
    required this.brightness,
    required this.base,
    required this.surface,
    required this.surfaceRaised,
    required this.hairline,
    required this.primary,
    required this.onPrimary,
    required this.text,
    required this.textMuted,
    required this.held,
    required this.warn,
    required this.badge,
    required this.display,
    required this.body,
    required this.mono,
    this.displayAxes = const [],
    this.bodyAxes = const [],
    this.cardRadius = 18,
    this.controlRadius = 14,
    this.covers = CoverStyle.glow,
    this.glowStrength = 1,
  });

  final String themeId;
  final Brightness brightness;

  final Color base;
  final Color surface;
  final Color surfaceRaised;
  final Color hairline;
  final Color primary;
  final Color onPrimary;
  final Color text;
  final Color textMuted;
  final Color held;
  final Color warn;
  final Color badge;

  final String display;
  final String body;
  final String mono;

  /// Extra variable-font axes for the display face (Crayon's bounce).
  final List<FontVariation> displayAxes;
  final List<FontVariation> bodyAxes;

  final double cardRadius;
  final double controlRadius;
  final CoverStyle covers;

  /// How strongly a cover's colour lights the room: 1 is Room's glow, 0 none.
  final double glowStrength;

  bool get isDark => brightness == Brightness.dark;
}

/// A named theme: its light and dark looks.
@immutable
class TunesThemeSpec {
  const TunesThemeSpec({
    required this.id,
    required this.name,
    required this.blurb,
    required this.dark,
    required this.light,
  });

  final String id;
  final String name;
  final String blurb;
  final TunesLook dark;
  final TunesLook light;

  TunesLook of(Brightness b) => b == Brightness.dark ? dark : light;
}

abstract final class Looks {
  /// The look every screen is drawn in right now. Set only by the theme
  /// controller, which then rebuilds the whole app.
  static TunesLook current = room.dark;

  static const room = TunesThemeSpec(
    id: 'room',
    name: 'Room',
    blurb: 'The room takes the colour of the record.',
    dark: TunesLook(
      themeId: 'room',
      brightness: Brightness.dark,
      base: Color(0xFF0E0E15),
      surface: Color(0xFF16161F),
      surfaceRaised: Color(0xFF1E1E2A),
      hairline: Color(0xFF2A2A38),
      primary: Color(0xFFB4A2F4),
      onPrimary: Color(0xFF0E0E15),
      text: Color(0xFFECE6DD),
      textMuted: Color(0xFFA39FA8),
      held: Color(0xFF8FD1B0),
      warn: Color(0xFFE6B87A),
      badge: Color(0xFF6E7B8B),
      display: 'Newsreader',
      body: 'HankenGrotesk',
      mono: 'DMMono',
    ),
    // The same room by day: paper walls, ink type, the lilac deepened so it
    // still reads as the accent on a light ground.
    light: TunesLook(
      themeId: 'room',
      brightness: Brightness.light,
      base: Color(0xFFF4F0E9),
      surface: Color(0xFFECE7DE),
      surfaceRaised: Color(0xFFFFFCF7),
      hairline: Color(0xFFDCD5C9),
      primary: Color(0xFF6A55C9),
      onPrimary: Color(0xFFFFFFFF),
      text: Color(0xFF1B1922),
      textMuted: Color(0xFF6B6672),
      held: Color(0xFF2F8A60),
      warn: Color(0xFFA86B1F),
      badge: Color(0xFF6E7B8B),
      display: 'Newsreader',
      body: 'HankenGrotesk',
      mono: 'DMMono',
      glowStrength: 0.55,
    ),
  );

  static const noir = TunesThemeSpec(
    id: 'noir',
    name: 'Noir',
    blurb: 'Premium and quiet: black, one gold accent, a fine serif.',
    dark: TunesLook(
      themeId: 'noir',
      brightness: Brightness.dark,
      base: Color(0xFF000000),
      surface: Color(0xFF0B0B0B),
      surfaceRaised: Color(0xFF141413),
      hairline: Color(0xFF242320),
      primary: Color(0xFFC9B37E),
      onPrimary: Color(0xFF000000),
      text: Color(0xFFF2EEE6),
      textMuted: Color(0xFF8A857B),
      held: Color(0xFF9FC9A8),
      warn: Color(0xFFD9A65E),
      badge: Color(0xFF6F6A60),
      display: 'BodoniModa',
      body: 'InstrumentSans',
      mono: 'IBMPlexMono',
      cardRadius: 4,
      controlRadius: 4,
      covers: CoverStyle.flat,
      glowStrength: 0,
    ),
    // Ivory stock, black ink, the gold darkened to brass so it holds up.
    light: TunesLook(
      themeId: 'noir',
      brightness: Brightness.light,
      base: Color(0xFFF7F4EE),
      surface: Color(0xFFEFEBE3),
      surfaceRaised: Color(0xFFFFFFFF),
      hairline: Color(0xFFDDD7CB),
      primary: Color(0xFF8C7136),
      onPrimary: Color(0xFFFFFFFF),
      text: Color(0xFF111111),
      textMuted: Color(0xFF6E685D),
      held: Color(0xFF3F7A52),
      warn: Color(0xFF9A6418),
      badge: Color(0xFF6F6A60),
      display: 'BodoniModa',
      body: 'InstrumentSans',
      mono: 'IBMPlexMono',
      cardRadius: 4,
      controlRadius: 4,
      covers: CoverStyle.flat,
      glowStrength: 0,
    ),
  );

  static const crayon = TunesThemeSpec(
    id: 'crayon',
    name: 'Crayon',
    blurb: 'A colouring book for music.',
    // Paper, ink and five crayons.
    light: TunesLook(
      themeId: 'crayon',
      brightness: Brightness.light,
      base: Color(0xFFFFFBF2),
      surface: Color(0xFFFFF4DC),
      surfaceRaised: Color(0xFFFFFFFF),
      hairline: Color(0x5922201C),
      primary: Color(0xFFFF5A4E),
      onPrimary: Color(0xFFFFFFFF),
      text: Color(0xFF22201C),
      textMuted: Color(0xFF6E675C),
      held: Color(0xFF2E9E57),
      warn: Color(0xFFD98A00),
      badge: Color(0xFF3FA7FF),
      display: 'ShantellSans',
      body: 'ShantellSans',
      mono: 'ShantellSans',
      displayAxes: [FontVariation('BNCE', 60), FontVariation('INFM', 60)],
      bodyAxes: [FontVariation('INFM', 20)],
      cardRadius: 16,
      controlRadius: 999,
      covers: CoverStyle.crayon,
      glowStrength: 0,
    ),
    // The same book on a chalkboard: dark paper, chalk lines, the crayons
    // brightened so they glow on it.
    dark: TunesLook(
      themeId: 'crayon',
      brightness: Brightness.dark,
      base: Color(0xFF1C1A2B),
      surface: Color(0xFF25223A),
      surfaceRaised: Color(0xFF2E2A47),
      hairline: Color(0x59EDE7DA),
      primary: Color(0xFFFF7A6E),
      onPrimary: Color(0xFF1C1A2B),
      text: Color(0xFFF6F1E6),
      textMuted: Color(0xFFB9B2C9),
      held: Color(0xFF5BD68A),
      warn: Color(0xFFFFC93C),
      badge: Color(0xFF6CC0FF),
      display: 'ShantellSans',
      body: 'ShantellSans',
      mono: 'ShantellSans',
      displayAxes: [FontVariation('BNCE', 60), FontVariation('INFM', 60)],
      bodyAxes: [FontVariation('INFM', 20)],
      cardRadius: 16,
      controlRadius: 999,
      covers: CoverStyle.crayon,
      glowStrength: 0,
    ),
  );

  static const all = [room, noir, crayon];

  static TunesThemeSpec byId(String id) =>
      all.firstWhere((t) => t.id == id, orElse: () => room);
}
