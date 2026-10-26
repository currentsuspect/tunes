import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/theme/looks.dart';
import 'package:tunes/core/ui/glass_dock.dart';
import 'package:tunes/core/ui/tunes_nav_bar.dart';

const _items = [
  TunesNavItem(glyph: NavGlyph.home, label: 'Home'),
  TunesNavItem(glyph: NavGlyph.discover, label: 'Discover'),
  TunesNavItem(glyph: NavGlyph.search, label: 'Search'),
  TunesNavItem(glyph: NavGlyph.library, label: 'Library'),
];

Widget _host(Widget dock) => MaterialApp(
  home: Scaffold(
    body: Align(alignment: Alignment.bottomCenter, child: dock),
  ),
);

void main() {
  late TunesLook before;
  setUp(() {
    before = Looks.current;
    Looks.current = Looks.glass.dark;
  });
  tearDown(() => Looks.current = before);

  testWidgets('dragging the droplet along the bar picks the tab it is let go '
      'on', (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(
      _host(
        GlassDock(
          items: _items,
          selectedIndex: 0,
          onSelected: picked.add,
          minimized: false,
          onExpand: () {},
          backing: Colors.transparent,
        ),
      ),
    );
    final home = tester.getCenter(find.text('Home'));
    final library = tester.getCenter(find.text('Library'));
    final drag = await tester.startGesture(home);
    await drag.moveTo(Offset((home.dx + library.dx) / 2, home.dy));
    await drag.moveTo(library);
    await drag.up();
    await tester.pumpAndSettle();
    expect(picked, [3]);
  });

  testWidgets('minimized with something playing, the tabs are one circle '
      'that opens them, and the player sits beside it', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      _host(
        GlassDock(
          items: _items,
          selectedIndex: 2,
          onSelected: (_) {},
          minimized: true,
          onExpand: () => opened++,
          backing: Colors.transparent,
          mini: (fold) => SizedBox.expand(
            key: const Key('mini'),
            child: Text('fold $fold'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('fold 1.0'), findsOneWidget);
    final circle = find.bySemanticsLabel('Show tabs');
    expect(circle, findsOneWidget);
    final mini = tester.getRect(find.byKey(const Key('mini')));
    final tabs = tester.getRect(circle);
    expect(tabs.width, tabs.height, reason: 'a circle');
    expect(mini.left, greaterThan(tabs.right), reason: 'beside it');
    expect(mini.top, moreOrLessEquals(tabs.top), reason: 'one row');
    await tester.tap(circle);
    expect(opened, 1);
  });

  testWidgets('with nothing playing, minimizing only folds the labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        GlassDock(
          items: _items,
          selectedIndex: 0,
          onSelected: (_) {},
          minimized: true,
          onExpand: () {},
          backing: Colors.transparent,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Show tabs'), findsNothing);
    for (final item in _items) {
      expect(find.bySemanticsLabel(item.label), findsOneWidget);
    }
  });
}
