/// Decides when the listener's place in a song is worth writing down.
///
/// The player reports four times a second and a write is a disk write, so this
/// says "now" only when something is worth keeping: the song changed, or the
/// playhead has moved on by [every] since the last write.
///
/// One thing is never worth keeping. Stopping the player (backing out of the
/// app halts it) makes the engine report 0:00, which is a long way from the
/// last write and so used to be written as the new place. The place the
/// listener actually left was then gone, and the next launch opened at the
/// start. A playhead at zero that is not playing is the engine being reset, not
/// the listener choosing to be there.
class PositionSaver {
  PositionSaver({this.every = const Duration(seconds: 5)});

  final Duration every;

  String? _sha;
  Duration _last = Duration.zero;

  /// The position to write now, or null for nothing.
  Duration? tick({
    required String? sha,
    required Duration position,
    required bool playing,
  }) {
    if (sha != _sha) {
      _sha = sha;
      _last = position;
      // The first report for a song is where the listener is in it: usually
      // the start, and after a relaunch the spot that was restored. Either way
      // it replaces whatever the previous song left behind.
      return sha == null ? null : position;
    }
    if (!playing && position == Duration.zero) return null;
    if ((position - _last).abs() >= every) {
      _last = position;
      return position;
    }
    return null;
  }
}
