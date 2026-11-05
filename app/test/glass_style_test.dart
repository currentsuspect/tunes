import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/theme/looks.dart';
import 'package:tunes/core/theme/theme_controller.dart';

TunesLook _resolve({String choice = 'glass', int style = 0, int? tint}) =>
    ThemeController.resolve(
      choice: choice,
      brightnessMode: 1,
      platform: Brightness.dark,
      now: DateTime(2026, 10, 26, 12),
      glassStyle: style,
      glassTint: tint,
    );

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('default Glass is the Glass look itself', () {
    expect(identical(_resolve(), Looks.glass.dark), isTrue);
  });

  test('the same choice gives the same look, so nothing rebuilds for it', () {
    expect(
      identical(
        _resolve(style: 2, tint: 0xFFFF7EB6),
        _resolve(style: 2, tint: 0xFFFF7EB6),
      ),
      isTrue,
    );
    expect(identical(_resolve(style: 1), _resolve(style: 1)), isTrue);
  });

  test('clear glass is less frosted and bends more', () {
    final clear = _resolve(style: 1);
    expect(clear.glassStyle, GlassStyle.clear);
    expect(clear.glassFrost, lessThan(Looks.glass.dark.glassFrost));
    expect(clear.glassBend, greaterThan(Looks.glass.dark.glassBend));
    expect(clear.glassWash(Colors.red), isNull);
  });

  test('a tint becomes the accent, readable whatever colour is picked', () {
    for (final tint in [0xFF000000, 0xFFFFFFFF, 0xFF0000FF, 0xFFFFFF00]) {
      for (final mode in [1, 2]) {
        final look = ThemeController.resolve(
          choice: 'glass',
          brightnessMode: mode,
          platform: Brightness.dark,
          now: DateTime(2026),
          glassStyle: 2,
          glassTint: tint,
        );
        expect(
          _contrast(look.primary, look.base),
          greaterThan(3),
          reason: 'tint ${tint.toRadixString(16)}, mode $mode',
        );
      }
    }
  });

  test('tinted with no colour of its own takes the record\'s', () {
    final look = _resolve(style: 2);
    expect(look.glassTint, isNull);
    expect(look.glassWash(Colors.green)?.$1, Colors.green);
  });

  test('glass styles leave the other themes alone', () {
    expect(
      identical(
        _resolve(choice: 'noir', style: 2, tint: 0xFFFF0000),
        Looks.noir.dark,
      ),
      isTrue,
    );
  });
}
