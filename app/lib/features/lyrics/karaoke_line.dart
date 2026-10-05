import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../core/lyrics/lrc_parser.dart';
import '../../core/theme/tokens.dart';

/// One lyric line rendered word by word, with the highlight sweeping across
/// the word currently being sung.
///
/// Words already sung stay lit, the word in progress is filled left-to-right
/// in proportion to how far through it the playhead is, and the rest stay dim.
/// That is the whole effect: no animation controller per word, just a gradient
/// whose hard stop moves.
class KaraokeLine extends StatelessWidget {
  const KaraokeLine({
    super.key,
    required this.lrc,
    required this.lineIndex,
    required this.playhead,
    required this.trackEnd,
    required this.isActive,
    required this.isPast,
    this.style,
    this.restOpacity,
  });

  final Lrc lrc;
  final int lineIndex;
  final ValueListenable<Duration> playhead;
  final Duration? trackEnd;
  final bool isActive;
  final bool isPast;
  final TextStyle? style;

  /// How bright this line is when it is not the one being sung. Null keeps the
  /// old past/upcoming defaults; the lyrics screen passes a value that fades
  /// with distance from the current line.
  final double? restOpacity;

  static const _litOpacity = 1.0;
  static const _dimOpacity = 0.35;

  @override
  Widget build(BuildContext context) {
    final line = lrc.lines[lineIndex];
    final base = (style ?? TypeScale.title).copyWith(height: 1.3);

    // A line that is not the one being sung has nothing to sweep: it is either
    // wholly behind us or wholly ahead. Rendering it as plain text keeps the
    // sweep cost to a single line no matter how long the lyrics are.
    if (!isActive) {
      return Text(
        line.text,
        style: base.copyWith(
          color: restOpacity != null
              ? Tones.text.withValues(alpha: restOpacity)
              : isPast
              ? Tones.textMuted.withValues(alpha: 0.6)
              : Tones.text.withValues(alpha: 0.85),
          fontWeight: FontWeight.w400,
        ),
      );
    }

    return ValueListenableBuilder<Duration>(
      valueListenable: playhead,
      builder: (context, position, _) {
        final active = LrcParser.activeWordIndex(lrc, lineIndex, position);
        return Wrap(
          spacing: 0,
          runSpacing: 2,
          children: [
            for (var i = 0; i < line.words.length; i++)
              _Word(
                // The trailing space belongs to the word so wrapping breaks in
                // the right places; a separate spacing gap would let a line
                // wrap before a space instead of after it.
                text: i == line.words.length - 1
                    ? line.words[i].text
                    : '${line.words[i].text} ',
                style: base.copyWith(fontWeight: FontWeight.w600),
                progress: active == null
                    ? 0
                    : i < active
                    ? 1
                    : i > active
                    ? 0
                    : LrcParser.wordProgress(
                        lrc,
                        lineIndex,
                        i,
                        position,
                        trackEnd: trackEnd,
                      ),
              ),
          ],
        );
      },
    );
  }
}

class _Word extends StatelessWidget {
  const _Word({
    required this.text,
    required this.style,
    required this.progress,
  });

  final String text;
  final TextStyle style;
  final double progress;

  @override
  Widget build(BuildContext context) {
    if (progress <= 0) {
      return Text(
        text,
        style: style.copyWith(
          color: Tones.text.withValues(alpha: KaraokeLine._dimOpacity),
        ),
      );
    }
    if (progress >= 1) {
      return Text(
        text,
        style: style.copyWith(
          color: Tones.text.withValues(alpha: KaraokeLine._litOpacity),
        ),
      );
    }
    // Mid-word: one gradient with both stops at the same offset, which paints
    // a hard edge that moves. Cheaper and steadier than animating a clip.
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Tones.text.withValues(alpha: KaraokeLine._litOpacity),
          Tones.text.withValues(alpha: KaraokeLine._dimOpacity),
        ],
        stops: [progress, progress],
      ).createShader(rect),
      // srcIn keeps the shader only where the glyphs are, so the child has to
      // be painted opaque for the colours above to survive.
      child: Text(text, style: style.copyWith(color: Colors.white)),
    );
  }
}
