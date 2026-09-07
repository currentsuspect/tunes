import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Downloads an update and hands it to the system installer.
///
/// The app never installs anything itself and could not: Android shows its own
/// confirmation and the user taps Install. This fetches the APK the daemon is
/// serving and opens that dialog on it.
class UpdateInstaller {
  UpdateInstaller({required this.cacheDir});

  static const _channel = MethodChannel('tunes/updates');

  /// Where downloads land. Must be under the path the FileProvider exposes
  /// (`res/xml/update_paths.xml`), or the installer is handed a URI the
  /// provider refuses to resolve.
  final Directory cacheDir;

  double? _progress;
  bool _busy = false;

  /// 0..1 while downloading, null otherwise.
  double? get progress => _progress;
  bool get busy => _busy;

  /// Whether the user has allowed this app to open the installer.
  ///
  /// Android 8+ makes this per-app and grantable only from Settings — there is
  /// no runtime prompt — so it has to be asked about before offering a
  /// download rather than after it.
  Future<bool> canInstall() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('canInstall') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openInstallSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openInstallSettings');
    } catch (_) {
      // The settings page is a courtesy; failing to open it is not worth an
      // error on top of whatever else is going wrong.
    }
  }

  /// Fetches [url] and opens the installer on it.
  ///
  /// Downloads to a `.part` file and renames on completion, so a cancelled or
  /// failed transfer can never be handed to the installer — a truncated APK
  /// fails to parse and reads as a corrupt release rather than a lost
  /// connection.
  Future<void> downloadAndInstall(
    String url,
    int build, {
    void Function(double? progress)? onProgress,
  }) async {
    if (_busy) return;
    _busy = true;
    _progress = 0;
    onProgress?.call(0);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    final target = File('${cacheDir.path}/tunes-$build.apk');
    final partial = File('${target.path}.part');
    try {
      await cacheDir.create(recursive: true);
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('update download ${res.statusCode}');
      }
      final total =
          int.tryParse(res.headers.value('content-length') ?? '') ?? 0;
      final sink = partial.openWrite();
      var received = 0;
      try {
        await for (final chunk in res) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            _progress = received / total;
            onProgress?.call(_progress);
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (await target.exists()) await target.delete();
      await partial.rename(target.path);
      await _channel.invokeMethod<void>('install', {'path': target.path});
    } catch (e) {
      if (await partial.exists()) {
        await partial.delete().catchError((_) => partial);
      }
      debugPrint('update install failed: $e');
      rethrow;
    } finally {
      _busy = false;
      _progress = null;
      onProgress?.call(null);
      client.close(force: true);
    }
  }
}
