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
