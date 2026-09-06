import 'package:flutter/widgets.dart';

import 'database.dart';

/// App settings, and who you are.
///
/// Read once into memory at startup and written through on change, so every
/// screen can read a setting synchronously during build. A setting that has
/// to be awaited mid-build is a setting that flickers.
///
/// An absent key means the default, so an upgraded install behaves exactly as
/// it did before the setting existed.
class SettingsStore extends ChangeNotifier {
  SettingsStore(this._db);

  final TunesDatabase _db;
  final Map<String, String> _cache = {};

  static const _displayName = 'profile.displayName';
  static const _avatarPath = 'profile.avatarPath';
  static const _gapless = 'playback.gapless';
  static const _stopOnClose = 'playback.stopOnClose';
  static const _lyricsTapOffsetMs = 'lyrics.tapOffsetMs';

  Future<void> load() async {
    final rows = await _db.select(_db.settings).get();
    _cache
      ..clear()
      ..addEntries(rows.map((r) => MapEntry(r.key, r.value)));
    notifyListeners();
  }

  Future<void> _put(String key, String value) async {
    if (_cache[key] == value) return;
    _cache[key] = value;
    notifyListeners();
    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(key: key, value: value),
        );
  }

  Future<void> _clear(String key) async {
    if (!_cache.containsKey(key)) return;
    _cache.remove(key);
    notifyListeners();
    await (_db.delete(_db.settings)..where((t) => t.key.equals(key))).go();
  }

  bool _bool(String key, {required bool fallback}) {
    final v = _cache[key];
    if (v == null) return fallback;
    return v == 'true';
  }

  // --- profile -------------------------------------------------------------

  /// Empty until set. Shown in the header and used for the initials avatar.
  String get displayName => _cache[_displayName] ?? '';
  Future<void> setDisplayName(String v) => _put(_displayName, v.trim());

  /// A file on this device, copied into app storage when chosen so it cannot
  /// disappear when the original is moved or the gallery entry is deleted.
  String? get avatarPath {
    final p = _cache[_avatarPath];
    return (p == null || p.isEmpty) ? null : p;
  }

  Future<void> setAvatarPath(String? path) =>
      path == null ? _clear(_avatarPath) : _put(_avatarPath, path);

  // --- playback ------------------------------------------------------------

  /// Forces mpv's `gapless-audio`, which otherwise only joins tracks whose
  /// formats already match. Off by default: it is the player's own default,
  /// and turning it on is a choice the listener makes.
  bool get gapless => _bool(_gapless, fallback: false);
  Future<void> setGapless(bool v) => _put(_gapless, '$v');

  /// Whether swiping the app away stops playback. On by default, because
  /// audio that outlives its app with no visible control is how you end up
  /// with two tracks playing at once.
  bool get stopOnClose => _bool(_stopOnClose, fallback: true);
  Future<void> setStopOnClose(bool v) => _put(_stopOnClose, '$v');

  // --- lyrics --------------------------------------------------------------

  /// How far ahead of the tap a lyric mark is placed, in milliseconds and
  /// negative. Tuned once and then trusted, which is exactly why it has to
  /// survive leaving the editor.
  Duration get lyricsTapOffset {
    final ms = int.tryParse(_cache[_lyricsTapOffsetMs] ?? '');
    return Duration(milliseconds: ms ?? -250);
  }

  Future<void> setLyricsTapOffset(Duration v) =>
      _put(_lyricsTapOffsetMs, '${v.inMilliseconds}');
}

/// Makes [SettingsStore] reachable from anywhere without threading it through
/// every screen between here and the lyrics editor.
///
/// Published above the Navigator, like [DownloadScope], so pushed routes can
/// read it too — the mistake that made download progress invisible on album
/// pages was putting a scope below the Navigator.
class SettingsScope extends InheritedNotifier<SettingsStore> {
  const SettingsScope({
    super.key,
    required SettingsStore settings,
    required super.child,
  }) : super(notifier: settings);

  static SettingsStore? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<SettingsScope>()
        ?.notifier;
  }
}
