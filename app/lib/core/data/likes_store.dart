import 'package:flutter/widgets.dart';

import 'database.dart';

/// What the listener said yes to.
///
/// Held in memory and written through, like [SettingsStore], because a heart
/// appears on every row of a list and in the player: an answer that has to be
/// awaited would make every one of them flicker in after the frame it belongs
/// to. The whole set is at most a few thousand short strings.
class LikesStore extends ChangeNotifier {
  LikesStore(this._db);

  final TunesDatabase _db;

  /// sha to when it was liked. A map rather than a set because the list is
  /// shown newest first, and the order things were liked in is the only
  /// meaningful one without asking the listener to sort.
  final Map<String, int> _likedAt = {};

  Future<void> load() async {
    final rows = await _db.select(_db.likedTracks).get();
    _likedAt
      ..clear()
      ..addEntries(rows.map((r) => MapEntry(r.sha, r.likedAt)));
    notifyListeners();
  }

  bool isLiked(String sha) => _likedAt.containsKey(sha);

  int get count => _likedAt.length;

  /// Liked tracks, most recently liked first.
  List<String> get shas {
    final entries = _likedAt.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in entries) e.key];
  }

  /// Flips the like and returns what it became.
  ///
  /// The map is updated and listeners notified before the write, so the heart
  /// fills under the finger rather than a database round trip later. A failed
  /// write leaves the two out of step until the next load, which is the right
  /// trade for a control that has to feel instant.
  Future<bool> toggle(String sha) async {
    if (_likedAt.containsKey(sha)) {
      _likedAt.remove(sha);
      notifyListeners();
      await (_db.delete(_db.likedTracks)..where((t) => t.sha.equals(sha))).go();
      return false;
    }
    _likedAt[sha] = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    await _db
        .into(_db.likedTracks)
        .insertOnConflictUpdate(
          LikedTracksCompanion.insert(sha: sha, likedAt: _likedAt[sha]!),
        );
    return true;
  }
}

/// Makes [LikesStore] reachable from anywhere.
///
/// Published above the Navigator with the other scopes, so an album page or
/// the player -- both pushed routes -- can read it. A scope below the
/// Navigator is the bug that made download progress invisible on album pages.
class LikesScope extends InheritedNotifier<LikesStore> {
  const LikesScope({super.key, required LikesStore likes, required super.child})
    : super(notifier: likes);

  static LikesStore? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<LikesScope>()?.notifier;
  }
}
