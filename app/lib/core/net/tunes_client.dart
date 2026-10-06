import 'dart:convert';
import 'dart:io';

import '../../domain/discography.dart';
import '../sync/sync_models.dart';
import 'update_check.dart';
import '../../domain/manifest.dart';

class ChangesResponse {
  const ChangesResponse({
    required this.generatedAt,
    required this.integrity,
    required this.addedShas,
    this.lyricsChanged = const [],
  });
  final DateTime? generatedAt;
  final String integrity;
  final List<String> addedShas;

  /// Tracks whose lyrics were added or changed since the last look. A new lyric
  /// adds no track, so [addedShas] alone would say nothing had happened.
  final List<String> lyricsChanged;
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

  /// Supplies a bearer token for requests this client makes itself.
  ///
  /// Set by the app once auth exists; null before enrolment and in tests, in
  /// which case requests go out unauthenticated exactly as they used to. A
  /// callback rather than a value because access tokens are short-lived and
  /// re-minted underneath -- capturing one at construction would work for ten
  /// minutes and then quietly stop.
  ///
  /// mpv is not covered by this and cannot be: it fetches media itself and
  /// cannot set headers. That is what signed URLs are for.
  Future<String?> Function()? bearer;

  Future<void> _authorize(HttpClientRequest req) async {
    final token = await bearer?.call();
    if (token != null) req.headers.set('authorization', 'Bearer $token');
  }

  static const _timeout = Duration(seconds: 8);
  static const _bodyTimeout = Duration(seconds: 40);
  static const _downloadTimeout = Duration(minutes: 30);

  File? get _cacheFile {
    final dir = _cacheDir;
    if (dir == null) return null;
    return File('${dir.path}/manifest.json');
  }

