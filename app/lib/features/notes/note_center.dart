import 'dart:async';

import '../../core/data/gets.dart';
import '../../core/data/settings_store.dart';
import '../../core/platform/notifications.dart';
import '../../domain/soulseek.dart';
import '../updates/update_controller.dart';

/// Decides what goes in the shade (design approved 24 Oct, "Tell me when"):
///
/// - a song this phone asked for has landed, with Play;
/// - someone else got songs, one note per batch, off unless turned on;
/// - a new Tunes is ready, once per version.
///
/// Only while the app is away: with Tunes on screen the landing shows as a
/// message on screen instead, and a second copy in the shade is noise.
class NoteCenter {
  NoteCenter({
    required this.gets,
    required this.settings,
    required this.updates,
    required this.foreground,
    this.show = showNote,
  }) {
    gets.addLandedListener(_landed);
    gets.addListener(_recentChanged);
    updates?.addListener(_updateChanged);
  }

  final GetsController gets;
  final SettingsStore settings;
  final UpdateController? updates;
  final bool Function() foreground;
  final Future<void> Function({
    required int id,
    required String title,
    String? body,
    String? tap,
    String? actionLabel,
    String? action,
  })
  show;

  /// Others' gets already seen, so each is told once. Null until the first
  /// look: what was there before the app started is not news.
  Set<String>? _seen;

  void _landed(GetJob j) {
    if (foreground() || !settings.noteMine || j.sha == null) return;
    unawaited(
      show(
        id: _idFor(j.id),
        title: '${j.title} is in your library',
        body: j.artist,
        tap: 'play:${j.sha}',
        actionLabel: 'Play',
        action: 'play:${j.sha}',
      ),
    );
  }

  void _recentChanged() {
    final done = [
      for (final j in gets.recent)
        if (j.state == GetState.done) j,
    ];
    final seen = _seen;
    _seen = {for (final j in done) j.id};
    if (seen == null || foreground() || !settings.noteOthers) return;
    final mine = {for (final j in gets.following) j.id};
    final fresh = [
      for (final j in done)
        if (!seen.contains(j.id) && !mine.contains(j.id)) j,
    ];
    if (fresh.isEmpty) return;
    final byWho = <String, List<GetJob>>{};
    for (final j in fresh) {
      byWho.putIfAbsent(j.by ?? 'Someone', () => []).add(j);
    }
    for (final MapEntry(key: who, value: jobs) in byWho.entries) {
      final names = jobs.map((j) => j.title).toList();
      unawaited(
        show(
          id: _idFor('others:$who'),
          title: jobs.length == 1
              ? '$who got ${names.first}'
              : '$who got ${jobs.length} songs',
          body: jobs.length == 1 ? jobs.first.artist : _list(names),
          tap: 'open:gets',
        ),
      );
    }
  }

  void _updateChanged() {
    final u = updates?.available;
    if (u == null || !settings.noteUpdate) return;
    if (settings.noteUpdateBuild == '${u.build}') return;
    unawaited(settings.setNoteUpdateBuild('${u.build}'));
    unawaited(
      show(
        id: _idFor('update'),
        title: 'A new Tunes is ready',
        body: 'Open Tunes to get it.',
        tap: 'open:update',
        actionLabel: 'Update',
        action: 'open:update',
      ),
    );
  }

  void dispose() {
    gets.removeLandedListener(_landed);
    gets.removeListener(_recentChanged);
    updates?.removeListener(_updateChanged);
  }

  /// "A, B and C", "A, B and 3 more".
  static String _list(List<String> names) {
    if (names.length <= 3) {
      return names.length == 1
          ? names.first
          : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
    }
    return '${names.take(2).join(', ')} and ${names.length - 2} more';
  }

  /// A stable notification id per thing told, so telling it again replaces
  /// the note instead of stacking a copy.
  static int _idFor(String key) {
    var h = 0x811c9dc5;
    for (final c in key.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0x7fffffff;
    }
    return 1000 + h % 1000000;
  }
}
