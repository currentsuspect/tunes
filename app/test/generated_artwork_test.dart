import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/ui/generated_artwork.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  testWidgets('defaults to the artist initial', (tester) async {
    await _pump(tester, const GeneratedArtwork(title: 'Lyfë', artist: 'Yeat'));
    expect(find.text('Y'), findsOneWidget);
  });

  testWidgets('an explicit label wins, so a rail of one act varies', (
    tester,
  ) async {
    // Six Yeat albums all drawing "Y" made the missing-albums rail read as
    // one repeated card.
    await _pump(
      tester,
      const GeneratedArtwork(title: 'Lyfë', artist: 'Yeat', label: 'L'),
    );
    expect(find.text('L'), findsOneWidget);
    expect(find.text('Y'), findsNothing);
  });

  testWidgets('falls back to the title when there is no artist', (
    tester,
  ) async {
    await _pump(
      tester,
      const GeneratedArtwork(title: 'Bassline', artist: 'unknown artist'),
    );
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('the same input always draws the same colours', (tester) async {
    // Stability across restarts is the whole point of a generated cover.
    await _pump(
      tester,
      const Row(
        children: [
          GeneratedArtwork(title: 'Lyfë', artist: 'Yeat', size: 40),
          GeneratedArtwork(title: 'Lyfë', artist: 'Yeat', size: 40),
        ],
      ),
    );
    final boxes = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => (c.decoration as BoxDecoration?)?.gradient)
        .whereType<Gradient>()
        .toList();
    expect(boxes, hasLength(2));
    expect(boxes[0], equals(boxes[1]));
  });
}
