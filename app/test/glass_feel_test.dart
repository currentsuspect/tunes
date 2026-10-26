import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/data/database.dart';
import 'package:tunes/core/data/settings_store.dart';
import 'package:tunes/core/theme/looks.dart';
import 'package:tunes/core/theme/theme_controller.dart';
import 'package:tunes/core/ui/glass.dart';
import 'package:tunes/core/ui/glass_dock.dart';
import 'package:tunes/core/ui/tunes_nav_bar.dart';
import 'package:tunes/features/profile/glass_tint_picker.dart';

const _items = [
  TunesNavItem(glyph: NavGlyph.home, label: 'Home'),
  TunesNavItem(glyph: NavGlyph.discover, label: 'Discover'),
  TunesNavItem(glyph: NavGlyph.search, label: 'Search'),
  TunesNavItem(glyph: NavGlyph.library, label: 'Library'),
];

/// Every haptic the app asks the phone for, by kind.
List<String> _feel(WidgetTester tester) {
  final felt = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        felt.add('${call.arguments}'.split('.').last);
      }
      return null;
    },
  );
  return felt;
}

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(
    body: Align(alignment: Alignment.bottomCenter, child: child),
  ),
);

void main() {
  late TunesLook before;
  setUp(() {
    before = Looks.current;
    Looks.current = Looks.glass.dark;
  });
  tearDown(() => Looks.current = before);

  group('the dock can be felt', () {
    testWidgets('touching glass knocks lightly', (tester) async {
      final felt = _feel(tester);
      await tester.pumpWidget(
        _app(
          const GlassPane(
            pressable: true,
            child: SizedBox(width: 200, height: 60),
          ),
        ),
      );
      final g = await tester.startGesture(
        tester.getCenter(find.byType(GlassPane)),
      );
      await tester.pump();
      expect(felt, ['lightImpact']);
      await g.up();
      await tester.pumpAndSettle();
      expect(felt, ['lightImpact'], reason: 'nothing more on release');
    });

    testWidgets('a pane that is not a control does not', (tester) async {
      final felt = _feel(tester);
      await tester.pumpWidget(
        _app(const GlassPane(child: SizedBox(width: 200, height: 60))),
      );
      await tester.tap(find.byType(GlassPane));
      expect(felt, isEmpty);
    });

    testWidgets('the droplet is picked up, ticks past each tab and is set '
        'down', (tester) async {
      final felt = _feel(tester);
      await tester.pumpWidget(
        _app(
          GlassDock(
            items: _items,
            selectedIndex: 0,
            onSelected: (_) {},
            minimized: false,
            onExpand: () {},
            backing: Colors.transparent,
          ),
        ),
      );
      final home = tester.getCenter(find.text('Home'));
      final library = tester.getCenter(find.text('Library'));
      final g = await tester.startGesture(home);
      for (var i = 1; i <= 12; i++) {
        await g.moveTo(Offset.lerp(home, library, i / 12)!);
        await tester.pump();
      }
      await g.up();
      await tester.pumpAndSettle();
      // The press on the glass, the pick-up, a tick for each of the three
      // tabs it passes into, and the set-down.
      expect(felt, [
        'lightImpact',
        'mediumImpact',
        'selectionClick',
        'selectionClick',
        'selectionClick',
        'lightImpact',
      ]);
    });
  });

  group('Tinted changes the whole app', () {
    late TunesDatabase db;
    late SettingsStore settings;
    late ThemeController theme;

    Future<void> start(WidgetTester tester) async {
      db = TunesDatabase.forTesting(NativeDatabase.memory());
      settings = SettingsStore(db);
      await settings.load();
      await settings.setThemeChoice('glass');
      await settings.setThemeBrightness(1);
      theme = ThemeController(settings);
    }

    // Before the test ends, not after: the theme's clock is a timer.
    Future<void> stop() async {
      theme.dispose();
      await db.close();
    }

    testWidgets('a chosen colour reaches the grounds, cards, lines and '
        'accent', (tester) async {
      await start(tester);
      final plain = Looks.current;
      await settings.setGlassStyle(2);
      await settings.setGlassTint(0xFFFF7EB6);
      final pink = Looks.current;
      expect(pink.glassTint, const Color(0xFFFF7EB6));
      for (final (name, a, b) in [
        ('base', plain.base, pink.base),
        ('surface', plain.surface, pink.surface),
        ('raised', plain.surfaceRaised, pink.surfaceRaised),
        ('hairline', plain.hairline, pink.hairline),
        ('muted text', plain.textMuted, pink.textMuted),
        ('accent', plain.primary, pink.primary),
      ]) {
        expect(b, isNot(a), reason: name);
      }
      // Pinker, not just different: red leads in the grounds now.
      expect(pink.base.r, greaterThan(plain.base.r));
      expect(pink.text, plain.text, reason: 'the type stays ink');
      await stop();
    });

    testWidgets('matching the record, the whole app follows each song', (
      tester,
    ) async {
      await start(tester);
      await settings.setGlassStyle(2);
      await settings.setGlassTint(null);
      theme.recordTint = const Color(0xFF3DB8F2);
      final blue = Looks.current;
      expect(blue.glassTint, const Color(0xFF3DB8F2));
      theme.recordTint = const Color(0xFFE85D75);
      expect(Looks.current.glassTint, const Color(0xFFE85D75));
      expect(Looks.current.base, isNot(blue.base));
      theme.recordTint = null;
      expect(Looks.current.glassTint, isNull, reason: 'nothing playing');
      await stop();
    });

    testWidgets('a chosen colour wins over the record\'s, and other styles '
        'ignore the record', (tester) async {
      await start(tester);
      await settings.setGlassStyle(2);
      await settings.setGlassTint(0xFF5ED6A0);
      theme.recordTint = const Color(0xFFE85D75);
      expect(Looks.current.glassTint, const Color(0xFF5ED6A0));
      await settings.setGlassStyle(0);
      expect(identical(Looks.current, Looks.glass.dark), isTrue);
      await stop();
    });
  });

  group('the colour picker', () {
    testWidgets('a swatch picks its colour, the record swatch picks none', (
      tester,
    ) async {
      final picks = <int?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GlassTintPicker(value: 0xFF7AA2FF, onChanged: picks.add),
          ),
        ),
      );
      await tester.tap(find.bySemanticsLabel('#ffc857'));
      await tester.tap(find.bySemanticsLabel('Match the record'));
      expect(picks, [0xFFFFC857, null]);
    });

    testWidgets('dragging the hue previews and applies the colour once, '
        'when the finger lifts', (tester) async {
      final picks = <int?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GlassTintPicker(value: 0xFF7AA2FF, onChanged: picks.add),
            ),
          ),
        ),
      );
      final hue = find.bySemanticsLabel('Hue').last;
      final r = tester.getRect(hue);
      expect(r.width, greaterThan(200), reason: 'the strip spans the row');
      final g = await tester.startGesture(r.centerLeft + const Offset(20, 0));
      for (var i = 1; i <= 10; i++) {
        await g.moveTo(
          Offset.lerp(
            r.centerLeft,
            r.centerRight - const Offset(40, 0),
            i / 10,
          )!,
        );
        await tester.pump();
      }
      expect(picks, isEmpty, reason: 'no retint mid-drag');
      await g.up();
      expect(picks, hasLength(1));
      final h = HSVColor.fromColor(Color(picks.single!)).hue;
      expect(h, greaterThan(270), reason: 'far along the wheel');
    });
  });
}
