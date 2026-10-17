import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../platform/diag_log.dart';
import 'byte_ranges.dart';

/// Plays streamed songs through this phone, so every byte heard is kept.
///
/// mpv used to stream each song straight from the server and throw the bytes
/// away; the stream cache was filled by a second, separate download of the
/// whole file that only began after eight seconds of play. Offline, a song
/// that had been playing for a minute had nothing on the phone.
///
/// Now mpv reads `http://127.0.0.1:<port>/s/<sha>` from here. The relay fetches
/// from the server, writes each byte into the song's cache file as it arrives,
/// and serves mpv from that file:
///
/// - one transfer per song, and what has been heard is on the phone;
/// - a seek into bytes that have arrived is a file read, with no round trip;
///   a seek past them restarts the fetch from there, keeping what came before;
/// - a song being played ([keepAll]) is fetched to its end straight away, so
///   stepping out of signal mid-song does not stop it; a song mpv only touched
///   (its playlist prefetch) gets a window ahead of the reader, not the file;
/// - a complete file is handed to [commit] and becomes a cache hit.
class StreamRelay {
  StreamRelay({
    required this.dir,
    required this.upstreamFor,
    required this.commit,
    this.onRefused,
    this.window = 4 * 1024 * 1024,
    this.maxFetches = 3,
    this.stallAfter = const Duration(seconds: 15),
  });

  /// A fetch that makes no progress for this long (no answer, no bytes) is
  /// cut off and its slot freed. On the phone (16 Oct) runs restarted at a
  /// seek sometimes never got an answer, stayed "fetching" for good, and with
  /// both slots held no other song could start until the app was restarted.
  final Duration stallAfter;

  /// Where partial and complete files live: the stream cache's directory, so
  /// a finished file is already where the cache keeps it.
  final Directory dir;

  /// The server address for a song, signed. Read per fetch, since grants
  /// expire and the server can change.
  final Future<Uri> Function(String sha) upstreamFor;

  /// A song is complete on the phone at this path.
  final Future<void> Function(String sha, String path) commit;

  /// The server refused the song's signature (expired, or minted for a
  /// session that has since changed). Drop it so [upstreamFor] mints anew.
  final void Function(String sha)? onRefused;

  /// How far ahead of the reader a song that is not being kept is fetched.
  final int window;

  /// Songs fetched at once. The one playing comes first; see [_admit].
  final int maxFetches;

  HttpServer? _server;
  final Map<String, _Entry> _entries = {};

  int? get port => _server?.port;

  Future<void> start() async {
    if (_server != null) return;
    await dir.create(recursive: true);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(
      (req) => unawaited(_serve(req)),
      onError: (Object e) => DiagLog.log('relay: server error $e'),
    );
    DiagLog.log('relay: listening on ${server.port}');
  }

  Future<void> close() async {
    for (final e in _entries.values) {
      e.cancel();
    }
    await _server?.close(force: true);
    _server = null;
  }

  /// The address mpv plays [sha] from, or null before [start].
  String? urlFor(String sha) {
    final p = port;
    return p == null ? null : 'http://127.0.0.1:$p/s/$sha';
  }

  bool isRelayUrl(String uri) {
    final p = port;
    return p != null && uri.startsWith('http://127.0.0.1:$p/');
  }

  String pathFor(String sha) => '${dir.path}/$sha';

  /// This song is being listened to: fetch all of it, now.
  void keepAll(String sha) {
    final e = _entry(sha);
    if (e.committed) return;
    e.wantAll = true;
    _pump(e);
  }

  /// Fetch [sha] whole ahead of being reached, if a fetch slot is free.
  void prefetch(String sha) {
    final e = _entry(sha);
    if (e.committed || e.wantAll) return;
    e.wantAll = true;
    e.background = true;
    _pump(e);
  }

  /// Bytes on the phone for [sha] so far, and the size when known.
  ({int have, int? total}) progressOf(String sha) {
    final e = _entries[sha];
    if (e == null) return (have: 0, total: null);
    return (have: e.ranges.length, total: e.total);
  }

