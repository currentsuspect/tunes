import 'package:flutter/material.dart';

import '../theme/looks.dart';
import '../theme/tokens.dart';
import 'look_extras.dart';

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

  /// Room: the serif. Crayon: the bouncy hand, underlined with a squiggle in
  /// a crayon picked by the title. Noir: fine print, gold small capitals
  /// under a hairline.
  List<Widget> _title() {
    final look = Looks.current;
    switch (look.kind) {
      case LookKind.room:
        return [Text(title, style: TypeScale.heading)];
      case LookKind.crayon:
        final c = look.crayons[title.hashCode.abs() % look.crayons.length];
        return [
          IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: TypeScale.heading),
                CrayonSquiggle(color: c),
              ],
            ),
          ),
        ];
      case LookKind.noir:
        return [
          Container(height: 1, color: Tones.hairline),
          const SizedBox(height: Space.sm),
          Text(
            title.toUpperCase(),
            style: TypeScale.mono.copyWith(
              color: Tones.primary,
              letterSpacing: 2.2,
              fontSize: 11,
            ),
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    // The action sits beside the heading, centred on it, and the note runs
    // the full width under both. The action used to sit beside the note at
    // the bottom, which squeezed the note onto two lines and left the
    // button floating away from the thing it plays (24 Oct, approved).
    return Padding(
      padding: EdgeInsets.fromLTRB(
        padding,
        Space.xl,
        trailing == null ? padding : Space.md,
        Space.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _title(),
                ),
              ),
              ?trailing,
            ],
          ),
          if (note != null && Looks.current.kind != LookKind.noir)
            Padding(
              padding: EdgeInsets.only(
                top: 2,
                right: trailing == null ? 0 : padding - Space.md,
              ),
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
    );
  }
}

/// Play all of a shelf: a round button beside its heading. Crayon colours it
/// in with the heading's crayon and gives it an ink edge.
class SectionPlay extends StatelessWidget {
  const SectionPlay({super.key, required this.label, required this.onTap});

  /// What it plays, for the screen reader ("Listen again").
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final look = Looks.current;
    final crayon = look.kind == LookKind.crayon;
    final fill = crayon
        ? look.crayons[label.hashCode.abs() % look.crayons.length]
        : Tones.surfaceRaised;
    return Tooltip(
      message: 'Play $label',
      child: Material(
        color: fill,
        shape: CircleBorder(
          side: BorderSide(
            color: crayon ? Tones.text : Tones.hairline,
            width: crayon ? 2 : 1,
          ),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: 44,
            child: Icon(
              Icons.play_arrow_rounded,
              size: 24,
              color: crayon ? const Color(0xFF22201C) : Tones.text,
            ),
          ),
        ),
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
