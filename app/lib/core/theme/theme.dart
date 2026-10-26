import 'package:flutter/material.dart';

import 'looks.dart';
import 'tokens.dart';

ThemeData buildTunesTheme(MediaQueryData mq) {
  final look = Looks.current;
  final scheme = look.isDark ? ColorScheme.dark : ColorScheme.light;
  final base = ThemeData(
    useMaterial3: true,
    brightness: look.brightness,
    colorScheme: scheme(
      surface: Tones.base,
      surfaceContainerLow: Tones.surface,
      surfaceContainerHigh: Tones.surfaceRaised,
      onSurface: Tones.text,
      onSurfaceVariant: Tones.textMuted,
      primary: Tones.primary,
      onPrimary: Tones.onPrimary,
      outline: Tones.hairline,
    ),
    scaffoldBackgroundColor: Tones.base,
    fontFamily: Faces.body,
    splashFactory: InkSparkle.splashFactory,
  );

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      displaySmall: TypeScale.wordmark,
      titleMedium: TypeScale.title,
      bodyMedium: TypeScale.body,
      bodySmall: TypeScale.caption,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Tones.surface,
      indicatorColor: Tones.primary.withValues(alpha: 0.16),
      labelTextStyle: WidgetStatePropertyAll(TypeScale.caption),
      iconTheme: WidgetStatePropertyAll(
        IconThemeData(color: Tones.textMuted, size: 22),
      ),
      height: 68,
      elevation: 0,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        // The default fills the selected segment with the Material tonal
        // colour, which on this scheme came out as a bright teal and was the
        // loudest thing on the Library screen.
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Tones.surfaceRaised
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Tones.text
              : Tones.textMuted,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: Tones.hairline)),
        textStyle: WidgetStatePropertyAll(
          TypeScale.caption.copyWith(fontSize: 13),
        ),
        iconColor: WidgetStatePropertyAll(Tones.primary),
        overlayColor: WidgetStatePropertyAll(
          Tones.primary.withValues(alpha: 0.08),
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: Tones.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RadiusTokens.card),
        side: BorderSide(color: Tones.hairline),
      ),
      margin: EdgeInsets.zero,
    ),
    // Every "more" menu. They took Material's defaults plus the control
    // radius, which in Crayon is a pill: a tall rounded slab laid over the
    // top bar with its first item clipped (owner, 24 Oct: "weird and not in
    // theme at all"). Now a card that opens under its button: an ink edge and
    // no blur in Crayon, a hairline and a soft lift in Room and Noir.
    // Glass (after iOS 26): menus and alerts are rounder, nearly opaque glass
    // with a bright rim. Not frosted: a menu opens over the very thing it is
    // about, and a blur behind small type costs more than it shows.
    dialogTheme: look.kind == LookKind.glass
        ? DialogThemeData(
            backgroundColor: Tones.surfaceRaised.withValues(alpha: 0.94),
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
              side: BorderSide(color: look.glassEdge),
            ),
          )
        : null,
    popupMenuTheme: PopupMenuThemeData(
      color: look.kind == LookKind.glass
          ? Tones.surfaceRaised.withValues(alpha: 0.94)
          : Tones.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      position: PopupMenuPosition.under,
      elevation: look.kind == LookKind.crayon ? 0 : 8,
      shadowColor: Colors.black.withValues(alpha: look.isDark ? 0.6 : 0.18),
      menuPadding: const EdgeInsets.symmetric(vertical: Space.xs),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          look.kind == LookKind.glass
              ? 20
              : RadiusTokens.card.clamp(4, 14).toDouble(),
        ),
        side: switch (look.kind) {
          LookKind.crayon => BorderSide(color: Tones.text, width: 2),
          LookKind.glass => BorderSide(color: look.glassEdge),
          _ => BorderSide(color: Tones.hairline),
        },
      ),
      textStyle: TypeScale.body,
      labelTextStyle: WidgetStatePropertyAll(TypeScale.body),
      iconColor: Tones.textMuted,
      iconSize: 20,
    ),
    dividerTheme: DividerThemeData(
      color: Tones.hairline,
      thickness: 1,
      space: 1,
    ),
  );
}
