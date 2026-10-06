import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/audio/tune_player.dart';

/// What a key does on a computer, apart from the screens, so it can be tested.
///
/// Space plays and pauses, the arrows seek five seconds, ctrl+arrows skip,
/// L likes, / (or ctrl+F) searches, Esc (or alt+left) goes back, and the media
/// keys do what they say.
///
/// While [typing] only the media keys are taken: a space typed into a search
/// box or a playlist name must never be read as "pause".
KeyEventResult handleDesktopKey({
  required KeyEvent event,
  required TunePlayer player,
  required bool typing,
  required bool ctrl,
  required bool alt,
  required VoidCallback onLike,
  required VoidCallback onSearch,
  required bool Function() onBack,
}) {
  if (event is KeyUpEvent) return KeyEventResult.ignored;
  final key = event.logicalKey;
  final down = event is KeyDownEvent;

  // Media keys work whatever has focus.
  if (key == LogicalKeyboardKey.mediaPlayPause) {
    if (down) player.toggle();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.mediaTrackNext) {
    if (down) player.next();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.mediaTrackPrevious) {
    if (down) player.previous();
    return KeyEventResult.handled;
  }
  if (typing) return KeyEventResult.ignored;

  if (alt && key == LogicalKeyboardKey.arrowLeft) {
    if (down) onBack();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.space) {
    if (down) player.toggle();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.arrowRight ||
      key == LogicalKeyboardKey.arrowLeft) {
    final forward = key == LogicalKeyboardKey.arrowRight;
    if (ctrl) {
      if (down) forward ? player.next() : player.previous();
    } else {
      // Held down it keeps seeking, which is what holding an arrow means.
      final to = player.position + Duration(seconds: forward ? 5 : -5);
      final end = player.duration;
      player.seek(
        to < Duration.zero
            ? Duration.zero
            : end > Duration.zero && to > end
            ? end
            : to,
      );
    }
    return KeyEventResult.handled;
  }
  if (!down) return KeyEventResult.ignored;
  if (key == LogicalKeyboardKey.keyL) {
    onLike();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.slash ||
      (ctrl && key == LogicalKeyboardKey.keyF)) {
    onSearch();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.escape) {
    onBack();
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}
