import 'package:flutter/material.dart';

import '../../core/audio/playhead_clock.dart';
import '../../core/audio/tune_player.dart';
import '../../core/theme/tokens.dart';

/// Where you are in a track, and how you move it.
///
/// Owns its own [PlayheadClock] so the fill advances every frame rather than
/// four times a second, and so the elapsed label counts smoothly instead of
/// jumping a second at a time.
///
/// While a drag is in progress the clock is ignored and the local value wins:
/// otherwise the thumb fights the finger, snapping back to real playback
/// between frames until the seek lands.
class Scrubber extends StatefulWidget {
  const Scrubber({super.key, required this.player, required this.duration});

  final TunePlayer player;
  final Duration duration;

  @override
  State<Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<Scrubber>
    with SingleTickerProviderStateMixin {
  late final PlayheadClock _playhead;

  /// Non-null only while a drag is in progress.
  double? _dragMs;

  @override
  void initState() {
    super.initState();
    _playhead = PlayheadClock(player: widget.player, vsync: this);
  }

  @override
  void dispose() {
    _playhead.dispose();
    super.dispose();
  }

  String _label(Duration d) {
    final s = d.inSeconds;
    final m = (s ~/ 60).toString().padLeft(2, '0');
    return '$m:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // Clamp is declared on num and returns num, so toDouble comes after it.
    final maxMs = widget.duration.inMilliseconds
        .clamp(1, double.infinity)
        .toDouble();
    final dragging = _dragMs != null;
    return ValueListenableBuilder<Duration>(
      valueListenable: _playhead,
      builder: (context, live, _) {
        final ms = _dragMs ?? live.inMilliseconds.toDouble();
        final shown = ms.clamp(0, maxMs).toDouble();
        return Row(
          children: [
            Text(
              // Reads the dragged position, not the playing one: a scrubber
              // whose label lags the thumb makes you aim by feel.
              _label(Duration(milliseconds: shown.round())),
              style: TypeScale.caption.copyWith(
                color: dragging ? Tones.text : null,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: dragging ? 5 : 3,
                  activeTrackColor: Tones.primary,
                  // A bare Slider inherits a rail colour invisible on this
                  // background, so at 0:00 the thumb looked like a dot
                  // floating between two timestamps with no track at all.
                  inactiveTrackColor: Tones.surfaceRaised,
                  thumbColor: Tones.primary,
                  overlayColor: Tones.primary.withValues(alpha: 0.15),
                  // Small at rest, larger under a finger. The visible control
                  // stays thin; the touch target never was the thin part --
                  // Slider claims its full height regardless.
                  thumbShape: RoundSliderThumbShape(
                    enabledThumbRadius: dragging ? 9 : 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 18,
                  ),
                ),
                child: Slider(
                  // Position can briefly exceed duration on a stream; Slider
                  // asserts if it does.
                  value: shown,
                  max: maxMs,
                  onChangeStart: (v) => setState(() => _dragMs = v),
                  onChanged: (v) => setState(() => _dragMs = v),
                  // Seek once, on release. Seeking every frame of a drag
                  // restarts the decoder dozens of times and, on a streamed
                  // track, refetches as many ranges -- the thumb is smooth
                  // either way, and this way the audio is too.
                  onChangeEnd: (v) {
                    widget.player.seek(Duration(milliseconds: v.round()));
                    setState(() => _dragMs = null);
                  },
                ),
              ),
            ),
            Text(
              _label(widget.duration),
              style: TypeScale.caption.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        );
      },
    );
  }
}
