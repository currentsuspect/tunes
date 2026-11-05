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
import 'package:tunes/core/data/avatar.dart';
import 'package:tunes/core/theme/tokens.dart';
import 'package:tunes/core/ui/look_extras.dart';
import 'package:tunes/features/profile/glass_tint_picker.dart';
import 'package:tunes/features/profile/wallpaper_tile.dart';

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

  group('your own background', () {
    test('Glass with a photo clears the pages\' ground to show it', () {
      final look = ThemeController.resolve(
        choice: 'glass',
        brightnessMode: 1,
        platform: Brightness.dark,
        now: DateTime(2026),
        wallpaper: '/photos/beach.jpg',
      );
      expect(look.wallpaper, '/photos/beach.jpg');
      Looks.current = look;
      expect(Tones.page, Colors.transparent);
      Looks.current = Looks.glass.dark;
      expect(Tones.page, Looks.glass.dark.base);
    });

    test('the photo is Glass\'s alone', () {
      final look = ThemeController.resolve(
        choice: 'noir',
        brightnessMode: 1,
        platform: Brightness.dark,
        now: DateTime(2026),
        wallpaper: '/photos/beach.jpg',
      );
      expect(look.wallpaper, isNull);
      expect(identical(look, Looks.noir.dark), isTrue);
    });

    test('a photo keeps the style and tint it is chosen with', () {
      final a = Looks.glass.dark.glassed(
        GlassStyle.tinted,
        const Color(0xFFFF7EB6),
        '/p.jpg',
      );
      expect(a.glassStyle, GlassStyle.tinted);
      expect(a.glassTint, const Color(0xFFFF7EB6));
      expect(
        identical(
          a,
          Looks.glass.dark.glassed(
            GlassStyle.tinted,
            const Color(0xFFFF7EB6),
            '/p.jpg',
          ),
        ),
        isTrue,
      );
    });

    testWidgets('the photo goes under every page, in place of the light', (
      tester,
    ) async {
      Looks.current = Looks.glass.dark.glassed(
        GlassStyle.frosted,
        null,
        '/nowhere/photo.jpg',
      );
      await tester.pumpWidget(
        const MaterialApp(home: LookGround(child: Text('page'))),
      );
      expect(find.byType(GlassWallpaper), findsOneWidget);
      expect(find.byType(GlassLight), findsNothing);
      // A missing photo leaves the room's ground, not an error.
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      Looks.current = Looks.glass.dark;
      await tester.pumpWidget(
        const MaterialApp(home: LookGround(child: Text('page'))),
      );
      expect(find.byType(GlassWallpaper), findsNothing);
      expect(find.byType(GlassLight), findsOneWidget);
    });

    testWidgets('choosing, changing and removing the photo, and the old '
        'copy is cleaned up', (tester) async {
      final db = TunesDatabase.forTesting(NativeDatabase.memory());
      final settings = SettingsStore(db);
      await settings.load();
      final store = _FakeStore(['/a.jpg', '/b.jpg']);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: settings,
              builder: (_, _) =>
                  WallpaperTile(settings: settings, store: store),
            ),
          ),
        ),
      );
      expect(find.text('Choose photo'), findsOneWidget);
      expect(find.text('Dim'), findsNothing, reason: 'no photo, no sliders');
      await tester.tap(find.text('Choose photo'));
      await tester.pump();
      expect(settings.wallpaperPath, '/a.jpg');
      expect(find.text('Dim'), findsOneWidget);
      expect(find.text('Blur'), findsOneWidget);
      await tester.tap(find.text('Change'));
      await tester.pump();
      expect(settings.wallpaperPath, '/b.jpg');
      expect(store.discarded, ['/a.jpg']);
      await tester.tap(find.text('Remove'));
      await tester.pump();
      expect(settings.wallpaperPath, isNull);
      expect(store.discarded, ['/a.jpg', '/b.jpg']);
      await db.close();
    });

    testWidgets('dismissing the picker keeps the photo you had', (
      tester,
    ) async {
      final db = TunesDatabase.forTesting(NativeDatabase.memory());
      final settings = SettingsStore(db);
      await settings.load();
      await settings.setWallpaperPath('/keep.jpg');
      final store = _FakeStore([null]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WallpaperTile(settings: settings, store: store),
          ),
        ),
      );
      await tester.tap(find.text('Change'));
      await tester.pump();
      expect(settings.wallpaperPath, '/keep.jpg');
      expect(store.discarded, isEmpty);
      await db.close();
    });

    testWidgets('the picker offers the photo\'s colour', (tester) async {
      final picks = <int?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GlassTintPicker(
              value: null,
              onChanged: picks.add,
              photo: const Color(0xFF3DB8F2),
            ),
          ),
        ),
      );
      await tester.tap(find.bySemanticsLabel('From your photo'));
      expect(picks, [0xFF3DB8F2]);
    });
  });

  group('the glass is liquid', () {
    Matrix4? shape(WidgetTester tester) {
      final t = find.descendant(
        of: find.byType(GlassPane),
        matching: find.byType(Transform),
      );
      return t.evaluate().isEmpty
          ? null
          : tester.widget<Transform>(t.first).transform;
    }

    testWidgets('it swells under the finger and leans toward a drag', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const GlassPane(
            pressable: true,
            child: SizedBox(width: 300, height: 60),
          ),
        ),
      );
      final r = tester.getRect(find.byType(GlassPane));
      final g = await tester.startGesture(r.center);
      // A frame for the spring to start, then time for it to run.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final pressed = shape(tester)!;
      expect(pressed.getMaxScaleOnAxis(), greaterThan(1.02));
      await g.moveTo(r.centerRight - const Offset(4, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final pulled = shape(tester)!;
      expect(
        pulled.entry(0, 0),
        greaterThan(pulled.entry(1, 1)),
        reason: 'stretched the way it is pulled',
      );
      expect(
        MatrixUtils.transformPoint(pulled, const Offset(150, 30)).dx,
        greaterThan(150),
        reason: 'its middle leans toward the finger',
      );
      await g.up();
      // Let go, it springs back past its size and settles.
      var smallest = double.infinity;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final m = shape(tester);
        if (m != null && m.entry(1, 1) < smallest) smallest = m.entry(1, 1);
      }
      expect(smallest, lessThan(1), reason: 'it wobbles');
      await tester.pumpAndSettle();
      expect(shape(tester), isNull, reason: 'and comes to rest');
    });

    testWidgets('with reduce motion on, it does not move', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: const Scaffold(
              body: Center(
                child: GlassPane(
                  pressable: true,
                  child: SizedBox(width: 300, height: 60),
                ),
              ),
            ),
          ),
        ),
      );
      final g = await tester.startGesture(
        tester.getCenter(find.byType(GlassPane)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(shape(tester), isNull);
      await g.up();
    });

    testWidgets('the dock springs between its shapes without a fault', (
      tester,
    ) async {
      Widget dock(bool minimized) => _app(
        GlassDock(
          items: _items,
          selectedIndex: 2,
          onSelected: (_) {},
          minimized: minimized,
          onExpand: () {},
          backing: Colors.transparent,
          mini: (fold) => const SizedBox.expand(),
        ),
      );
      for (final m in [true, false, true]) {
        await tester.pumpWidget(dock(m));
        for (var i = 0; i < 50; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.takeException(), isNull);
        }
      }
    });
  });
}

class _FakeStore extends AvatarStore {
  _FakeStore(this.picks) : super.wallpaper();

  final List<String?> picks;
  final discarded = <String>[];

  @override
  Future<String?> pick() async => picks.removeAt(0);

  @override
  Future<void> discard(String? path) async {
    if (path != null) discarded.add(path);
  }
}
