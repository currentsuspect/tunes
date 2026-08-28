import 'dart:convert';
import 'dart:io';

import '../../domain/manifest.dart';

class TunesClient {
  TunesClient(this.baseUrl, [this._cacheDir]);

  final String baseUrl;
  final Directory? _cacheDir;

  static const _timeout = Duration(seconds: 8);
  static const _downloadTimeout = Duration(minutes: 30);

  File? get _cacheFile {
    final dir = _cacheDir;
    if (dir == null) return null;
    return File('${dir.path}/manifest.json');
  }

  Future<List<ManifestTrack>> fetchManifest() async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await client.getUrl(Uri.parse('$baseUrl/manifest'));
      final res = await req.close().timeout(_timeout);
      if (res.statusCode != 200) {
        throw TunesFetchException('manifest ${res.statusCode}');
      }
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final tracks = (json['tracks'] as List<dynamic>? ?? const [])
          .map((t) => ManifestTrack.fromJson(t as Map<String, dynamic>))
          .toList();
      await _writeCache(body);
      return tracks;
    } on SocketException catch (e) {
      final cached = await _readCache();
      if (cached != null) return cached;
      throw TunesFetchException('tunesd unreachable: ${e.message}');
    } on HttpException catch (e) {
      final cached = await _readCache();
      if (cached != null) return cached;
      throw TunesFetchException('tunesd unreachable: ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> downloadTrack(
    String sha,
    String path, {
    void Function(int received, int total)? onProgress,
  }) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await client.getUrl(Uri.parse('$baseUrl/track/$sha'));
      final res = await req.close().timeout(_downloadTimeout);
      if (res.statusCode != 200) {
        throw TunesFetchException('track ${res.statusCode}');
      }
      final total =
          int.tryParse(res.headers.value('content-length') ?? '') ?? 0;
      await File(path).parent.create(recursive: true);
      final sink = File(path).openWrite();
      var received = 0;
      try {
        await for (final chunk in res) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
    } on SocketException catch (e) {
      throw TunesFetchException('download failed: ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _writeCache(String body) async {
    final f = _cacheFile;
    if (f == null) return;
    try {
      await f.parent.create(recursive: true);
      await f.writeAsString(body);
    } catch (_) {}
  }

  Future<List<ManifestTrack>?> _readCache() async {
    final f = _cacheFile;
    if (f == null) return null;
    try {
      if (!await f.exists()) return null;
      final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return (json['tracks'] as List<dynamic>? ?? const [])
          .map((t) => ManifestTrack.fromJson(t as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }
}

class TunesFetchException implements Exception {
  TunesFetchException(this.message);

  final String message;

  @override
  String toString() => message;
}
