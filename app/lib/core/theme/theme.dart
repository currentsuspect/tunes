import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData buildTunesTheme(MediaQueryData mq) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.dark(
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
        side: const WidgetStatePropertyAll(BorderSide(color: Tones.hairline)),
        textStyle: WidgetStatePropertyAll(
          TypeScale.caption.copyWith(fontSize: 13),
        ),
        iconColor: const WidgetStatePropertyAll(Tones.primary),
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
        side: const BorderSide(color: Tones.hairline),
      ),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: const DividerThemeData(
      color: Tones.hairline,
      thickness: 1,
      space: 1,
    ),
  );
}
