import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A section's name in the serif, with a line under it in the personal voice
/// saying why it is there, and an optional action at the end.
class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    required this.padding,
    this.note,
    this.trailing,
  });

  final String title;
  final double padding;
  final String? note;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        padding,
        Space.xl,
        trailing == null ? padding : Space.md,
        Space.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TypeScale.heading),
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      note!,
                      style: TypeScale.note.copyWith(
                        fontSize: 14,
                        color: Tones.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A small outlined action: Play on a rail, Shuffle above a list.
class PlayPill extends StatelessWidget {
  const PlayPill({
    super.key,
    required this.onTap,
    this.label = 'Play',
    this.icon = Icons.play_arrow_rounded,
  });

  final VoidCallback onTap;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(99),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.md,
              vertical: Space.sm - 2,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: Tones.hairline),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: Tones.text),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: Faces.body,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Tones.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The name of a record or song under its sleeve: bright, because it is the
/// thing you are choosing by. It was set in the muted body colour, so every
/// card's title was the dimmest text on the page.
TextStyle cardTitleStyle() => TypeScale.title.copyWith(
  fontSize: 14,
  fontVariations: const [FontVariation('wght', 500)],
  fontWeight: FontWeight.w500,
);

/// How much of a record you hold, as a ring with the count inside.
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.have, required this.total});

  final int have;
  final int total;

  @override
  Widget build(BuildContext context) {
    final value = total <= 0 ? 0.0 : (have / total).clamp(0.0, 1.0);
    return SizedBox(
      width: 42,
      height: 42,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: value,
            strokeWidth: 3,
            backgroundColor: Tones.hairline,
            color: Tones.primary,
          ),
          Text('$have/$total', style: TypeScale.mono.copyWith(fontSize: 9)),
        ],
      ),
    );
  }
}
