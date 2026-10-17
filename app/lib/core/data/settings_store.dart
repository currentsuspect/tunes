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
  static const _cacheSize = 'storage.cacheSize';
  static const _prefetchNext = 'storage.prefetchNext';
  static const _doubleTapDownloads = 'gesture.doubleTapDownloads';
  static const _themeChoice = 'theme.choice';
  static const _themeBrightness = 'theme.brightness';
  static const _radioAutoplay = 'radio.autoplay';
  static const _lyricsTapOffsetMs = 'lyrics.tapOffsetMs';
  static const _animatedArtwork = 'nowPlaying.animatedArtwork';
  static const _lyricSize = 'lyrics.size';
  static const _showLyrics = 'lyrics.show';
  static const _radioReach = 'radio.reach';
  static const _whatsNewSeen = 'app.whatsNewSeen';
  static const _serverUrl = 'server.url';
  static const _syncHistory = 'sync.history';
  static const _volume = 'desktop.volume';
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

  // --- desktop -------------------------------------------------------------

  /// The player's own level on a computer, 0 to 1, kept between launches.
  double get volume =>
      (double.tryParse(_cache[_volume] ?? '') ?? 1).clamp(0, 1);
  Future<void> setVolume(double v) => _put(_volume, v.toStringAsFixed(2));

  // --- sync ----------------------------------------------------------------

  /// Whether listening is shared with the account's other devices. On by
  /// default; off keeps this device's taste to itself, so a phone and a TV can
  /// be different listeners the way they are on a video app.
  bool get syncHistory => _bool(_syncHistory, fallback: true);
  Future<void> setSyncHistory(bool v) => _put(_syncHistory, '$v');

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

  // --- storage -------------------------------------------------------------

  /// The sizes the songs-you-have-heard cache can be, as shown in Settings.
  static const cacheSizesGb = [2, 5, 10, 20];

  /// Which of [cacheSizesGb] is chosen. 5 GB by default: a few hundred songs
  /// in lossless, small against a phone.
  int get cacheSize {
    final v = int.tryParse(_cache[_cacheSize] ?? '');
    return v == null ? 1 : v.clamp(0, cacheSizesGb.length - 1);
  }

  Future<void> setCacheSize(int i) => _put(_cacheSize, '$i');

  int get cacheBytes => cacheSizesGb[cacheSize] * 1024 * 1024 * 1024;

  /// Whether the next song is fetched whole before it is reached: 0 never,
  /// 1 on Wi-Fi (the default), 2 always, mobile data included.
  int get prefetchNext {
    final v = int.tryParse(_cache[_prefetchNext] ?? '');
    return v == null ? 1 : v.clamp(0, 2);
  }

  Future<void> setPrefetchNext(int v) => _put(_prefetchNext, '$v');

  /// What a double tap on a cover does. Off (the default): it likes the
  /// song, and the button where the heart was downloads instead. On: it
  /// downloads (the whole album, on an album page), and the heart stays a
  /// button. Two listeners asked for the two opposite gestures.
  bool get doubleTapDownloads => _bool(_doubleTapDownloads, fallback: false);

  /// The theme: 'room' (the default, what the app has always looked like),
  /// 'noir', 'crayon', or 'auto' (Crayon by day, Noir after dark).
  String get themeChoice => _cache[_themeChoice] ?? 'room';
  Future<void> setThemeChoice(String v) => _put(_themeChoice, v);

  /// 0 follows the phone, 1 is always dark, 2 always light. Dark by default:
  /// the app was dark-only until themes, so nobody wakes up to a white app.
  int get themeBrightness => int.tryParse(_cache[_themeBrightness] ?? '') ?? 1;
  Future<void> setThemeBrightness(int v) => _put(_themeBrightness, '$v');

  Future<void> setDoubleTapDownloads(bool v) => _put(_doubleTapDownloads, '$v');

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
  /// Off by default: a square sleeve turning for thirty seconds at a time is a
  /// choice, not a default. It was on before the redesign, which is why the
  /// switch exists at all -- it is the one piece of motion in the app that
  /// runs continuously.
  bool get animatedArtwork => _bool(_animatedArtwork, fallback: false);
  Future<void> setAnimatedArtwork(bool v) => _put(_animatedArtwork, '$v');

  /// The id of the last What's new pack that was shown, so each is shown once.
  String? get whatsNewSeen {
    final v = _cache[_whatsNewSeen];
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> setWhatsNewSeen(String id) => _put(_whatsNewSeen, id);

  /// How large the lyrics are set: 0 small, 1 medium, 2 large.
  int get lyricSize {
    final v = int.tryParse(_cache[_lyricSize] ?? '');
    return v == null ? 1 : v.clamp(0, 2);
  }

  /// Whether Now Playing shows lyrics at all. On by default; they are still a
  /// menu item away when off, and a song with none never shows an empty space.
  bool get showLyrics => _bool(_showLyrics, fallback: true);
  Future<void> setShowLyrics(bool v) => _put(_showLyrics, '$v');

  Future<void> setLyricSize(int v) => _put(_lyricSize, '${v.clamp(0, 2)}');

  /// How far out the radio is allowed to go, 0 (familiar) to 1 (further out).
  ///
  /// The listener's own dial for what plays when the queue runs out. The
  /// session still narrows after skips and widens after songs heard through;
  /// this moves where that starts and how far it can go.
  double get radioReach {
    final v = double.tryParse(_cache[_radioReach] ?? '');
    return v == null ? kDefaultRadioReach : v.clamp(0.0, 1.0);
  }

  Future<void> setRadioReach(double v) =>
      _put(_radioReach, v.clamp(0.0, 1.0).toStringAsFixed(2));

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
/// Where the radio dial rests until it is moved.
const double kDefaultRadioReach = 0.2;

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
