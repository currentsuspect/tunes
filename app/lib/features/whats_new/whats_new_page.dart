import '../../core/platform/device.dart';

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/ui/cover_tint.dart';
import '../../domain/whats_new.dart';

/// Everything that is new, as a page you read once and are glad you did.
///
/// Shown the first time a release opens, and again from Settings. A page, not a
/// dialog: there is a lot to say and none of it should be cut off to fit a box.
class WhatsNewPage extends StatelessWidget {
  const WhatsNewPage({super.key, required this.onDone});

  /// Called when the reader says they are done. The caller records that it has
  /// been seen and leaves the page.
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tones.base,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AmbientGlow(tint: Tones.primary, strength: 0.34),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      Space.lg,
                      Space.xl,
                      Space.lg,
                      Space.lg,
                    ),
                    children: [
                      Text(
                        'NEW IN TUNES',
                        style: TypeScale.mono.copyWith(letterSpacing: 1.6),
                      ),
                      const SizedBox(height: Space.sm),
                      Text(
                        kWhatsNewTitle,
                        style: TypeScale.wordmark.copyWith(fontSize: 46),
                      ),
                      const SizedBox(height: Space.md),
                      Text(
                        kWhatsNewIntro,
                        style: TypeScale.note.copyWith(
                          fontSize: 17,
                          color: Tones.text,
                        ),
                      ),
                      const SizedBox(height: Space.xl),
                      for (var i = 0; i < kWhatsNew.length; i++)
                        _Entry(entry: kWhatsNew[i]),
                      const SizedBox(height: Space.lg),
                      Text(
                        kWhatsNewSignoff,
                        style: TypeScale.note.copyWith(
                          fontSize: 15,
                          color: Tones.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    Space.sm,
                    Space.lg,
                    Space.lg,
                  ),
                  child: FilledButton(
                    onPressed: onDone,
                    style: FilledButton.styleFrom(
                      backgroundColor: Tones.text,
                      foregroundColor: Tones.base,
                      padding: const EdgeInsets.symmetric(vertical: Space.md),
                    ),
                    child: const Text('Let\'s go'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({required this.entry});

  final WhatsNewEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.title, style: TypeScale.heading.copyWith(fontSize: 21)),
          const SizedBox(height: Space.xs),
          Text(
            // Written for a phone; on a computer it says computer.
            entry.body.replaceAll('phone', Device.noun),
            style: TypeScale.body.copyWith(height: 1.5, fontSize: 14.5),
          ),
        ],
      ),
    );
  }
}
