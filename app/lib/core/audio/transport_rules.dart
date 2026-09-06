/// Transport decisions that are pure logic, kept away from the player so they
/// can be reasoned about and tested without a decoder, a queue or a device.
library;

/// What pressing "previous" should actually do.
enum PreviousAction {
  /// Start the track that is playing again from the top.
  restart,

  /// Step back one track in the queue.
  previousTrack,

  /// Jump to the end of the queue, wrapping around.
  wrapToLast,
}

/// How far into a track "previous" stops meaning "the one before".
///
/// Three seconds is the convention every player settled on, and it is the
/// right shape: a press moments after a track starts is almost always "go
/// back, that was the one I wanted", and a press any later is almost always
/// "play this again". Nothing else distinguishes the two intents, since both
/// are the same button.
const kRestartWindow = Duration(seconds: 3);

/// How long a restart stays "the first of two presses".
///
/// Longer than the restart window on purpose. Pressing twice is a deliberate
/// act -- reach the top of the track, decide that was not it, go back -- and
/// deciding takes longer than three seconds. Without this the second press
/// would land after playback had moved past the window and restart the track
/// all over again, which is the one thing a double press must never do.
const kDoublePressWindow = Duration(seconds: 8);

/// Decides what "previous" means given where playback currently is.
///
/// [sinceRestart] is how long ago a previous press restarted this same track,
/// or null if the last press did not. Wall clock rather than playback
/// position, because a restart while paused leaves the position at zero
/// indefinitely, and a press an hour later is not a double press.
///
/// Deliberately takes [repeatAll] as a bool rather than the player's repeat
/// mode: this file stays free of imports so it runs anywhere, and the only
/// thing the decision needs to know is whether the queue wraps.
PreviousAction previousActionFor({
  required Duration position,
  required int index,
  required int queueLength,
  required bool repeatAll,
  Duration? sinceRestart,
  Duration window = kRestartWindow,
  Duration doublePressWindow = kDoublePressWindow,
}) {
  // Press once to hear this track again, twice to go back. The second press
  // must step back wherever playback has got to by then, or the answer to
  // "previous, previous" would depend on how fast the button was pressed.
  final doublePress = sinceRestart != null && sinceRestart <= doublePressWindow;

  // Past the window, previous restarts the track you are on -- including on
  // the first track, and including when the queue wraps. Losing your place in
  // a track you are three seconds into is a worse mistake than making you
  // press the button twice.
  if (!doublePress && position > window) return PreviousAction.restart;
  if (index > 0) return PreviousAction.previousTrack;
  if (repeatAll && queueLength > 1) return PreviousAction.wrapToLast;
  // First track, nowhere back to go: land on the top of the track rather than
  // doing nothing at all.
  return PreviousAction.restart;
}
