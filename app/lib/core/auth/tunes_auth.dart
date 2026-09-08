// prefer_initializing_formals fires on this file's constructor and cannot be
// satisfied: the fields are private, so an initializing formal would have to
// be named `_post`, and Dart forbids named parameters beginning with an
// underscore. Suppressed with that reason rather than by making the fields
// public, which would be a worse trade for a lint.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'token_store.dart';

/// Result of asking for an access token.
///
/// `needsEnrolment` is distinct from a plain failure: it means the device has
/// no refresh token or the server has rejected the one it has, and no amount
/// of retrying will help. The UI must send the user to enter an invite code
/// rather than showing "offline" and quietly retrying forever -- which is
/// exactly the failure mode the FileProvider bug had, where the message named
/// the wrong thing and cost an afternoon.
sealed class AuthResult {
  const AuthResult();
}

class AuthOk extends AuthResult {
  const AuthOk(this.accessToken);
  final String accessToken;
}

class AuthNeedsEnrolment extends AuthResult {
  const AuthNeedsEnrolment();
}

class AuthUnavailable extends AuthResult {
  const AuthUnavailable(this.cause);
  final Object cause;
}

/// Minimal transport seam, so tests do not need a socket and the client stays
/// pure Dart with zero Flutter imports (AGENTS.md §1).
typedef PostJson = Future<({int status, Map<String, dynamic> body})> Function(
  String path,
  Map<String, dynamic> body, {
  String? bearer,
});

/// The device's half of the auth protocol.
///
///   invite -> enrol -> refresh token (stored) -> access token (cached)
///
/// Holds no secret that shipped with the app. The refresh token is earned by
/// redeeming an invite and is the only durable credential; everything else is
/// minted and expires.
class TunesAuth {
  TunesAuth({
    required PostJson post,
    required TokenStore store,
    DateTime Function() now = DateTime.now,
  }) : _post = post,
       _store = store,
       _now = now;

  final PostJson _post;
  final TokenStore _store;
  final DateTime Function() _now;

  String? _accessToken;
  DateTime? _accessExpiry;

  /// Re-mint this long before actual expiry.
  ///
  /// A token that is valid when checked but expires while the request is in
  /// flight reads to the caller as an auth failure, which would bounce the
  /// user to an enrolment screen they do not need. Thirty seconds is longer
  /// than any request this app makes.
  static const _skew = Duration(seconds: 30);

  bool get hasCachedToken {
    final exp = _accessExpiry;
    return _accessToken != null && exp != null && _now().isBefore(exp);
  }

  /// Exchanges an invite code for a refresh token, once, on a new device.
  Future<AuthResult> enrol(String code, String deviceLabel) async {
    try {
      final res = await _post("/auth/redeem", {
        "code": code,
        "label": deviceLabel,
      });
      if (res.status != 200) return const AuthNeedsEnrolment();
      final refresh = res.body["refresh_token"];
      final deviceId = res.body["device_id"];
      if (refresh is! String || deviceId is! String) {
        return const AuthNeedsEnrolment();
      }
      await _store.writeRefreshToken(refresh);
      await _store.writeDeviceId(deviceId);
      // Awaited inside the try on purpose: returning the future unawaited
      // would let a failure escape this catch and surface as an unhandled
      // rejection instead of AuthUnavailable.
      return await accessToken();
    } catch (e) {
      return AuthUnavailable(e);
    }
  }

  /// A valid access token, from cache when possible.
  ///
  /// The cached token is returned without a network call, which matters: this
  /// sits in front of every authenticated request, and a round trip per
  /// request would put the auth service on the critical path of playback.
  Future<AuthResult> accessToken({bool forceRefresh = false}) async {
    if (!forceRefresh && hasCachedToken) return AuthOk(_accessToken!);

    final refresh = await _store.readRefreshToken();
    if (refresh == null) return const AuthNeedsEnrolment();

    try {
      final res = await _post("/auth/token", {"refresh_token": refresh});
      if (res.status == 401 || res.status == 403) {
        // The server has disowned this device -- revoked, or the account is
        // disabled. Clearing is deliberate: keeping a token the server has
        // rejected only produces a device that retries forever and never says
        // why.
        await _store.clear();
        _accessToken = null;
        _accessExpiry = null;
        return const AuthNeedsEnrolment();
      }
      if (res.status != 200) {
        return AuthUnavailable(StateError("token endpoint ${res.status}"));
      }
      final token = res.body["access_token"];
      final expiresIn = res.body["expires_in"];
      if (token is! String || expiresIn is! int) {
        return AuthUnavailable(StateError("malformed token response"));
      }
      _accessToken = token;
      _accessExpiry = _now().add(Duration(seconds: expiresIn)).subtract(_skew);
      return AuthOk(token);
    } catch (e) {
      // A network failure is not a revocation. Keep the refresh token.
      return AuthUnavailable(e);
    }
  }

  /// Signed URLs for media, minted in one round trip for a whole queue.
  ///
  /// Batched because the player opens an entire playlist at once
  /// (`tune_player.dart`), so a per-track call would mean one request per
  /// queue entry before playback could start.
  ///
  /// Returns a map from the requested path to its signed URL. Paths the
  /// server refuses are simply absent rather than throwing, so one bad entry
  /// cannot stop a queue from playing.
  Future<({Map<String, String> grants, int expiresIn})> mediaGrants(
    List<String> paths,
  ) async {
    const empty = (grants: <String, String>{}, expiresIn: 0);
    if (paths.isEmpty) return empty;
    final auth = await accessToken();
    if (auth is! AuthOk) return empty;
    try {
      final res = await _post("/auth/media/grant", {
        "paths": paths,
      }, bearer: auth.accessToken);
      if (res.status != 200) return empty;
      final grants = res.body["grants"];
      final expiresIn = res.body["expires_in"];
      if (grants is! Map || expiresIn is! int) return empty;
      return (
        grants: {
          for (final e in grants.entries)
            if (e.key is String && e.value is String)
              e.key as String: e.value as String,
        },
        expiresIn: expiresIn,
      );
    } catch (_) {
      return empty;
    }
  }

  /// Forgets the cached access token without touching the refresh token.
  /// Used when the server rejects a token that has not yet expired locally,
  /// which means the clocks disagree.
  void invalidateCachedToken() {
    _accessToken = null;
    _accessExpiry = null;
  }
}

/// Decodes a JWT payload without verifying it.
///
/// The client must never make a trust decision from this -- verification is
/// the edge's job and the app has no key. It exists so the UI can show which
/// account a device belongs to without a round trip.
Map<String, dynamic>? peekClaims(String jwt) {
  final parts = jwt.split(".");
  if (parts.length != 3) return null;
  try {
    var p = parts[1].replaceAll("-", "+").replaceAll("_", "/");
    p += "=" * ((4 - p.length % 4) % 4);
    final decoded = jsonDecode(utf8.decode(base64.decode(p)));
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}
