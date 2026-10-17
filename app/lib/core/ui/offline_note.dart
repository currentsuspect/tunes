import '../platform/device.dart';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// What the top of the app says when there is no connection.
///
/// A line in the app's own voice rather than a grey alert box: a small mono
/// "offline" tag, then one sentence about what is still here. Hairline, no
/// fill, so it reads as part of the page and not something sitting on it.
class OfflineNote extends StatelessWidget {
  const OfflineNote({super.key});

  static String get message => 'Showing what is on ${Device.thisOne}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
      child: Semantics(
        liveRegion: true,
        label: 'Offline. $message.',
        excludeSemantics: true,
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: Tones.held,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: Space.sm),
            Text('offline', style: TypeScale.mono),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TypeScale.note.copyWith(
                  fontSize: 14,
                  color: Tones.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
