import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/nav/tunes_nav.dart';

/// One panel at a time: opening the panel that is already up is a no-op, and
/// opening another panel replaces it rather than stacking.
///
/// The bug this pins: every opener pushed unconditionally, so opening an album
/// twice left two identical routes and Back landed on the twin.
void main() {
  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('shell'))),
    );
    await tester.pumpAndSettle();
  }

  // NB: never awaited. A push future completes when the route pops, so
  // awaiting it here would hang the test on the pushed panel.
  void openFrom(WidgetTester tester, Finder anchor) {
    openTunesPanel(
      tester.element(anchor),
      TunesPanels.album('rel-1'),
      (_) => const Text('album one'),
    );
  }

  testWidgets('opening the same panel twice opens it once', (tester) async {
    await pumpShell(tester);
    openFrom(tester, find.text('shell'));
    await tester.pumpAndSettle();
    expect(find.text('album one'), findsOneWidget);

    openFrom(tester, find.text('album one'));
    await tester.pumpAndSettle();
    expect(find.text('album one'), findsOneWidget);

    // Shell + one panel, not shell + twins.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('shell'), findsOneWidget);
    expect(find.text('album one'), findsNothing);
  });

  testWidgets('a different panel replaces the open one', (tester) async {
    await pumpShell(tester);
    openFrom(tester, find.text('shell'));
    await tester.pumpAndSettle();

    openTunesPanel(
      tester.element(find.text('album one')),
      TunesPanels.artist('Vax'),
      (_) => const Text('artist vax'),
    );
    await tester.pumpAndSettle();
    expect(find.text('artist vax'), findsOneWidget);
    expect(find.text('album one'), findsNothing);

    // Back skips the replaced panel and lands on the shell.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('shell'), findsOneWidget);
  });

  testWidgets('a panel pushes over the shell, which is not a panel', (
    tester,
  ) async {
    await pumpShell(tester);
    openTunesPanel(
      tester.element(find.text('shell')),
      TunesPanels.nowPlaying,
      (_) => const Text('now playing'),
    );
    await tester.pumpAndSettle();
    expect(find.text('now playing'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('shell'), findsOneWidget);
  });
}
