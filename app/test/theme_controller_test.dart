import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/theme/looks.dart';
import 'package:tunes/core/theme/theme_controller.dart';

void main() {
  TunesLook at(
    String choice,
    int mode,
    int hour, {
    Brightness phone = Brightness.dark,
  }) => ThemeController.resolve(
    choice: choice,
    brightnessMode: mode,
    platform: phone,
    now: DateTime(2026, 10, 9, hour),
  );

  test('auto is Crayon by day and Noir after dark', () {
    expect(at('auto', 1, 9).themeId, 'crayon');
    expect(at('auto', 1, 18).themeId, 'crayon');
    expect(at('auto', 1, 19).themeId, 'noir');
    expect(at('auto', 1, 2).themeId, 'noir');
  });

  test('every theme has a dark and a light look', () {
    for (final t in Looks.all) {
      expect(at(t.id, 1, 12).brightness, Brightness.dark);
      expect(at(t.id, 2, 12).brightness, Brightness.light);
      expect(
        at(t.id, 0, 12, phone: Brightness.light).brightness,
        Brightness.light,
      );
    }
  });

  test('an unknown theme falls back to Room', () {
    expect(at('nope', 1, 12), same(Looks.room.dark));
  });

  test('light looks keep text readable on their ground', () {
    double lum(Color c) => c.computeLuminance();
    double contrast(Color a, Color b) {
      final x = lum(a), y = lum(b);
      return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
    }

    for (final t in Looks.all) {
      for (final l in [t.dark, t.light]) {
        expect(
          contrast(l.text, l.base),
          greaterThan(7),
          reason: '${t.id} ${l.brightness} text',
        );
        expect(
          contrast(l.textMuted, l.base),
          greaterThan(4.5),
          reason: '${t.id} ${l.brightness} muted',
        );
      }
    }
  });
}
