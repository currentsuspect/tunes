import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/ui/initials.dart';
import 'package:tunes/core/ui/profile_avatar.dart';

void main() {
  Future<void> pumpAvatar(
    WidgetTester tester, {
    String name = '',
    String? path,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ProfileAvatar(name: name, path: path),
      ),
    ),
  );

  testWidgets('a fresh install shows the generic person', (tester) async {
    await pumpAvatar(tester);
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
  });

  testWidgets('a name alone is enough for initials', (tester) async {
    await pumpAvatar(tester, name: 'Dylan Makori');
    expect(find.text('DM'), findsOneWidget);
    expect(find.byIcon(Icons.person_rounded), findsNothing);
  });

  testWidgets('a picture wins over initials', (tester) async {
    await pumpAvatar(tester, name: 'Dylan Makori', path: '/tmp/avatar_x.jpg');
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(InitialsAvatar), findsNothing);
  });
}
