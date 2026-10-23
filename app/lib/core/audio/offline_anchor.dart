/// When a failed stream offline may go back to the song heard last.
///
/// Offline, mpv moves on to the next entry by itself when one fails, without a
/// sound, so the player goes back to the song the listener actually heard. That
/// is right once. When the server is down but some songs still play (the edge
/// serves them from its own copy), going back every time the next song fails
/// replays the same song over and over: it ends, the next one fails, back again.
///
/// So the way back is used once per song. It opens again when a different song
/// is heard, or when the listener moves (next, back, a tap, a seek).
library;

class OfflineAnchor {
  String? _used;

  /// Whether the player may go back to [sha] now. A yes is spent.
  bool take(String sha) {
    if (_used == sha) return false;
    _used = sha;
    return true;
  }

  /// [sha] is playing and being heard.
  void heard(String sha) {
    if (_used != null && _used != sha) _used = null;
  }

  /// The listener moved on their own.
  void clear() => _used = null;
}
