import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../core/lyrics/adlibs.dart';
import '../../core/lyrics/lrc_parser.dart';
import '../../core/lyrics/word_motion.dart';
import '../../core/theme/tokens.dart';

/// One lyric line rendered word by word, with the highlight sweeping across
/// the word currently being sung.
///
/// Words already sung stay lit, the word in progress is filled left-to-right
/// in proportion to how far through it the playhead is, and the rest stay dim.
/// A word rises a touch while it is sung, a held note glows for as long as it
/// is held, and each settles when its own end comes (see word_motion.dart).
/// No animation controller per word: every frame is drawn from the playhead.
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
    this.textAlign = TextAlign.start,
    this.wrapAlignment = WrapAlignment.start,
    this.onWordTap,
  });

  /// Tapping a word jumps to it: the time the word starts, to the
  /// millisecond. Null leaves the line to its own tap (jump to the line).
  final ValueChanged<Duration>? onWordTap;

  /// Which edge the line hangs from, for a voice that sings from the right.
  final TextAlign textAlign;
  final WrapAlignment wrapAlignment;

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
      final rest = base.copyWith(
        color: restOpacity != null
            ? Tones.text.withValues(alpha: restOpacity)
            : isPast
            ? Tones.textMuted.withValues(alpha: 0.6)
            : Tones.text.withValues(alpha: 0.85),
        fontWeight: FontWeight.w400,
      );
      final tap = onWordTap;
      if (tap == null) {
        return Text(line.text, textAlign: textAlign, style: rest);
      }
      // Still static (no playhead), just in tappable words.
      return _rows(
        line,
        (i, adlib, last) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => tap(line.words[i].start),
          child: Text(
            last ? line.words[i].text : '${line.words[i].text} ',
            style: adlib ? _adlibStyle(rest) : rest,
          ),
        ),
      );
    }

    return ValueListenableBuilder<Duration>(
      valueListenable: playhead,
      builder: (context, position, _) {
        final style = base.copyWith(fontWeight: FontWeight.w600);
        return _rows(
          line,
          (i, adlib, last) => _tappable(
            i,
            _Word(
              // The trailing space belongs to the word so wrapping breaks in
              // the right places; a separate spacing gap would let a line
              // wrap before a space instead of after it.
              text: last ? line.words[i].text : '${line.words[i].text} ',
              style: adlib ? _adlibStyle(style) : style,
              // Each word by its own time, not by "the latest to start": an
              // ad-lib under the main vocal lights while the vocal does.
              motion: wordMotion(
                start: line.words[i].start,
                end: lrc.wordEndOf(lineIndex, i, trackEnd: trackEnd),
                position: position,
              ),
            ),
          ),
        );
      },
    );
  }
}

extension on KaraokeLine {
  /// The main words on one row and the ad-libs, smaller, on a row of their
  /// own beneath (see adlibs.dart). A line with no ad-libs is one row.
  Widget _rows(
    LrcLine line,
    Widget Function(int i, bool adlib, bool last) word,
  ) {
    final mask = adlibMask([for (final w in line.words) w.text]);
    final mainAt = [
      for (var i = 0; i < mask.length; i++)
        if (!mask[i]) i,
    ];
    final adlibAt = [
      for (var i = 0; i < mask.length; i++)
        if (mask[i]) i,
    ];
    final main = [for (final i in mainAt) word(i, false, i == mainAt.last)];
    if (main.length == line.words.length) {
      return Wrap(alignment: wrapAlignment, runSpacing: 2, children: main);
    }
    // Stretched, so the ad-lib row spans the line and can sit at its far side.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(alignment: wrapAlignment, runSpacing: 2, children: main),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Wrap(
            // The other side of the line from the lead: an answer, not a
            // continuation.
            alignment: wrapAlignment == WrapAlignment.end
                ? WrapAlignment.start
                : WrapAlignment.end,
            runSpacing: 2,
            children: [
              for (final i in adlibAt) word(i, true, i == adlibAt.last),
            ],
          ),
        ),
      ],
    );
  }

  TextStyle _adlibStyle(TextStyle s) => s.copyWith(
    fontSize: (s.fontSize ?? 20) * 0.72,
    fontStyle: FontStyle.italic,
  );

  Widget _tappable(int i, Widget child) {
    final tap = onWordTap;
    if (tap == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => tap(lrc.lines[lineIndex].words[i].start),
      child: child,
    );
  }
}

class _Word extends StatelessWidget {
  const _Word({required this.text, required this.style, required this.motion});

  final String text;
  final TextStyle style;
  final WordMotion motion;

  /// How far a sung word rises, as a share of its size.
  static const _liftScale = 0.06;

  @override
  Widget build(BuildContext context) {
    final glow = motion.glow;
    final lit = style.copyWith(
      color: Tones.text.withValues(alpha: KaraokeLine._litOpacity),
      shadows: glow <= 0
          ? null
          : [
              Shadow(
                color: Tones.primary.withValues(alpha: 0.55 * glow),
                blurRadius: 4 + 14 * glow,
              ),
            ],
    );
    final Widget word;
    if (motion.fill <= 0) {
      word = Text(
        text,
        style: style.copyWith(
          color: Tones.text.withValues(alpha: KaraokeLine._dimOpacity),
        ),
      );
    } else if (motion.fill >= 1) {
      word = Text(text, style: lit);
    } else {
      // Mid-word: one gradient with both stops at the same offset, which
      // paints a hard edge that moves. Cheaper and steadier than a clip.
      word = ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (rect) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Tones.text.withValues(alpha: KaraokeLine._litOpacity),
            Tones.text.withValues(alpha: KaraokeLine._dimOpacity),
          ],
          stops: [motion.fill, motion.fill],
        ).createShader(rect),
        // srcIn keeps the shader only where the glyphs are, so the child has
        // to be painted opaque for the colours above to survive.
        child: Text(text, style: lit.copyWith(color: Colors.white)),
      );
    }
    if (motion.lift <= 0) return word;
    // A transform, not a size change: the line never reflows under the eye.
    return Transform.scale(
      scale: 1 + _liftScale * motion.lift,
      alignment: Alignment.bottomCenter,
      child: word,
    );
  }
}
