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

  test('auto switches at the times the listener picked', () {
    TunesLook atMin(int h, int m, {int day = 6 * 60, int night = 22 * 60}) =>
        ThemeController.resolve(
          choice: 'auto',
          brightnessMode: 1,
          platform: Brightness.dark,
          now: DateTime(2026, 10, 9, h, m),
          dayFrom: day,
          nightFrom: night,
        );
    expect(atMin(21, 59).themeId, 'crayon');
    expect(atMin(22, 0).themeId, 'noir');
    expect(atMin(5, 59).themeId, 'noir');
    expect(atMin(6, 0).themeId, 'crayon');
    // By default: Noir from 18:45, as near sunset in Nairobi.
    expect(at('auto', 1, 18).themeId, 'crayon');
    expect(
      ThemeController.resolve(
        choice: 'auto',
        brightnessMode: 1,
        platform: Brightness.dark,
        now: DateTime(2026, 10, 9, 18, 45),
      ).themeId,
      'noir',
    );
  });

  test('each room knows what kind it is', () {
    expect(Looks.room.dark.kind, LookKind.room);
    expect(Looks.noir.light.kind, LookKind.noir);
    expect(Looks.crayon.dark.kind, LookKind.crayon);
    expect(Looks.crayon.light.crayons, hasLength(5));
  });
}
