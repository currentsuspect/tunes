import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/nav/root_route_guard.dart';

void main() {
  testWidgets('popping the last route puts the shell back', (tester) async {
    final key = GlobalKey<NavigatorState>();
    var builds = 0;
    Widget shell() {
      builds += 1;
      return const Scaffold(body: Text('shell'));
    }

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        navigatorObservers: [
          RootRouteGuard(
            restore: () => MaterialPageRoute<void>(builder: (_) => shell()),
          ),
        ],
        home: shell(),
      ),
    );
    expect(find.text('shell'), findsOneWidget);

    key.currentState!.pop();
    await tester.pumpAndSettle();

    expect(find.text('shell'), findsOneWidget);
    expect(builds, greaterThan(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an ordinary pop is left alone', (tester) async {
    final key = GlobalKey<NavigatorState>();
    var restored = 0;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        navigatorObservers: [
          RootRouteGuard(
            restore: () {
              restored += 1;
              return MaterialPageRoute<void>(builder: (_) => const Text('x'));
            },
          ),
        ],
        home: const Scaffold(body: Text('shell')),
      ),
    );
    key.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Text('page')),
    );
    await tester.pumpAndSettle();
    key.currentState!.pop();
    await tester.pumpAndSettle();

    expect(find.text('shell'), findsOneWidget);
    expect(restored, 0);
  });
}
