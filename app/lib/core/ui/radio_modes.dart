import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/settings_store.dart';
import '../radio/session.dart';
import '../theme/tokens.dart';
import 'pressable.dart';

/// The radio's three modes, one tap each (docs/IDEAS.md, agreed 5 Oct):
/// what plays when the queue runs out. Shown in the queue, where the radio
/// takes over, and on Discover.
class RadioModes extends StatelessWidget {
  const RadioModes({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsets padding;

  static String lineFor(RadioMode m) => switch (m) {
    RadioMode.stayClose =>
      'More of what is playing, with a stretch now and then.',
    RadioMode.drift => 'Wanders from what is playing, and comes back.',
    RadioMode.surprise => 'Further out, often: new to you, and next door.',
  };

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.maybeOf(context);
    if (settings == null) return const SizedBox.shrink();
    final mode = settings.radioMode;
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            settings.radioAutoplay ? 'THEN RADIO' : 'RADIO IS OFF IN SETTINGS',
            style: TypeScale.mono,
          ),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final m in RadioMode.values)
                _ModeChip(
                  label: m.label,
                  selected: m == mode,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    settings.setRadioMode(m);
                  },
                ),
            ],
          ),
          const SizedBox(height: Space.xs),
          AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            child: Text(
              lineFor(mode),
              key: ValueKey(mode),
              style: TypeScale.caption,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? Tones.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(99),
        child: PressRow(
          onTap: onTap,
          borderRadius: BorderRadius.circular(99),
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? Tones.primary : Tones.hairline,
              ),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              label,
              style: TypeScale.caption.copyWith(
                color: selected ? Tones.onPrimary : Tones.text,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
