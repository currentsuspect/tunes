/// Where the refresh token lives.
///
/// An interface rather than a concrete store on purpose. The refresh token is
/// the one long-lived credential on the device and belongs in the Android
/// keystore, which needs `flutter_secure_storage` -- a new dependency, and
/// AGENTS.md §1 requires agreement before adding one. Until that decision is
/// made this seam lets the backing store change without touching any caller.
///
/// Whatever implements this must survive app upgrades. Losing the refresh
/// token means re-enrolling the device by hand, which for a phone that is not
/// physically nearby is a genuinely bad afternoon.
abstract class TokenStore {
  Future<String?> readRefreshToken();
  Future<void> writeRefreshToken(String token);
  Future<String?> readDeviceId();
  Future<void> writeDeviceId(String id);
  Future<void> clear();
}

/// In-memory store. Tests, and nothing else -- it forgets on restart.
class MemoryTokenStore implements TokenStore {
  String? _refresh;
  String? _device;

  @override
  Future<String?> readRefreshToken() async => _refresh;

  @override
  Future<void> writeRefreshToken(String token) async => _refresh = token;

  @override
  Future<String?> readDeviceId() async => _device;

  @override
  Future<void> writeDeviceId(String id) async => _device = id;

  @override
  Future<void> clear() async {
    _refresh = null;
    _device = null;
  }
}
