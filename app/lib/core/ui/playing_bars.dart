import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The mark on the song that is playing: a few bars that bounce with the music.
///
/// Paused, they stand still, the same bars at rest, so the row still says "this
/// is the one" without moving. It replaces a waveform glyph that looked drawn on
/// and did not change when playback did.
///
/// Bars are phased differently and ride different curves, so they never move in
/// lockstep, which is what makes it read as a meter and not a spinner. Reduced
/// motion holds them still, as paused does.
class PlayingBars extends StatefulWidget {
  const PlayingBars({
    super.key,
    required this.playing,
    this.color,
    this.size = 18,
  });

  final bool playing;

  /// Null takes the look's accent.
  final Color? color;

  /// Height of the whole mark; the width follows.
  final double size;

  @override
  State<PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends State<PlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  /// Where each bar sits at rest, as a fraction of the height.
  static const _rest = [0.45, 0.85, 0.6, 0.35];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(PlayingBars old) {
    super.didUpdateWidget(old);
    if (old.playing != widget.playing) _sync();
  }

  /// Runs the clock only while the bars really move. A clock left ticking under
  /// still bars keeps asking for frames for nothing, and holds up anything that
  /// waits for the screen to settle.
  void _sync() {
    final moves = widget.playing && !MediaQuery.disableAnimationsOf(context);
    if (moves) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// A bar's height now: its rest height with a swing around it, each bar on its
  /// own phase and its own speed multiple.
  double _height(int i, double t) {
    final speed = [1.0, 2.0, 1.0, 3.0][i];
    final phase = [0.0, 0.3, 0.6, 0.15][i];
    final wave = (t * speed + phase) % 1.0;
    // A triangle wave, eased, then mapped between 0.2 and 1.
    final tri = wave < 0.5 ? wave * 2 : (1 - wave) * 2;
    final eased = Curves.easeInOut.transform(tri);
    return 0.2 + 0.8 * eased;
  }

  @override
  Widget build(BuildContext context) {
    final still = !widget.playing || MediaQuery.disableAnimationsOf(context);
    final h = widget.size;
    final barW = h * 0.17;
    final gap = h * 0.11;
    return Semantics(
      label: widget.playing ? 'Playing' : 'Paused',
      excludeSemantics: true,
      child: SizedBox(
        width: barW * 4 + gap * 3,
        height: h,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < 4; i++)
                  Container(
                    width: barW,
                    height: h * (still ? _rest[i] : _height(i, _c.value)),
                    decoration: BoxDecoration(
                      color: widget.color ?? Tones.primary,
                      borderRadius: BorderRadius.circular(barW / 2),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
