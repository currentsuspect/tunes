import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/audio/playhead_clock.dart';
import '../../core/audio/tune_player.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/looks.dart';
import '../../core/ui/cover_tint.dart';
import '../../core/ui/look_extras.dart';

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
        final accent = AccentScope.of(context);
        final times = TypeScale.mono.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SliderTheme(
              data: SliderThemeData(
                // Crayon's stroke is thick; Noir's line is a hairline with a
                // bead (both drawn by LookTrackShape).
                trackHeight: switch (Looks.current.kind) {
                  LookKind.crayon => 9,
                  LookKind.noir => 8,
                  LookKind.room => dragging ? 5 : 3,
                },
                activeTrackColor: accent,
                // A bare Slider inherits a rail colour invisible on this
                // background, so the rail is set outright.
                inactiveTrackColor: Tones.hairline,
                thumbColor: Tones.text,
                overlayColor: accent.withValues(alpha: 0.15),
                // Nothing but the line at rest; a thumb appears under a
                // finger. The touch target never was the thin part -- Slider
                // claims its full height regardless.
                thumbShape: RoundSliderThumbShape(
                  enabledThumbRadius: dragging ? 8 : 0,
                  elevation: 0,
                  pressedElevation: 0,
                ),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                trackShape: const LookTrackShape(),
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
                  // On release, where the seek commits -- not during the
                  // drag, which would buzz continuously.
                  HapticFeedback.selectionClick();
                  widget.player.seek(Duration(milliseconds: v.round()));
                  setState(() => _dragMs = null);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    // Reads the dragged position, not the playing one: a
                    // scrubber whose label lags the thumb makes you aim by
                    // feel.
                    _label(Duration(milliseconds: shown.round())),
                    style: times.copyWith(color: dragging ? Tones.text : null),
                  ),
                  Text(
                    '-${_label(Duration(milliseconds: (maxMs - shown).round()))}',
                    style: times,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
