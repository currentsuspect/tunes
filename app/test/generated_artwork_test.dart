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

  test('the same input always draws the same sleeve', () {
    // Stability across restarts is the whole point of a generated cover.
    expect(
      GeneratedArtwork.specFor('Lyfë', 'Yeat'),
      GeneratedArtwork.specFor('Lyfë', 'Yeat'),
    );
    expect(
      GeneratedArtwork.specFor('Lyfë', 'Yeat'),
      isNot(GeneratedArtwork.specFor('Afterlyfe', 'Yeat')),
    );
  });

  test('the seed does not depend on String.hashCode', () {
    // Pinned value: if this moves, every generated sleeve changes colour.
    expect(
      GeneratedArtwork.specFor('Continuum', 'John Mayer').seed,
      3260763654,
    );
  });
}
