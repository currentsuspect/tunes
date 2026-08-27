import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/main.dart';

void main() {
  testWidgets('library home renders empty state and chrome', (tester) async {
    await tester.pumpWidget(const TunesApp());

    expect(find.text('tunes'), findsOneWidget);
    expect(find.text('No Tracks yet'), findsOneWidget);
    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('Artists'), findsOneWidget);
    expect(find.text('Channels'), findsOneWidget);
    expect(find.textContaining('local'), findsWidgets);
  });

  testWidgets('tab switch swaps empty state label', (tester) async {
    await tester.pumpWidget(const TunesApp());

    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();

    expect(find.text('No Albums yet'), findsOneWidget);
  });
}
