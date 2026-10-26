import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/theme/looks.dart';
import 'package:tunes/core/theme/theme.dart';
import 'package:tunes/core/theme/tokens.dart';
import 'package:tunes/core/ui/glass.dart';
import 'package:tunes/core/ui/glass_dock.dart';
import 'package:tunes/core/ui/look_extras.dart';
import 'package:tunes/core/ui/tunes_nav_bar.dart';
import 'package:tunes/features/profile/glass_tint_picker.dart';

/// Pictures of every look's dock over a busy page, for a person to judge:
/// `TUNES_SHOT=1 flutter test test/glass_shots_test.dart --update-goldens`
/// writes them to test/shots/glass/. Skipped otherwise; pictures of glass
/// are for eyes, not for a diff.
Future<void> _fonts() async {
  for (final (family, files) in [
    ('InstrumentSans', ['InstrumentSans.ttf']),
    ('HankenGrotesk', ['HankenGrotesk.ttf']),
    ('DMMono', ['DMMono-Regular.ttf']),
    ('Newsreader', ['Newsreader.ttf']),
    ('BodoniModa', ['BodoniModa.ttf']),
    ('ShantellSans', ['ShantellSans.ttf']),
    ('IBMPlexMono', ['IBMPlexMono-Regular.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(
        Future.value(
          ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync()),
        ),
      );
    }
    await loader.load();
  }
}

/// A stand-in for someone's photo: a sunset of bands and soft discs, busy
/// enough to show what the glass does over a real picture.
Future<String> _samplePhoto() async {
  const size = Size(1170, 2532);
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF2B1B5A), Color(0xFFD9467A), Color(0xFFF6A04D)],
      ).createShader(Offset.zero & size),
  );
  for (final (x, y, r, col) in [
    (0.75, 0.38, 260.0, const Color(0xFFFFE08A)),
    (0.2, 0.7, 340.0, const Color(0xFF3DB8F2)),
    (0.6, 0.85, 220.0, const Color(0xFF5ED6A0)),
  ]) {
    c.drawCircle(
      Offset(x * size.width, y * size.height),
      r,
      Paint()..color = col.withValues(alpha: 0.75),
    );
  }
  final image = await rec.endRecording().toImage(
    size.width.toInt(),
    size.height.toInt(),
  );
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(
    '${Directory.systemTemp.createTempSync('tunes_shot').path}'
    '/photo.png',
  );
  await file.writeAsBytes(png!.buffer.asUint8List());
  return file.path;
}

const _items = [
  TunesNavItem(glyph: NavGlyph.home, label: 'Home'),
  TunesNavItem(glyph: NavGlyph.discover, label: 'Discover'),
  TunesNavItem(glyph: NavGlyph.search, label: 'Search'),
  TunesNavItem(glyph: NavGlyph.library, label: 'Library'),
];

const _covers = [
  Color(0xFFE85D75),
  Color(0xFFF2B33D),
  Color(0xFF3DB8F2),
  Color(0xFF7BD389),
  Color(0xFF9B6BFF),
];

class _Scene extends StatelessWidget {
  const _Scene({this.minimized = false});

  final bool minimized;

  @override
  Widget build(BuildContext context) {
    final look = Looks.current;
    final glass = look.kind == LookKind.glass;
    final record = _covers[4];
    final page = ListView(
      padding: const EdgeInsets.fromLTRB(Space.md, 54, Space.md, 220),
      children: [
        Text('Good evening', style: TypeScale.display.copyWith(fontSize: 30)),
        const SizedBox(height: Space.md),
        Container(
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            color: Tones.surface,
            borderRadius: BorderRadius.circular(RadiusTokens.card),
            border: Border.all(color: Tones.hairline),
          ),
          child: Row(
            children: [
              Icon(Icons.graphic_eq_rounded, color: Tones.primary),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text('Your week in music', style: TypeScale.title),
              ),
              Text('12h', style: TypeScale.mono.copyWith(color: Tones.primary)),
            ],
          ),
        ),
        const SizedBox(height: Space.lg),
        for (var i = 0; i < 9; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm + 2),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: _covers[i % 5],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Song number ${i + 1}', style: TypeScale.title),
                      Text('An artist · 3:2$i', style: TypeScale.caption),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    Widget mini(double fold) => GlassPane(
      borderRadius: BorderRadius.circular(31),
      tint: record,
      backing: look.base.withValues(alpha: look.isDark ? 0.42 : 0.34),
      pressable: true,
      lift: true,
      child: Row(
        children: [
          SizedBox(width: Space.sm + 2 + 2 * fold),
          Container(
            width: 42 - 8 * fold,
            height: 42 - 8 * fold,
            decoration: BoxDecoration(
              color: _covers[0],
              borderRadius: BorderRadius.circular(9 + 2 * fold),
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(child: Text('Song number 4', style: TypeScale.title)),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Tones.text,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.play_arrow_rounded, color: Tones.base),
          ),
          const SizedBox(width: Space.sm + 4),
        ],
      ),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTunesTheme(const MediaQueryData()),
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 844),
          padding: EdgeInsets.only(top: 47, bottom: 34),
        ),
        child: Scaffold(
          backgroundColor: Tones.page,
          extendBody: glass,
          body: LookGround(
            child: Stack(
              children: [
                page,
                if (glass)
                  const Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: GlassTopEdge(),
                  ),
              ],
            ),
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: glass
                ? GlassDock(
                    items: _items,
                    selectedIndex: 1,
                    onSelected: (_) {},
                    minimized: minimized,
                    onExpand: () {},
                    tint: record,
                    backing: look.base.withValues(
                      alpha: look.isDark ? 0.42 : 0.34,
                    ),
                    mini: mini,
                  )
                : TunesNavBar(
                    items: _items,
                    selectedIndex: 1,
                    onSelected: (_) {},
                  ),
          ),
        ),
      ),
    );
  }
}

