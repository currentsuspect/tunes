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
  static const _radioAutoplay = 'radio.autoplay';
  static const _lyricsTapOffsetMs = 'lyrics.tapOffsetMs';
  static const _animatedArtwork = 'nowPlaying.animatedArtwork';
  static const _serverUrl = 'server.url';
  static const _lastPlayedSha = 'playback.lastPlayedSha';
  static const _lastPositionMs = 'playback.lastPositionMs';

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

  /// Whether the music keeps going after the queue runs out.
  ///
  /// On by default: when an album (or anything else) ends with repeat off,
  /// the radio engine picks what follows from the listener's own history, on
  /// this device. The pick is appended to the queue, never spliced into it.
  /// Off means the queue ends in silence, as before.
  bool get radioAutoplay => _bool(_radioAutoplay, fallback: true);
  Future<void> setRadioAutoplay(bool v) => _put(_radioAutoplay, '$v');

  /// Whether the sleeve turns slowly while a track plays.
  ///
  /// On by default because it is what the player already did, and the whole
  /// point of putting it here is that it can now be turned off -- it is the
  /// one piece of motion in the app that runs continuously.
  bool get animatedArtwork => _bool(_animatedArtwork, fallback: true);
  Future<void> setAnimatedArtwork(bool v) => _put(_animatedArtwork, '$v');

  /// The track that was playing when the app was last closed.
  ///
  /// Stored by sha rather than by queue position, because the library can
  /// change while the app is shut: a position would silently come back
  /// pointing at a different song.
  String? get lastPlayedSha {
    final v = _cache[_lastPlayedSha];
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> setLastPlayedSha(String? sha) => sha == null || sha.isEmpty
      ? _clear(_lastPlayedSha)
      : _put(_lastPlayedSha, sha);

  /// How far into [lastPlayedSha] playback had reached.
  ///
  /// Zero rather than null when unknown, because "start from the beginning" is
  /// the correct behaviour for an unknown position and callers should not each
  /// have to decide that.
  Duration get lastPosition {
    final ms = int.tryParse(_cache[_lastPositionMs] ?? '');
    return Duration(milliseconds: (ms == null || ms < 0) ? 0 : ms);
  }

  Future<void> setLastPosition(Duration position) =>
      _put(_lastPositionMs, '${position.inMilliseconds}');

  // --- server --------------------------------------------------------------

  /// Where tunesd lives, or null to use the address this build was compiled
  /// with.
  ///
  /// The compile-time TUNESD_URL was the only way to say this, which meant a
  /// second person could not use the app without someone rebuilding it for
  /// them. Stored rather than baked so one APK serves everyone, and so an
  /// address that moves -- a laptop changing networks, a tailnet node -- is a
  /// text field rather than a release.
  ///
  /// Null when unset, deliberately: the fallback then remains whatever the
  /// build was compiled with, so an existing install behaves exactly as it did
  /// before this setting existed.
  String? get serverUrl {
    final v = _cache[_serverUrl]?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  /// Stores a server address, or clears it back to the compiled-in default.
  ///
  /// Trailing slashes are stripped because every request builds its path as
  /// '$baseUrl/manifest' -- a stored 'http://host:4780/' would ask for
  /// '//manifest' and fail in a way that looks like the server being down.
  Future<void> setServerUrl(String? url) {
    final v = url?.trim();
    if (v == null || v.isEmpty) return _clear(_serverUrl);
    return _put(_serverUrl, v.endsWith('/') ? v.substring(0, v.length - 1) : v);
  }

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
