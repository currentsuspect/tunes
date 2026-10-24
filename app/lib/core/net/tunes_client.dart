import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:isolate';

import '../../domain/discography.dart';
import '../sync/sync_models.dart';
import 'update_check.dart';
import '../../domain/about.dart';
import '../../domain/manifest.dart';
import '../../domain/soulseek.dart';

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
      final manifest = await decodeManifestOffMain(body);
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
      // A computer asks about its own build (the Linux bundle).
      final req = await client.getUrl(
        Uri.parse(
          Platform.isLinux
              ? '$baseUrl/update?platform=linux'
              : '$baseUrl/update',
        ),
      );
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
  String get updateApkUrl =>
      Platform.isLinux ? '$baseUrl/update/linux' : '$baseUrl/update/apk';

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
  ///
  /// [signedPath] is the song's signed `/t/<sha>?…` path: the fetch worker
  /// only takes media grants, and the device token this used to send was
  /// refused (401) every time, so no song was ever warmed.
  Future<void> warm(String sha, {String? signedPath}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final path = signedPath ?? '/t/$sha';
      final sep = path.contains('?') ? '&' : '?';
      final req = await client.getUrl(Uri.parse('$baseUrl$path${sep}warm=1'));
      if (signedPath == null) await _authorize(req);
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

  /// A moment of [sha] from [from] to [to], cut by the box (tunesd clip.ts):
  /// a short video over [card] (a PNG), or audio alone when [card] is null.
  /// Null on any failure; never throws.
  Future<Uint8List?> clip(
    String sha,
    Duration from,
    Duration to, {
    Uint8List? card,
  }) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await client.postUrl(
        Uri.parse(
          '$baseUrl/clip/$sha'
          '?from=${from.inMilliseconds}&to=${to.inMilliseconds}',
        ),
      );
      await _authorize(req);
      if (card != null) {
        req.headers.contentType = ContentType('image', 'png');
        req.add(card);
      }
      // Cutting is quick, but an archived song is fetched first.
      final res = await req.close().timeout(const Duration(seconds: 90));
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in res.timeout(const Duration(seconds: 90))) {
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } catch (_) {
      return null;
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
  /// `/update` is public and a few bytes, answered in milliseconds. The two
  /// things this used to ask were wrong for opposite reasons: /manifest is the
  /// whole library (about 3 MB every ten seconds), and /changes makes the box
  /// rebuild that manifest from scratch on every call, which on a busy box takes
  /// seconds -- longer than the check would wait, so a perfectly good
  /// connection was reported as lost, over and over.
  ///
  /// Any answer short of a server error counts: this asks "is it there", and a
  /// 401 from a token that needs refreshing is the server very much being there.
  Future<bool> ping() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.getUrl(Uri.parse('$baseUrl/update'));
      final res = await req.close().timeout(const Duration(seconds: 6));
      await res.drain<void>().timeout(const Duration(seconds: 6));
      return res.statusCode < 500;
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

  // --- Soulseek (tunesd getter.ts) ---------------------------------------

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Object? body,
    Duration timeout = _timeout,
  }) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await client.openUrl(method, Uri.parse('$baseUrl$path'));
      await _authorize(req);
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(jsonEncode(body)));
      }
      final res = await req.close().timeout(timeout);
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) {
        throw TunesFetchException('$path ${res.statusCode}');
      }
      return jsonDecode(text) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  /// Songs out there for [q]. Slow: the box asks Soulseek and waits for
  /// answers (about ten seconds), so this has a long timeout of its own.
  Future<List<FoundSong>> soulseekSearch(String q) async {
    final j = await _json(
      'GET',
      '/soulseek/search?q=${Uri.encodeQueryComponent(q)}',
      timeout: const Duration(seconds: 60),
    );
    return [
      for (final s in j['songs'] as List<dynamic>? ?? const [])
        FoundSong.fromJson(s as Map<String, dynamic>),
    ];
  }

  /// Asks the box to get [song] (the copy found in search, else whatever
  /// it finds), or a song by name for an album's missing track.
  Future<GetJob> soulseekGet({
    required String title,
    required String artist,
    String? album,
    int? durationMs,
    String? release,
    FoundSong? copy,
  }) async {
    final j = await _json(
      'POST',
      '/soulseek/get',
      body: {
        'title': title,
        'artist': artist,
        'album': ?album,
        'durationMs': ?durationMs,
        'release': ?release,
        if (copy != null) ...{
          'username': copy.username,
          'filename': copy.filename,
          'size': copy.sizeBytes,
        },
      },
    );
    return GetJob.fromJson(j['job'] as Map<String, dynamic>);
  }

  /// The last day's gets, newest first.
  Future<List<GetJob>> soulseekJobs({int? days}) async {
    final j = await _json(
      'GET',
      days == null ? '/soulseek/jobs' : '/soulseek/jobs?days=$days',
    );
    return [
      for (final x in j['jobs'] as List<dynamic>? ?? const [])
        GetJob.fromJson(x as Map<String, dynamic>),
    ];
  }

  /// Takes a waiting song out of the line. False when it had already
  /// started (a download under way finishes) or the box forgot it.
  Future<bool> soulseekCancel(String id) async {
    try {
      await _json('POST', '/soulseek/cancel', body: {'id': id});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Gets every song of [releaseId] the library lacks.
  Future<List<GetJob>> soulseekComplete(String releaseId) async {
    final j = await _json(
      'POST',
      '/soulseek/complete',
      body: {'release': releaseId},
      timeout: const Duration(seconds: 30),
    );
    return [
      for (final x in j['jobs'] as List<dynamic>? ?? const [])
        GetJob.fromJson(x as Map<String, dynamic>),
    ];
  }

  /// An album's full track list, or null when the box does not know it.
  Future<List<TracklistEntry>?> tracklist(String releaseId) async {
    try {
      final j = await _json(
        'GET',
        '/tracklist?release=${Uri.encodeQueryComponent(releaseId)}',
        timeout: const Duration(seconds: 20),
      );
      return [
        for (final t in j['tracks'] as List<dynamic>? ?? const [])
          TracklistEntry.fromJson(t as Map<String, dynamic>),
      ];
    } on TunesFetchException {
      return null;
    }
  }

  /// What Genius knows about a song (tunesd about.ts), with its album's
  /// write-up. Null when the box cannot say; the page simply leaves those
  /// sections out.
  Future<({SongAbout? song, AlbumAbout? album})?> aboutSong(String sha) async {
    try {
      final j = await _json(
        'GET',
        '/about/song?sha=$sha',
        timeout: const Duration(seconds: 15),
      );
      final s = j['song'] as Map<String, dynamic>?;
      final a = j['album'] as Map<String, dynamic>?;
      return (
        song: s == null ? null : SongAbout.fromJson(s),
        album: a == null ? null : AlbumAbout.fromJson(a),
      );
    } on TunesFetchException {
      return null;
    }
  }

  Future<AlbumAbout?> aboutAlbum(String releaseId) async {
    try {
      final j = await _json(
        'GET',
        '/about/album?release=${Uri.encodeQueryComponent(releaseId)}',
        timeout: const Duration(seconds: 15),
      );
      final a = j['album'] as Map<String, dynamic>?;
      return a == null ? null : AlbumAbout.fromJson(a);
    } on TunesFetchException {
      return null;
    }
  }

  Future<({ArtistAbout? artist, List<Collaborator> people})?> aboutArtist(
    String name,
  ) async {
    try {
      final j = await _json(
        'GET',
        '/about/artist?name=${Uri.encodeQueryComponent(name)}',
        timeout: const Duration(seconds: 20),
      );
      final a = j['artist'] as Map<String, dynamic>?;
      return (
        artist: a == null ? null : ArtistAbout.fromJson(a),
        people: [
          for (final p in (j['people'] as List<dynamic>? ?? const []))
            Collaborator.fromJson(p as Map<String, dynamic>),
        ],
      );
    } on TunesFetchException {
      return null;
    }
  }

  /// The songs a person made that the library holds, and how.
  Future<List<Work>?> aboutPerson(String name) async {
    try {
      final j = await _json(
        'GET',
        '/about/person?name=${Uri.encodeQueryComponent(name)}',
        timeout: const Duration(seconds: 15),
      );
      return [
        for (final w in (j['work'] as List<dynamic>? ?? const []))
          Work.fromJson(w as Map<String, dynamic>),
      ];
    } on TunesFetchException {
      return null;
    }
  }

  Future<TunesManifest?> _readCache() async {
    final f = _cacheFile;
    if (f == null) return null;
    try {
      if (!await f.exists()) return null;
      return await decodeManifestOffMain(await f.readAsString());
    } catch (_) {
      return null;
    }
  }
}

/// Turns the library file into a [TunesManifest] on another isolate.
///
/// It is about 8 MB and 2,400 songs. Decoding it took 230-350 ms on the
/// laptop (24 Oct) and several times that on a phone, all on the thread that
/// draws the screen, so every sync that brought a new song froze the app for
/// a moment. Here the screen keeps moving; only the finished objects are
/// copied back.
Future<TunesManifest> decodeManifestOffMain(String body) =>
    Isolate.run(() => _decodeManifest(body), debugName: 'manifest');

TunesManifest _decodeManifest(String body) =>
    TunesManifest.fromJson(jsonDecode(body) as Map<String, dynamic>);
