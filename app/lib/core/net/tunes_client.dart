import 'dart:convert';
import 'dart:io';

import '../../domain/discography.dart';
import 'update_check.dart';
import '../../domain/manifest.dart';

class ChangesResponse {
  const ChangesResponse({
    required this.generatedAt,
    required this.integrity,
    required this.addedShas,
  });
  final DateTime? generatedAt;
  final String integrity;
  final List<String> addedShas;
}

/// Raised when a download is cancelled by the user. Distinct from a failure:
/// nothing went wrong, so it must not be reported as an error.
class DownloadCancelled implements Exception {
  const DownloadCancelled();
  @override
  String toString() => 'DownloadCancelled';
}

/// Cooperative cancellation for an in-flight download. Checked between chunks,
/// so a cancel takes effect within one chunk rather than at the end of a 20 MB
/// file.
class CancelSignal {
  bool _cancelled = false;
  void cancel() => _cancelled = true;
  bool get isCancelled => _cancelled;
}

class TunesFetchException implements Exception {
  TunesFetchException(this.message);

  final String message;

  @override
  String toString() => 'TunesFetchException: $message';
}

class TunesClient {
  TunesClient(this.baseUrl, [this._cacheDir]);

  /// Where tunesd is. Mutable so changing the server in Settings takes effect
  /// on the next request instead of on the next launch.
  ///
  /// Every request builds its URL from this at call time, so there is no
  /// connection or handle to rebuild — but anything already fetched is still
  /// from the old server until something asks again, which is why the setting
  /// triggers a resync rather than assuming the screen will catch up.
  String baseUrl;
  final Directory? _cacheDir;

  static const _timeout = Duration(seconds: 8);
  static const _downloadTimeout = Duration(minutes: 30);

  File? get _cacheFile {
    final dir = _cacheDir;
    if (dir == null) return null;
    return File('${dir.path}/manifest.json');
  }

  Future<TunesManifest> fetchManifest() async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await client.getUrl(Uri.parse('$baseUrl/manifest'));
      final res = await req.close().timeout(_timeout);
      if (res.statusCode != 200) {
        throw TunesFetchException('manifest ${res.statusCode}');
      }
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final manifest = TunesManifest.fromJson(json);
      await _writeCache(body);
      return manifest;
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

