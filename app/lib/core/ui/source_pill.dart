import '../platform/device.dart';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Where the sound for a track is coming from right now.
///
/// Said plainly, in the player and in the bar, so a dropout is never a
/// mystery: either it is on this phone and will always play, it is arriving
/// from the box, or it is not on this phone and the box cannot be reached.
enum TrackSource { saved, streaming, unavailable }

TrackSource sourceFor({required bool held, required bool offline}) {
  if (held) return TrackSource.saved;
  return offline ? TrackSource.unavailable : TrackSource.streaming;
}

extension TrackSourceText on TrackSource {
  /// Short enough for the second line of the mini bar.
  String get label => switch (this) {
    TrackSource.saved => 'held offline',
    TrackSource.streaming => 'streaming',
    TrackSource.unavailable => 'not on ${Device.thisOne} yet',
  };

  Color get color => switch (this) {
    TrackSource.saved => Tones.held,
    TrackSource.streaming => Tones.textMuted,
    TrackSource.unavailable => Tones.warn,
  };
}

/// The small outlined tag at the top of Now Playing.
class SourcePill extends StatelessWidget {
  const SourcePill({super.key, required this.source});

  final TrackSource source;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Source: ${source.label}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: Tones.hairline),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          source.label,
          style: TypeScale.mono.copyWith(fontSize: 11, color: source.color),
        ),
      ),
    );
  }
}
