import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/ui/tunes_refresh.dart';

void main() {
  Widget app(Future<void> Function() onRefresh, {int items = 30}) =>
      MaterialApp(
        home: Scaffold(
          body: TunesRefreshList(
            onRefresh: onRefresh,
            children: [
              for (var i = 0; i < items; i++)
                SizedBox(height: 60, child: Text('Row $i')),
            ],
          ),
        ),
      );

  testWidgets('pulling down far enough refreshes, and says so', (tester) async {
    var calls = 0;
    final gate = Completer<void>();
    await tester.pumpWidget(
      app(() {
        calls += 1;
        return gate.future;
      }),
    );

    await tester.drag(find.text('Row 0'), const Offset(0, 260));
    await tester.pump();
    // It springs back to its resting height first, which takes most of a second.
    for (var i = 0; i < 9; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Still working: it says so, and has called for the refresh once.
    expect(calls, 1);
    expect(find.text('Syncing'), findsOneWidget);

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Up to date'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('a short pull does nothing', (tester) async {
    var calls = 0;
    await tester.pumpWidget(app(() async => calls += 1));
    await tester.drag(find.text('Row 0'), const Offset(0, 30));
    await tester.pumpAndSettle();
    expect(calls, 0);
  });

  testWidgets('says what a pull will do before it is far enough', (
    tester,
  ) async {
    await tester.pumpWidget(app(() async {}));
    final g = await tester.startGesture(tester.getCenter(find.text('Row 1')));
    await g.moveBy(const Offset(0, 40));
    await tester.pump();
    expect(find.text('Pull to sync'), findsOneWidget);
    await g.moveBy(const Offset(0, 140));
    await tester.pump();
    expect(find.text('Let go to sync'), findsOneWidget);
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('works on a list shorter than the screen', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      app(() async {
        calls += 1;
      }, items: 2),
    );
    await tester.drag(find.text('Row 0'), const Offset(0, 260));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });
}
