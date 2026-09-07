import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// What a screen says when it has nothing to show.
///
/// One shape for all of them, because an empty screen is where an app is
/// judged most harshly: it is the moment there is nothing to look at except
/// how the app talks to you.
///
/// Two rules for the copy at every call site. Say which kind of empty this is
/// -- "you have not done this yet" and "there is nothing here" and "this
/// failed" are three different sentences. And never end on the bad news:
/// finish with what to do, or with why nothing is wrong.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Tones.surfaceRaised,
                borderRadius: BorderRadius.circular(RadiusTokens.control),
              ),
              child: Icon(icon, size: 32, color: Tones.textMuted),
            ),
            const SizedBox(height: Space.lg),
            Text(title, style: TypeScale.title, textAlign: TextAlign.center),
            const SizedBox(height: Space.sm),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TypeScale.body.copyWith(height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