  /// The whole library from the daemon.
  ///
  /// [fromCacheOnFailure] hands back the last copy on disk when the daemon
  /// cannot be reached. That is a convenience for showing something, and it
  /// must never be mistaken for a sync: a caller that treats the cached copy as
  /// fresh records "synced just now" while offline, and then asks the daemon
  /// only for what changed since that moment once it is back -- everything
  /// added in between is never fetched, which is a phone stuck on stale
  /// content until it is closed and reopened. The sync passes false.
  Future<TunesManifest> fetchManifest({bool fromCacheOnFailure = true}) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await client.getUrl(Uri.parse('$baseUrl/manifest'));
      await _authorize(req);
      final res = await req.close().timeout(_timeout);
      if (res.statusCode != 200) {
        throw TunesFetchException('manifest ${res.statusCode}');
      }
      // A bound on the body as well as the headers: a connection that dies
      // half way (wifi to mobile data, a phone that slept) otherwise leaves
      // this await open for good, and everything waiting behind it with it.
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(_bodyTimeout);
      final json = jsonDecode(body) as Map<String, dynamic>;
      final manifest = TunesManifest.fromJson(json);
      await _writeCache(body);
      return manifest;
    } on SocketException catch (e) {
      final cached = fromCacheOnFailure ? await _readCache() : null;
      if (cached != null) return cached;
      throw TunesFetchException('tunesd unreachable: ${e.message}');
    } on HttpException catch (e) {
      final cached = fromCacheOnFailure ? await _readCache() : null;
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
      await _authorize(req);
      final res = await req.close().timeout(_timeout);
      if (res.statusCode != 200) {
        throw TunesFetchException('changes ${res.statusCode}');
      }
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(_bodyTimeout);
      final json = jsonDecode(body) as Map<String, dynamic>;
      return ChangesResponse(
        generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? ''),
        integrity: json['integrity'] as String,
        addedShas: ((json['addedShas'] as List?) ?? const [])
            .cast<String>()
            .toList(),
        lyricsChanged: ((json['lyricsChanged'] as List?) ?? const [])
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
      await _authorize(req);
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

  /// Cover bytes for one art sha. Small files, no progress reporting: either
  /// the sleeve arrives whole or it does not arrive at all.
  Future<void> downloadArt(String sha, String path) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await client.getUrl(Uri.parse('$baseUrl/art/$sha'));
      await _authorize(req);
      final res = await req.close().timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        throw TunesFetchException('art ${res.statusCode}');
      }
      await File(path).parent.create(recursive: true);
      final sink = File(path).openWrite();
      try {
        await for (final chunk in res) {
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
    } on SocketException catch (e) {
      await _discardPartial(path);
      throw TunesFetchException('art download failed: ${e.message}');
    } catch (_) {
      await _discardPartial(path);
      rethrow;
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
      await _authorize(req);
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
      await _authorize(req);
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
      await _authorize(req);
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

  /// Whether the server is reachable AND willing to answer this device.
  ///
  /// Authorized like every other request. Without the token this would 401
  /// against an authenticated server and report "offline" forever, on a
  /// daemon that is perfectly healthy -- which is exactly the class of bug
  /// where the message names the wrong thing.
  /// Asks the server to have a cold track ready, without sending its audio.
  ///
  /// `GET /t/<sha>?warm=1` answers 204 once the bytes are in the server's
  /// cache. A hint only: the server declines when it is busy with real
  /// playback, and every failure here is swallowed, because the track still
  /// plays when it is reached either way.
  Future<void> warm(String sha) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final req = await client.getUrl(Uri.parse('$baseUrl/t/$sha?warm=1'));
      await _authorize(req);
      final res = await req.close().timeout(const Duration(seconds: 60));
      await res.drain<void>();
    } catch (_) {
      // A hint, never a reason to bother the listener.
    } finally {
      client.close(force: true);
    }
  }

  /// Shares a listener's lyrics for a track with everyone. True when the
  /// daemon took them. Empty [text] takes the listener's version away.
  ///
  /// Never throws: a failure here must not lose what was typed, which is kept
  /// on this phone and offered again after the next successful sync.
  Future<bool> putLyrics(String sha, String text) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await client.putUrl(Uri.parse('$baseUrl/lyrics/$sha'));
      await _authorize(req);
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode({'lyrics': text})));
      final res = await req.close().timeout(_timeout);
      await res.drain<void>();
      return res.statusCode == 204;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// Sends changed documents to the account (see edge/src/sync.ts). Returns
  /// the server's clock in ms, or null on any failure -- never throws, so a
  /// phone with no signal simply keeps its changes for the next try.
  Future<int?> syncPush(List<SyncDoc> docs) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await client.postUrl(Uri.parse('$baseUrl/sync/push'));
      await _authorize(req);
      req.headers.contentType = ContentType.json;
      req.add(
        utf8.encode(
          jsonEncode({
            'docs': [for (final d in docs) d.toJson()],
          }),
        ),
      );
      final res = await req.close().timeout(_timeout);
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(_bodyTimeout);
      final json = jsonDecode(body);
      return json is Map ? (json['now'] as num?)?.toInt() : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Everything the account has changed after [after], one page. Null on any
  /// failure.
  Future<SyncPullPage?> syncPull(int after, {bool onlyLive = false}) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await client.getUrl(
        Uri.parse(
          '$baseUrl/sync/pull?after=$after${onlyLive ? '&only=live' : ''}',
        ),
      );
      await _authorize(req);
      final res = await req.close().timeout(_timeout);
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(_bodyTimeout);
      return SyncPullPage.fromJson(jsonDecode(body));
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Whether the service answers, asked the cheapest way there is.
  ///
  /// This used to fetch /manifest, the whole library (about 3 MB), every ten
  /// seconds, which is a lot to spend on mobile data to learn one bit.
  /// /changes with "since now" is authenticated like the manifest and answers
  /// in a few bytes, from the daemon and the edge alike.
  Future<bool> ping() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final since = Uri.encodeComponent(
        DateTime.now().toUtc().toIso8601String(),
      );
      final req = await client.getUrl(
        Uri.parse('$baseUrl/changes?since=$since'),
      );
      await _authorize(req);
      final res = await req.close().timeout(const Duration(seconds: 4));
      await res.drain<void>().timeout(const Duration(seconds: 4));
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
