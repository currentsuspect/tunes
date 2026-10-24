import 'package:flutter/material.dart';

import '../../core/audio/sleep_timer.dart';
import '../../core/theme/looks.dart';
import '../../core/theme/tokens.dart';

/// Stop playing in 15, 30, 45 minutes, an hour, at the end of this song or
/// this album; fade out over the last minute (design approved 24 Oct).
class SleepSheet extends StatelessWidget {
  const SleepSheet({super.key, required this.sleep});

  final SleepTimer sleep;

  static Future<void> show(BuildContext context, SleepTimer sleep) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Tones.surface,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(RadiusTokens.card),
        ),
        side: Looks.current.kind == LookKind.crayon
            ? BorderSide(color: Tones.text, width: 2)
            : BorderSide.none,
      ),
      builder: (_) => SleepSheet(sleep: sleep),
    );
  }

  @override
  Widget build(BuildContext context) {
    final crayon = Looks.current.kind == LookKind.crayon;
    final moon = crayon ? Looks.current.crayons[1] : Tones.primary;
    return ListenableBuilder(
      listenable: sleep,
      builder: (context, _) {
        final left = sleep.remaining;
        Widget choice(String label, bool on, VoidCallback onTap) =>
            _Choice(label: label, on: on, onTap: onTap);
        void pick(VoidCallback set) {
          set();
          Navigator.of(context).maybePop();
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.lg,
              Space.md,
              Space.lg,
              Space.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.bedtime_rounded, color: moon, size: 26),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(
                        sleep.active
                            ? _activeTitle(sleep, left)
                            : 'Stop playing',
                        style: TypeScale.heading.copyWith(fontSize: 22),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.md),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: Space.sm,
                  crossAxisSpacing: Space.sm,
                  childAspectRatio: 1.9,
                  children: [
                    for (final m in const [15, 30, 45])
                      choice(
                        '$m min',
                        false,
                        () => pick(() => sleep.start(Duration(minutes: m))),
                      ),
                    choice(
                      '1 hour',
                      false,
                      () => pick(() => sleep.start(const Duration(hours: 1))),
                    ),
                    choice(
                      'End of song',
                      sleep.mode == SleepMode.endOfSong,
                      () => pick(sleep.endOfSong),
                    ),
                    choice(
                      'End of album',
                      sleep.mode == SleepMode.endOfAlbum,
                      () => pick(sleep.endOfAlbum),
                    ),
                  ],
                ),
                const SizedBox(height: Space.sm),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: sleep.fade,
                  onChanged: (v) => sleep.fade = v,
                  title: Text('Fade out slowly', style: TypeScale.title),
                  subtitle: Text(
                    'The last minute gets quieter, then stops.',
                    style: TypeScale.caption,
                  ),
                ),
                if (sleep.active) ...[
                  const SizedBox(height: Space.sm),
                  Row(
                    children: [
                      if (sleep.mode == SleepMode.timed) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: sleep.extend,
                            style: _outline(Tones.text),
                            child: const Text('+10 min'),
                          ),
                        ),
                        const SizedBox(width: Space.sm),
                      ],
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => pick(sleep.cancel),
                          style: _outline(Tones.warn),
                          child: const Text('Turn off'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  static String _activeTitle(SleepTimer s, Duration? left) => switch (s.mode) {
    SleepMode.timed => 'Sleeping in ${sleepClock(left ?? Duration.zero)}',
    SleepMode.endOfSong => 'Stopping after this song',
    SleepMode.endOfAlbum => 'Stopping after this album',
    SleepMode.off => 'Stop playing',
  };

  static ButtonStyle _outline(Color c) {
    final crayon = Looks.current.kind == LookKind.crayon;
    return OutlinedButton.styleFrom(
      foregroundColor: c,
      minimumSize: const Size.fromHeight(48),
      side: BorderSide(
        color: crayon ? c : Tones.hairline,
        width: crayon ? 2 : 1,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(crayon ? 14 : RadiusTokens.control),
      ),
      textStyle: TypeScale.title.copyWith(fontSize: 15),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final crayon = Looks.current.kind == LookKind.crayon;
    final fill = on
        ? (crayon ? Looks.current.crayons[1] : Tones.primary)
        : Colors.transparent;
    final ink = on
        ? (crayon ? const Color(0xFF22201C) : Tones.onPrimary)
        : Tones.text;
    return Material(
      color: fill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(crayon ? 14 : RadiusTokens.card),
        side: BorderSide(
          color: crayon ? Tones.text : Tones.hairline,
          width: crayon ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(crayon ? 14 : RadiusTokens.card),
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TypeScale.title.copyWith(fontSize: 15, color: ink),
          ),
        ),
      ),
    );
  }
}