  List<Map<String, Object?>> debugState() => [
    for (final e in _entries.values) e.describe(),
  ];

  /// Connections reading [sha] right now. For tests and the state page.
  int readersOf(String sha) => _entries[sha]?.readers ?? 0;

  _Entry _entry(String sha) {
    final e = _entries[sha];
    // Committed, then evicted from the cache: start over.
    if (e != null && e.committed && !File(e.path).existsSync()) {
      _entries.remove(sha);
    }
    return _entries.putIfAbsent(sha, () => _Entry(sha, pathFor(sha)));
  }

  // ---------------------------------------------------------------- serving

  Future<void> _serve(HttpRequest req) async {
    final res = req.response;
    final parts = req.uri.pathSegments;
    if (req.uri.path == '/state') {
      // What each song's fetch is doing, for debugging over adb. Loopback
      // only, and only hashes: never a title or a file name.
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode([for (final e in _entries.values) e.describe()]));
      await res.close();
      return;
    }
    if (parts.length != 2 || parts[0] != 's' || !_isSha(parts[1])) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    final e = _entry(parts[1]);
    final head = req.method == 'HEAD';
    final reqRange = req.headers.value(HttpHeaders.rangeHeader);
    final start = _rangeStart(reqRange);
    e.readers += 1;
    try {
      e.demand(start);
      _pump(e, from: start);
      final total = await e.whenTotal().timeout(
        const Duration(seconds: 25),
        onTimeout: () => null,
      );
      if (total == null) {
        res.statusCode = HttpStatus.badGateway;
        await res.close();
        return;
      }
      final explicitEnd = _rangeEnd(reqRange);
      final end = math.min(explicitEnd ?? total - 1, total - 1);
      if (start >= total) {
        res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
        await res.close();
        return;
      }
      res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      res.headers.contentType = ContentType.parse(
        e.type ?? 'application/octet-stream',
      );
      res.contentLength = end - start + 1;
      if (reqRange != null) {
        res.statusCode = HttpStatus.partialContent;
        res.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/$total',
        );
      }
      if (head) {
        await res.close();
        return;
      }
      await _pipe(e, res, start, end);
    } catch (err) {
      e.lastServeError = '$err';
      // The reader went away (a seek opens a new one), or the fetch failed
      // with nothing left to give. Either way this connection is over.
      try {
        await res.close();
      } catch (_) {}
    } finally {
      e.readers -= 1;
    }
  }

  /// Writes `[start, end]` to [res] as the bytes become available. Ends the
  /// response early, which mpv reads as an error, when the bytes cannot come:
  /// offline, past what has arrived.
  Future<void> _pipe(_Entry e, HttpResponse res, int start, int end) async {
    final f = File(e.path);
    if (!f.existsSync()) await f.create(recursive: true);
    final file = await f.open();
    // The body is written on the raw socket. Dart's HTTP layer never notices
    // a client that has gone: a flush to a closed connection just waits, so
    // every abandoned seek used to leave a reader parked for good, counted as
    // a listener. The socket reports the other side closing at once.
    res.persistentConnection = false;
    final socket = await res.detachSocket(writeHeaders: true);
    final hungUp = Completer<void>();
    socket.listen(
      (_) {},
      onDone: () => hungUp.isCompleted ? null : hungUp.complete(),
      onError: (Object _) => hungUp.isCompleted ? null : hungUp.complete(),
      cancelOnError: true,
    );
    try {
      var pos = start;
      while (pos <= end && !hungUp.isCompleted) {
        final avail = e.ranges.runEnd(pos);
        if (avail > pos) {
          final n = math.min(math.min(avail, end + 1) - pos, 256 * 1024);
          await file.setPosition(pos);
          final bytes = await file.read(n);
          if (bytes.isEmpty) break;
          socket.add(bytes);
          // A paused mpv that stops reading keeps its connection and waits
          // here as long as it likes; one that hung up ends it.
          await Future.any<void>([socket.flush(), hungUp.future]);
          if (hungUp.isCompleted) break;
          pos += bytes.length;
          e.demand(pos);
          _pump(e, from: pos);
          continue;
        }
        _pump(e, from: pos);
        if (!e.fetching && e.recentlyFailed) {
          // Nothing is coming: let mpv see the end and decide.
          DiagLog.log('relay: no bytes past $pos, ending the stream');
          break;
        }
        await Future.any<void>([
          e.changed(),
          hungUp.future,
          Future<void>.delayed(const Duration(seconds: 30)),
        ]);
        if (!e.fetching && !e.ranges.has(pos) && e.recentlyFailed) break;
      }
    } catch (_) {
      // Writing to a connection that is gone: nothing more to do.
    } finally {
      await file.close();
      socket.destroy();
    }
  }

  // ---------------------------------------------------------------- fetching

  /// Starts or redirects the fetch for [e] so the bytes the reader needs come
  /// next. Called often; does nothing when the fetch is already on its way.
  void _pump(_Entry e, {int? from}) {
    if (e.committed) return;
    final total = e.total;
    if (total != null && e.ranges.covers(total)) {
      unawaited(_finish(e));
      return;
    }
    final need = from ?? 0;
    final want = total == null ? need : e.ranges.firstGap(need, total);
    if (e.fetching) {
      // Already fetching near enough to the reader: let it run. Far behind or
      // past it (a seek), move it.
      final cursor = e.cursor;
      if (want == null || from == null) return;
      if (want >= cursor && want - cursor < 512 * 1024) return;
      if (e.runFrom <= want && want < cursor) return;
      e.cancel();
      e.restartAt = want;
      return;
    }
    if (e.recentlyFailed) return;
    final at = want ?? (total == null ? 0 : e.ranges.firstGap(0, total));
    if (at == null) return;
    if (!_shouldFetch(e, at)) return;
    if (!_admit(e)) return;
    unawaited(_fetch(e, at));
  }

  /// Whether more of [e] is wanted from [at]: all of it when kept, else only a
  /// window ahead of the furthest a reader has asked for.
  bool _shouldFetch(_Entry e, int at) {
    if (e.wantAll) return true;
    if (e.readers == 0) return false;
    return at < e.demandHigh + window;
  }

  /// One slot per song; a background prefetch never takes the last free slot
  /// from a song someone is listening to.
  bool _admit(_Entry e) {
    final running = _entries.values.where((x) => x.fetching).length;
    final listened = e.readers > 0 || !e.background;
    if (running < maxFetches) {
      // A prefetch leaves the last slot for a song someone is hearing.
      return listened || running < maxFetches - 1;
    }
    if (!listened) return false;
    // A song being listened to bumps a background prefetch; when that run
    // ends, the freed slot goes to songs with readers first (see _fetch).
    for (final x in _entries.values) {
      if (x.fetching && x.background && x.readers == 0) {
        x.cancel();
        break;
      }
    }
    return false;
  }

  Future<void> _fetch(_Entry e, int from) async {
    e.fetching = true;
    e.runFrom = from;
    e.cursor = from;
    final token = e.newRun();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 15);
    RandomAccessFile? out;
    // Every step marks progress; a watchdog cuts the run off when none comes.
    var stalled = false;
    void step(String phase) {
      e.phase = phase;
      e.phaseAt = DateTime.now();
    }

    step('signing');
    final watchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      final at = e.phaseAt;
      if (at == null || DateTime.now().difference(at) < stallAfter) return;
      if (stalled) return;
      stalled = true;
      DiagLog.log('relay: run stalled at ${e.phase}, cutting it off');
      token.cancelled = true;
      client.close(force: true);
      e.notify();
    });
    try {
      final uri = await upstreamFor(e.sha).timeout(stallAfter);
      step('connecting');
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=$from-');
      // The file exists before anyone learns the size: a reader that heard
      // the size opened the file at once, found nothing, and its reply died
      // empty, which mpv takes as a failed song.
      out = await File(e.path).open(mode: FileMode.append);
      step('waiting');
      final res = await req.close().timeout(stallAfter);
      step('receiving');
      e.lastUpstream =
          '${res.statusCode} len=${res.contentLength} '
          'range=${res.headers.value(HttpHeaders.contentRangeHeader)} '
          'enc=${res.headers.value(HttpHeaders.contentEncodingHeader)}';
      var at = from;
      if (res.statusCode == HttpStatus.ok) {
        at = 0; // the server ignored the range: it starts at the top
        e.setTotal(res.contentLength > 0 ? res.contentLength : null);
      } else if (res.statusCode == HttpStatus.partialContent) {
        e.setTotal(_totalOf(res.headers.value(HttpHeaders.contentRangeHeader)));
      } else if (res.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
        e.setTotal(_totalOf(res.headers.value(HttpHeaders.contentRangeHeader)));
        await res.drain<void>();
        return;
      } else if ((res.statusCode == HttpStatus.unauthorized ||
              res.statusCode == HttpStatus.forbidden) &&
          !e.refusedOnce) {
        // A stale signature, not a dead server: sign again and go straight
        // back, once. Without this a song kept failing until a restart
        // re-signed the queue.
        e.refusedOnce = true;
        await res.drain<void>();
        onRefused?.call(e.sha);
        e.restartAt = from;
        return;
      } else {
        throw HttpException('upstream ${res.statusCode}');
      }
      e.type ??= res.headers.contentType?.mimeType;
      e.cursor = at;
      await for (final chunk in res.timeout(const Duration(seconds: 20))) {
        if (token.cancelled) break;
        // Written where it belongs: a run restarted after a seek overlaps
        // nothing it should not, and rewriting identical bytes is harmless.
        await out.setPosition(at);
        await out.writeFrom(chunk);
        step('receiving');
        e.ranges.add(at, at + chunk.length);
        at += chunk.length;
        e.cursor = at;
        e.notify();
        final total = e.total;
        if (total != null && at >= total) break;
        if (!e.wantAll && e.readers == 0) break;
        if (!e.wantAll && at > e.demandHigh + window) break;
        final gapAhead = total == null ? at : e.ranges.firstGap(at, total);
        if (gapAhead != null && gapAhead > at) break; // ran into bytes we have
      }
      if (stalled) throw StateError('stalled at ${e.phase}');
      e.failedAt = null;
      if (e.ranges.length > 0) e.refusedOnce = false;
    } catch (err) {
      if (stalled || !token.cancelled) {
        e.failedAt = DateTime.now();
        e.lastError = '$err';
        DiagLog.log('relay: fetch stopped ($err)');
      }
    } finally {
      watchdog.cancel();
      e.phase = stalled ? 'stalled' : 'idle';
      e.phaseAt = DateTime.now();
      await out?.close();
      client.close(force: true);
      e.fetching = false;
      e.notify();
      final restart = e.restartAt;
      e.restartAt = null;
      if (restart != null) {
        _pump(e, from: restart);
      } else {
        // A slot came free: songs someone is hearing first, then this one,
        // then any prefetch still waiting.
        for (final x in _entries.values.toList()) {
          if (!identical(x, e) &&
              !x.fetching &&
              !x.committed &&
              x.readers > 0) {
            _pump(x, from: x.demandHigh);
          }
        }
        _pump(e, from: e.cursor);
        for (final x in _entries.values.toList()) {
          if (!identical(x, e) && !x.fetching && !x.committed) {
            _pump(x, from: x.demandHigh);
          }
        }
      }
    }
  }

  Future<void> _finish(_Entry e) async {
    if (e.committed || e.committing) return;
    e.committing = true;
    try {
      final total = e.total!;
      final len = await File(e.path).length();
      if (len < total) {
        e.committing = false;
        return;
      }
      if (len > total) {
        final f = await File(e.path).open(mode: FileMode.append);
        await f.truncate(total);
        await f.close();
      }
      await commit(e.sha, e.path);
      e.committed = true;
      DiagLog.log('relay: song complete on the phone');
    } catch (err) {
      e.committing = false;
      DiagLog.log('relay: commit failed ($err)');
    }
  }

  /// Removes partial files a previous run left behind: the ranges that say
  /// which of their bytes are real lived in memory and are gone.
  Future<void> dropPartials(bool Function(String sha) isComplete) async {
    try {
      await for (final f in dir.list()) {
        if (f is! File) continue;
        final name = f.uri.pathSegments.last;
        if (!_isSha(name)) continue;
        if (isComplete(name) || _entries.containsKey(name)) continue;
        await f.delete();
      }
    } catch (_) {}
  }

  static bool _isSha(String s) => RegExp(r'^[0-9a-f]{64}$').hasMatch(s);

  static int _rangeStart(String? header) {
    if (header == null) return 0;
    final m = RegExp(r'^bytes=(\d+)-').firstMatch(header.trim());
    return m == null ? 0 : int.parse(m.group(1)!);
  }

  static int? _rangeEnd(String? header) {
    if (header == null) return null;
    final m = RegExp(r'^bytes=\d+-(\d+)$').firstMatch(header.trim());
    return m == null ? null : int.parse(m.group(1)!);
  }

  static int? _totalOf(String? contentRange) {
    if (contentRange == null) return null;
    final m = RegExp(r'/(\d+)$').firstMatch(contentRange.trim());
    return m == null ? null : int.parse(m.group(1)!);
  }
}

