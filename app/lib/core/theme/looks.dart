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

/// Which room a look belongs to, for the few things that are more than
/// colour: the progress line, section headings, the greeting's voice, the
/// ground texture, stickers and bounce (the mood board's "what changes"
/// table). Screens ask `Looks.current.kind`; a new theme picks one. Glass is
/// Room's light seen through frosted panes, so where a screen has nothing
/// glass-specific to say it treats Glass as Room.
enum LookKind { room, noir, crayon, glass }

/// How Glass's panes look, chosen the way the iPhone's home screen offers its
/// icons. Frosted: the default, milky glass washed with the record's colour.
/// Clear: barely frosted, so the page shows through sharp, held together by
/// a brighter rim and a stronger bend. Tinted: glass in one colour of your
/// choosing, which also becomes the app's accent; or, left to the record,
/// glass that changes colour with every song.
enum GlassStyle { frosted, clear, tinted }

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
    this.glassStyle = GlassStyle.frosted,
    this.glassTint,
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

  /// Glass's panes ([GlassStyle]); ignored by every other look.
  final GlassStyle glassStyle;

  /// Tinted Glass's own colour, or null for the record's.
  final Color? glassTint;

  bool get isDark => brightness == Brightness.dark;

  /// Crayon's hard, unblurred shadow under stickers and covers: ink on
  /// paper, and on the chalkboard a deeper board, since chalk would read as
  /// a second outline rather than a shadow.
  Color get inkShadow => isDark ? const Color(0xFF0E0D17) : text;

  LookKind get kind => switch (themeId) {
    'noir' => LookKind.noir,
    'crayon' => LookKind.crayon,
    'glass' => LookKind.glass,
    _ => LookKind.room,
  };

  /// Room's behaviour, for the screens that treat Glass as Room.
  bool get roomLike => kind == LookKind.room || kind == LookKind.glass;

  /// A frosted pane (Glass): the fill's two ends, lighter at the top-left
  /// where the light lands, and the bright edge that makes it read as glass
  /// rather than a grey box. The blur behind it is [GlassPane]'s.
  List<Color> get glassFill => switch ((glassStyle, isDark)) {
    (GlassStyle.clear, true) => const [Color(0x14FFFFFF), Color(0x05FFFFFF)],
    (GlassStyle.clear, false) => const [Color(0x4DFFFFFF), Color(0x1AFFFFFF)],
    (_, true) => const [Color(0x2EFFFFFF), Color(0x0FFFFFFF)],
    (_, false) => const [Color(0xB8FFFFFF), Color(0x73FFFFFF)],
  };
  Color get glassEdge => switch ((glassStyle, isDark)) {
    (GlassStyle.clear, true) => const Color(0x66FFFFFF),
    (GlassStyle.clear, false) => const Color(0xF2FFFFFF),
    (_, true) => const Color(0x38FFFFFF),
    (_, false) => const Color(0xCCFFFFFF),
  };

  /// How much of the frost a pane keeps (its blur, and the dim layer under
  /// text): Clear keeps a little, enough to read the dock through.
  double get glassFrost => glassStyle == GlassStyle.clear ? 0.35 : 1;

  /// How far a pane's rim bends the page, in points. Clear glass shows its
  /// shape by bending, since it has little frost to show it by.
  double get glassBend => glassStyle == GlassStyle.clear ? 14 : 9;

  /// The colour washed into a pane, given the record's: none in Clear, the
  /// chosen colour (strongly) in Tinted, the record's (faintly) otherwise.
  (Color, double)? glassWash(Color? record) => switch (glassStyle) {
    GlassStyle.clear => null,
    GlassStyle.tinted => switch (glassTint ?? record) {
      final c? => (c, isDark ? 0.30 : 0.24),
      null => null,
    },
    GlassStyle.frosted => record == null ? null : (record, 0.10),
  };

  /// This look as Glass in [style], with [tint] for Tinted. The same
  /// arguments give the same object, so the theme controller can tell
  /// nothing changed and leave the app alone.
  TunesLook glassed(GlassStyle style, Color? tint) {
    if (kind != LookKind.glass) return this;
    final keep = style == GlassStyle.tinted ? tint : null;
    if (style == glassStyle && keep == glassTint) return this;
    return _glassed.putIfAbsent((this, style, keep), () {
      // Tinted: the colour runs through the room, not just the panes. The
      // accent is the colour moved to a lightness that reads on this room,
      // the room's grounds take a breath of it.
      final accent = keep == null ? null : glassAccent(keep, dark: isDark);
      Color tone(Color c, double a) =>
          keep == null ? c : Color.alphaBlend(keep.withValues(alpha: a), c);
      // The whole room, not only the glass: grounds, cards, lines and the
      // quiet text all lean to the colour, the text itself stays ink.
      return TunesLook(
        themeId: themeId,
        brightness: brightness,
        base: tone(base, isDark ? 0.13 : 0.11),
        surface: tone(surface, isDark ? 0.15 : 0.13),
        surfaceRaised: tone(surfaceRaised, isDark ? 0.15 : 0.09),
        hairline: keep == null
            ? hairline
            : Color.alphaBlend(keep.withValues(alpha: 0.12), hairline),
        primary: accent ?? primary,
        onPrimary: onPrimary,
        text: text,
        textMuted: tone(textMuted, isDark ? 0.18 : 0.14),
        held: held,
        warn: warn,
        badge: badge,
        display: display,
        body: body,
        mono: mono,
        displayAxes: displayAxes,
        bodyAxes: bodyAxes,
        cardRadius: cardRadius,
        controlRadius: controlRadius,
        covers: covers,
        glowStrength: glowStrength,
        glassStyle: style,
        glassTint: keep,
      );
    });
  }

  static final _glassed = <(TunesLook, GlassStyle, Color?), TunesLook>{};

  /// Tinted Glass's accent for [tint]: the same hue, moved until it reads
  /// on a dark or a light room. By luminance, not lightness: a yellow and a
  /// blue of the same lightness are nowhere near as bright.
  static Color glassAccent(Color tint, {required bool dark}) {
    final h = HSLColor.fromColor(tint);
    var c = h.withSaturation(h.saturation.clamp(0.0, 0.9));
    var l = dark ? c.lightness.clamp(0.62, 0.82) : c.lightness.clamp(0.3, 0.5);
    bool reads(Color x) =>
        dark ? x.computeLuminance() >= 0.33 : x.computeLuminance() <= 0.17;
    while (!reads(c.withLightness(l).toColor()) && l > 0.05 && l < 0.95) {
      l += dark ? 0.02 : -0.02;
    }
    return c.withLightness(l).toColor();
  }

  /// Crayon's five crayons, for things coloured in turn (track numbers,
  /// squiggles). Brighter on the chalkboard.
  List<Color> get crayons => isDark
      ? const [
          Color(0xFFFF7A6E),
          Color(0xFFFFC93C),
          Color(0xFF6CC0FF),
          Color(0xFF5BD68A),
          Color(0xFFB896FF),
        ]
      : const [
          Color(0xFFFF5A4E),
          Color(0xFFFFC93C),
          Color(0xFF3FA7FF),
          Color(0xFF3DBE6B),
          Color(0xFF9B6BFF),
        ];
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

  static const glass = TunesThemeSpec(
    id: 'glass',
    name: 'Glass',
    blurb: 'Frosted panes over the colour of the record.',
    // Night glass: a deep indigo room, the cover's light stronger than in
    // Room because the panes take some of it.
    dark: TunesLook(
      themeId: 'glass',
      brightness: Brightness.dark,
      base: Color(0xFF0B0D1A),
      surface: Color(0xFF151A2C),
      surfaceRaised: Color(0xFF1D2338),
      hairline: Color(0x29FFFFFF),
      primary: Color(0xFFA9C7FF),
      onPrimary: Color(0xFF0B0D1A),
      text: Color(0xFFF4F6FB),
      textMuted: Color(0xFFA7AEC2),
      held: Color(0xFF7FE0B5),
      warn: Color(0xFFF2C47E),
      badge: Color(0xFF7E8AA6),
      display: 'InstrumentSans',
      body: 'HankenGrotesk',
      mono: 'DMMono',
      cardRadius: 22,
      controlRadius: 16,
      glowStrength: 1.35,
    ),
    // Frost: pale blue-grey, ink type, the accent a deeper periwinkle so it
    // still reads on the light panes.
    light: TunesLook(
      themeId: 'glass',
      brightness: Brightness.light,
      base: Color(0xFFEDF0F7),
      surface: Color(0xFFE3E7F1),
      surfaceRaised: Color(0xFFF8FAFD),
      hairline: Color(0x1F12152A),
      primary: Color(0xFF4F6BD8),
      onPrimary: Color(0xFFFFFFFF),
      text: Color(0xFF12152A),
      textMuted: Color(0xFF5E6478),
      held: Color(0xFF2B8A63),
      warn: Color(0xFFA8691C),
      badge: Color(0xFF6E7B8B),
      display: 'InstrumentSans',
      body: 'HankenGrotesk',
      mono: 'DMMono',
      cardRadius: 22,
      controlRadius: 16,
      glowStrength: 0.8,
    ),
  );

  static const all = [room, noir, crayon, glass];

  static TunesThemeSpec byId(String id) =>
      all.firstWhere((t) => t.id == id, orElse: () => room);
}
