/// Projecting the playhead between position updates.
///
/// The player reports its position at most every 250 ms. That is plenty for a
/// scrubber, but a sung word lasts roughly 300-700 ms, so a highlight driven
/// straight off those reports advances in one to three visible jumps per word
/// instead of sweeping across it.
///
/// So the reported position is treated as a fix taken at a known wall-clock
/// instant, and the value in between is projected from how long ago that was.
/// This is the same idea as `PlaybackState.updatePosition` / `updateTime` in
/// audio_service, and it means the player does not have to tick faster to make
/// the lyrics look smooth.
///
/// Deliberately free of any Flutter import so it can be exercised directly.
library;

/// Where the playhead is now, given the last report from the player.
///
/// While paused the reported position is already current, so it is returned
/// unchanged -- projecting there would drift a paused track forwards.
///
/// [duration], when known, clamps the result: a projection that ran past the
/// end of the track would light up lyrics that are no longer playing, which is
/// exactly the moment a listener notices the timing is wrong.
Duration projectPosition({
  required Duration reported,
  required DateTime reportedAt,
  required DateTime now,
  required bool playing,
  Duration? duration,
}) {
  if (!playing) return _clamp(reported, duration);
  final elapsed = now.difference(reportedAt);
  // A backwards or absurd clock reading means the fix is not usable; fall back
  // to the reported value rather than projecting nonsense.
  if (elapsed.isNegative) return _clamp(reported, duration);
  return _clamp(reported + elapsed, duration);
}

Duration _clamp(Duration value, Duration? duration) {
  if (value.isNegative) return Duration.zero;
  if (duration != null && duration > Duration.zero && value > duration) {
    return duration;
  }
  return value;
}
