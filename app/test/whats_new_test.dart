import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/domain/whats_new.dart';
import 'package:tunes/features/whats_new/whats_new_page.dart';

void main() {
  testWidgets('lists everything that is new, and says who it is from', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: WhatsNewPage(onDone: () {})));
    expect(find.text(kWhatsNewTitle), findsOneWidget);
    expect(find.textContaining('A gift from Dylan'), findsOneWidget);

    // Scrolled rather than assumed on screen: it is a long page.
    for (final e in kWhatsNew) {
      await tester.scrollUntilVisible(find.text(e.title), 200);
      expect(find.text(e.title), findsOneWidget, reason: e.title);
    }
    await tester.scrollUntilVisible(find.text(kWhatsNewSignoff), 200);
    expect(find.text(kWhatsNewSignoff), findsOneWidget);
  });

  testWidgets('Let\'s go finishes it', (tester) async {
    var done = 0;
    await tester.pumpWidget(
      MaterialApp(home: WhatsNewPage(onDone: () => done += 1)),
    );
    await tester.tap(find.text('Let\'s go'));
    expect(done, 1);
  });

  test('every entry has a title and something to say', () {
    for (final e in kWhatsNew) {
      expect(e.title.trim(), isNotEmpty);
      expect(e.body.trim().length, greaterThan(20), reason: e.title);
    }
    // Titles are unique, or the page reads as a mistake.
    expect(kWhatsNew.map((e) => e.title).toSet().length, kWhatsNew.length);
  });

  test('the pack has an id, so a later one is shown separately', () {
    expect(kWhatsNewId, isNotEmpty);
  });
}