class _RunToken {
  bool cancelled = false;
}

class _Entry {
  _Entry(this.sha, this.path);

  final String sha;
  final String path;
  final ByteRanges ranges = ByteRanges();
  int? total;
  String? type;
  bool wantAll = false;
  bool background = false;
  bool fetching = false;
  bool committing = false;
  bool committed = false;
  bool refusedOnce = false;
  String? lastUpstream;
  String? lastError;
  String? lastServeError;
  String phase = 'idle';
  DateTime? phaseAt;
  int readers = 0;
  int runFrom = 0;
  int cursor = 0;
  int demandHigh = 0;
  int? restartAt;
  DateTime? failedAt;
  _RunToken _run = _RunToken();
  Completer<void> _changed = Completer<void>();
  final Completer<int?> _total = Completer<int?>();

  Map<String, Object?> describe() => {
    'sha': sha.substring(0, 10),
    'total': total,
    'have': ranges.length,
    'fetching': fetching,
    'runFrom': runFrom,
    'cursor': cursor,
    'demandHigh': demandHigh,
    'readers': readers,
    'phase': phase,
    'phaseFor': phaseAt == null
        ? null
        : DateTime.now().difference(phaseAt!).inMilliseconds,
    'wantAll': wantAll,
    'committed': committed,
    'upstream': lastUpstream,
    'error': lastError,
    'serveError': lastServeError,
  };

  bool get recentlyFailed {
    final f = failedAt;
    return f != null &&
        DateTime.now().difference(f) < const Duration(seconds: 5);
  }

  _RunToken newRun() => _run = _RunToken();

  void cancel() => _run.cancelled = true;

  void demand(int pos) {
    if (pos > demandHigh) demandHigh = pos;
  }

  void setTotal(int? t) {
    if (t == null) return;
    total ??= t;
    if (!_total.isCompleted) _total.complete(t);
  }

  Future<int?> whenTotal() {
    final t = total;
    if (t != null) return Future.value(t);
    // A failed fetch ends the wait instead of holding mpv for the timeout.
    return Future.any([_total.future, _waitFailure()]);
  }

  Future<int?> _waitFailure() async {
    while (true) {
      await changed();
      if (total != null) return total;
      if (!fetching && recentlyFailed) return null;
    }
  }

  Future<void> changed() => _changed.future;

  void notify() {
    final c = _changed;
    _changed = Completer<void>();
    if (!c.isCompleted) c.complete();
  }
}
