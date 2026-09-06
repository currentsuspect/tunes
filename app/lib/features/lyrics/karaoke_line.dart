import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/audio/playhead.dart';
import '../../core/audio/tune_player.dart';
import '../../core/lyrics/lrc_parser.dart';
import '../../core/theme/tokens.dart';

/// A smooth playhead for the lyric view.
///
/// The player notifies at most four times a second, which is too coarse to
/// sweep a highlight across a word. This takes each report as a fix and
/// projects between them on a ticker, so only the widgets that listen here
/// repaint at frame rate -- the lyric list itself does not.
///
/// The ticker only runs while something is playing, so a paused sheet costs
/// nothing.
class PlayheadClock extends ValueNotifier<Duration> {
  PlayheadClock({required this.player, required TickerProvider vsync})
    : super(player.position) {
    _ticker = vsync.createTicker(_onTick);
    player.addListener(_onPlayerChanged);
    _onPlayerChanged();
  }

  final TunePlayer player;
  late final Ticker _ticker;
  Duration _reported = Duration.zero;
  DateTime _reportedAt = DateTime.now();

  void _onPlayerChanged() {
    _reported = player.position;
    _reportedAt = DateTime.now();
    if (player.playing && !_ticker.isActive) {
      _ticker.start();
    } else if (!player.playing && _ticker.isActive) {
      _ticker.stop();
    }
    if (!player.playing) value = _reported;
  }

  void _onTick(Duration _) {
    value = projectPosition(
      reported: _reported,
      reportedAt: _reportedAt,
      now: DateTime.now(),
      playing: player.playing,
      duration: player.duration,
    );
  }

  @override
  void dispose() {
    player.removeListener(_onPlayerChanged);
    _ticker.dispose();
    super.dispose();
  }
}

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
  });

  final Lrc lrc;
  final int lineIndex;
  final ValueListenable<Duration> playhead;
  final Duration? trackEnd;
  final bool isActive;
  final bool isPast;
  final TextStyle? style;

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
          color: isPast
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