void main() {
  final shoot = Platform.environment['TUNES_SHOT'] != null;
  late TunesLook before;
  late String photo;
  setUpAll(() async {
    await _fonts();
    if (shoot) photo = await _samplePhoto();
  });
  setUp(() => before = Looks.current);
  tearDown(() => Looks.current = before);

  for (final (name, style, tint, dark) in [
    ('photo_default_dark', GlassStyle.frosted, null, true),
    ('photo_clear_dark', GlassStyle.clear, null, true),
    ('photo_tinted_light', GlassStyle.tinted, const Color(0xFFD9467A), false),
  ]) {
    testWidgets('shot: $name', skip: !shoot, (tester) async {
      Looks.current = Looks.glass
          .of(dark ? Brightness.dark : Brightness.light)
          .glassed(style, tint, photo);
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      // The photo loads from disk, outside the test's fake clock, so it is
      // decoded first, at the size the wallpaper asks for (the scene's
      // MediaQuery says 1x), and the scene then finds it ready.
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => precacheImage(
          ResizeImage(FileImage(File(photo)), height: 844),
          tester.element(find.byType(SizedBox)),
        ),
      );
      await tester.pumpWidget(const _Scene());
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('shots/glass/$name.png'),
      );
    });
  }

  final cases = <(String, TunesLook, bool)>[
    for (final dark in [true, false]) ...[
      for (final (name, style, tint) in [
        ('default', GlassStyle.frosted, null),
        ('clear', GlassStyle.clear, null),
        ('tinted_pink', GlassStyle.tinted, const Color(0xFFFF7EB6)),
        ('tinted_amber', GlassStyle.tinted, const Color(0xFFFFC857)),
        ('tinted_record', GlassStyle.tinted, _covers[4]),
      ])
        (
          'glass_${name}_${dark ? 'dark' : 'light'}',
          Looks.glass
              .of(dark ? Brightness.dark : Brightness.light)
              .glassed(style, tint),
          false,
        ),
      for (final spec in [Looks.room, Looks.noir, Looks.crayon])
        (
          '${spec.id}_${dark ? 'dark' : 'light'}',
          spec.of(dark ? Brightness.dark : Brightness.light),
          false,
        ),
    ],
    ('glass_default_dark_minimized', Looks.glass.dark, true),
    (
      'glass_tinted_pink_dark_minimized',
      Looks.glass.dark.glassed(GlassStyle.tinted, const Color(0xFFFF7EB6)),
      true,
    ),
  ];

  for (final (name, look, minimized) in cases) {
    testWidgets('shot: $name', skip: !shoot, (tester) async {
      Looks.current = look;
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_Scene(minimized: minimized));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('shots/glass/$name.png'),
      );
    });
  }

  for (final dark in [true, false]) {
    testWidgets('shot: picker ${dark ? 'dark' : 'light'}', skip: !shoot, (
      tester,
    ) async {
      Looks.current = Looks.glass
          .of(dark ? Brightness.dark : Brightness.light)
          .glassed(GlassStyle.tinted, const Color(0xFFB18CFF));
      tester.view.physicalSize = const Size(390, 520) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTunesTheme(const MediaQueryData()),
          home: Scaffold(
            backgroundColor: Tones.base,
            body: Padding(
              padding: const EdgeInsets.only(top: 40),
              child: GlassTintPicker(value: 0xFFB18CFF, onChanged: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('shots/glass/picker_${dark ? 'dark' : 'light'}.png'),
      );
    });
  }
}