  /// Returns the set of shas added since [since] (ISO8601) along
  /// with the daemon's current integrity hash. Used by the app to
  /// skip full manifest downloads when nothing has changed.
  Future<ChangesResponse> fetchChanges(DateTime since) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final iso = Uri.encodeComponent(since.toUtc().toIso8601String());
      final req = await client.getUrl(Uri.parse('$baseUrl/changes?since=$iso'));
      final res = await req.close().timeout(_timeout);
      if (res.statusCode != 200) {
        throw TunesFetchException('changes ${res.statusCode}');
      }
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      return ChangesResponse(
        generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? ''),
        integrity: json['integrity'] as String,
        addedShas: ((json['addedShas'] as List?) ?? const [])
            .cast<String>()
            .toList(),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<void> downloadTrack(
    String sha,
    String path, {
    void Function(int received, int total)? onProgress,
    CancelSignal? cancel,
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
          if (cancel != null && cancel.isCancelled) {
            throw const DownloadCancelled();
          }
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
    } on DownloadCancelled {
      await _discardPartial(path);
      rethrow;
    } on SocketException catch (e) {
      await _discardPartial(path);
      throw TunesFetchException('download failed: ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  /// A half-written file is worse than no file: it would be indexed as a
  /// download and play as a truncated track.
  Future<void> _discardPartial(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<SearchResults> search(String q) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final uri = Uri.parse('$baseUrl/search?q=${Uri.encodeQueryComponent(q)}');
      final req = await client.getUrl(uri);
      final res = await req.close().timeout(_timeout);
      if (res.statusCode != 200) {
        throw TunesFetchException('search ${res.statusCode}');
      }
      final body = await res.transform(utf8.decoder).join();
      return SearchResults.fromJson(jsonDecode(body) as Map<String, dynamic>);
    } finally {
      client.close(force: true);
    }
  }

  Future<ArtistDiscography> discography(String artist) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final uri = Uri.parse(
        '$baseUrl/discography?artist=${Uri.encodeQueryComponent(artist)}',
      );
      final req = await client.getUrl(uri);
      final res = await req.close().timeout(_timeout);
      if (res.statusCode != 200) {
        throw TunesFetchException('discography ${res.statusCode}');
      }
      final body = await res.transform(utf8.decoder).join();
      return ArtistDiscography.fromJson(
        jsonDecode(body) as Map<String, dynamic>,
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Albums by acts in the library that the library does not have.
  ///
  /// The daemon decides this: it holds the artist discographies, and it skips
  /// any artist whose discography it cannot corroborate against something
  /// already owned, so a common name resolving to the wrong artist does not
  /// turn into a wrong recommendation.
  Future<List<MissingRelease>> missing({int limit = 40}) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final uri = Uri.parse('$baseUrl/missing?limit=$limit');
      final req = await client.getUrl(uri);
      final res = await req.close().timeout(_timeout);
      if (res.statusCode != 200) {
        throw TunesFetchException('missing ${res.statusCode}');
      }
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      return (json['groups'] as List<dynamic>? ?? const [])
          .map((g) => MissingRelease.fromJson(g as Map<String, dynamic>))
          .toList();
    } finally {
      client.close(force: true);
    }
  }

  /// What the daemon says the newest app build is, or null when there is
  /// nothing to report.
  ///
  /// The daemon answers this, not GitHub: the repository is private, and a
  /// token shipped inside an APK is a token anyone can read out of it. 204 is
  /// the ordinary "no update configured or none yet" answer and is not an
  /// error.
  ///
  /// Never throws. An update check that can interrupt the app is worse than no
  /// update check — nobody opened the app to be told about updates.
  Future<AvailableUpdate?> fetchUpdate() async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await client.getUrl(Uri.parse('$baseUrl/update'));
      final res = await req.close().timeout(_timeout);
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      return AvailableUpdate.fromJson(jsonDecode(body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Where the APK lives.
  ///
  /// The daemon serves this range-capable, but [UpdateInstaller] does not ask:
  /// it issues a plain GET and starts over if the transfer breaks. That is
  /// survivable now the APK is ~28 MB rather than ~104 MB, and it is what makes
  /// a failed update harmless -- there is no partial file to resume from and no
  /// way to splice two builds together.
  String get updateApkUrl => '$baseUrl/update/apk';

  /// POSTs JSON to an auth endpoint and returns the status alongside the
  /// decoded body.
  ///
  /// Lives here rather than in the auth client so there is exactly one place
  /// that knows where the server is. [baseUrl] is read at call time, so
  /// changing the server in Settings redirects authentication too -- pinning
  /// it at construction is the bug that made a configured server produce a
  /// library that streamed from an unreachable address.
  ///
  /// A non-JSON body is reported as an empty map with the real status, so a
  /// proxy error page cannot be mistaken for a valid response.
  Future<({int status, Map<String, dynamic> body})> postJson(
    String path,
    Map<String, dynamic> payload, {
    String? bearer,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.postUrl(Uri.parse('$baseUrl$path'));
      req.headers.set('content-type', 'application/json; charset=utf-8');
      if (bearer != null) req.headers.set('authorization', 'Bearer $bearer');
      req.add(utf8.encode(jsonEncode(payload)));
      final res = await req.close().timeout(_timeout);
      final text = await res.transform(utf8.decoder).join();
      Map<String, dynamic> body;
      try {
        final decoded = jsonDecode(text);
        body = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      } catch (_) {
        body = <String, dynamic>{};
      }
      return (status: res.statusCode, body: body);
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> ping() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final req = await client.getUrl(Uri.parse('$baseUrl/manifest'));
      final res = await req.close().timeout(const Duration(seconds: 2));
      return res.statusCode == 200;
    } catch (_) {
      return false;
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

  Future<TunesManifest?> _readCache() async {
    final f = _cacheFile;
    if (f == null) return null;
    try {
      if (!await f.exists()) return null;
      final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return TunesManifest.fromJson(json);
    } catch (_) {
      return null;
    }
  }
}
