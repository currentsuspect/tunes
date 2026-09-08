import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'token_store.dart';

/// The refresh token, in Android's keystore-backed storage.
///
/// This is the one credential on the device whose compromise actually
/// matters: it is long-lived and it mints access tokens. Everything below it
/// in the hierarchy expires on its own.
///
///     refresh token  -> here, keystore-backed
///     access token   -> memory only, ~10 min
///     media grant    -> not stored, one object, hours
///
/// Deliberately NOT SharedPreferences, the drift database, or a plain file.
/// All three are readable by anything that gets filesystem access to the app's
/// data directory, which on a rooted or restored-from-backup device is not a
/// high bar.
///
/// Pinned to 10.x deliberately. v11 requires `compileSdk 37`, which this
/// project does not have -- Flutter supplies 36, and AGP 9.1.0's maximum
/// recommended is also 36, so v11 fails the APK build outright. The two
/// versions offer the same ciphers and the same defaults; v11's only relevant
/// change is dropping the long-deprecated `encryptedSharedPreferences`
/// parameter, which this code never used. Revisit when the toolchain moves.
///
/// The defaults are spelled out rather than inherited, because they are the
/// security-relevant part:
///
/// - `AES/GCM/NoPadding` for the data, with the key wrapped by
///   `RSA/ECB/OAEPwithSHA-256andMGF1Padding` in the Android keystore, which is
///   hardware-backed wherever there is a TEE.
/// - `migrateWithBackup: false`, so the ciphertext does not travel in a device
///   backup to somewhere the keystore key does not exist.
/// - `resetOnError: true`, so a key invalidated by a lock-screen change clears
///   the entry instead of throwing on every launch. The token is unusable
///   either way; clearing turns that into "not enrolled", which routes the
///   user to the invite screen rather than a crash loop.
class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              resetOnError: true,
              migrateWithBackup: false,
              storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
              keyCipherAlgorithm:
                  KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
            ),
          );

  final FlutterSecureStorage _storage;

  static const _refreshKey = 'tunes.auth.refresh_token';
  static const _deviceKey = 'tunes.auth.device_id';

  /// Reads return null rather than throwing.
  ///
  /// Secure storage can fail for reasons that have nothing to do with this app
  /// -- a keystore invalidated by a lock-screen change, or a restored backup
  /// carrying ciphertext this device's key cannot open. A throw here would
  /// crash on launch; null means "not enrolled", which routes the user to the
  /// invite screen. That is the right outcome for both cases, because in both
  /// the token is genuinely unusable.
  @override
  Future<String?> readRefreshToken() async {
    try {
      return await _storage.read(key: _refreshKey);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeRefreshToken(String token) =>
      _storage.write(key: _refreshKey, value: token);

  @override
  Future<String?> readDeviceId() async {
    try {
      return await _storage.read(key: _deviceKey);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeDeviceId(String id) =>
      _storage.write(key: _deviceKey, value: id);

  @override
  Future<void> clear() async {
    // Delete both, and do not let a failure on the first stop the second: a
    // half-cleared enrolment is worse than either outcome.
    try {
      await _storage.delete(key: _refreshKey);
    } catch (_) {
      // fall through
    }
    try {
      await _storage.delete(key: _deviceKey);
    } catch (_) {
      // fall through
    }
  }
}
