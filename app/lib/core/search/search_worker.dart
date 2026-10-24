import 'dart:async';
import 'dart:isolate';

import '../../domain/library_search.dart';
import '../../domain/manifest.dart';

/// The library search, off the screen's thread (owner, Angel and Dennis,
/// 24 Oct: the search bar lags).
///
/// Building the index took ~0.2 s and readying lyric search ~4 s on a
/// desktop, and a phrase ("don't get hit with") searched every lyric line
/// in ~0.25 s, all on the thread that draws the screen, so typing froze for
/// up to a second on a phone after every pause. Here a worker isolate
/// builds the index once per library and answers each query; the screen
/// only sends the query and draws what comes back.
class SearchWorker {
  SearchWorker._();

  /// Searches on the calling thread instead, for widget tests, whose fake
  /// clock never lets a real isolate's answer arrive. A seam, not a guess.
  static bool inline = false;

  Isolate? _isolate;
  SendPort? _requests;
  ReceivePort? _replies;
  SearchIndex? _local;

  final _pending = <int, Completer<LibrarySearchResults>>{};
  var _next = 0;
  var _closed = false;

  /// Lyric search finished getting ready: a query typed meanwhile may now
  /// find more.
  final lyricsReady = ValueNotifierLike();

  /// Answers on the calling thread, at once (see [inline]).
  bool get isInline => _local != null;

  /// A worker that searches on the calling thread (see [inline]).
  factory SearchWorker.local({
    required List<ManifestTrack> tracks,
    required List<ManifestRelease> releases,
    required List<ManifestArtist> artists,
    required Map<String, int> plays,
  }) {
    final w = SearchWorker._();
    final index = SearchIndex(
      tracks: tracks,
      releases: releases,
      artists: artists,
      plays: plays,
    );
    w._local = index;
    unawaited(
      index.warmLyrics().then((_) {
        if (!w._closed) w.lyricsReady.fire();
      }),
    );
    return w;
  }

  /// A worker isolate holding the library. The library is copied over once.
  static Future<SearchWorker> start({
    required List<ManifestTrack> tracks,
    required List<ManifestRelease> releases,
    required List<ManifestArtist> artists,
    required Map<String, int> plays,
  }) async {
    final w = SearchWorker._();
    final replies = ReceivePort();
    final inbox = Completer<SendPort>();
    w._replies = replies;
    replies.listen((m) {
      if (m is SendPort) {
        inbox.complete(m);
      } else if (m == 'lyricsReady') {
        w.lyricsReady.fire();
      } else if (m is (int, LibrarySearchResults)) {
        w._pending.remove(m.$1)?.complete(m.$2);
      }
    });
    w._isolate = await Isolate.spawn(_main, (
      replies.sendPort,
      tracks,
      releases,
      artists,
      plays,
    ), debugName: 'search');
    w._requests = await inbox.future;
    return w;
  }

  /// The library's results for [raw]. [onlyShas], when given, keeps only
  /// those songs (what is on this phone).
  Future<LibrarySearchResults> search(
    String raw, {
    Set<FacetKind> off = const {},
    SongSort sort = SongSort.best,
    Set<String>? onlyShas,
    List<SearchPlaylist> playlists = const [],
  }) {
    final local = _local;
    if (local != null) {
      return Future.value(
        searchNow(
          raw,
          off: off,
          sort: sort,
          onlyShas: onlyShas,
          playlists: playlists,
        ),
      );
    }
    if (_closed) return Future.error(StateError('search worker closed'));
    final id = _next++;
    final c = Completer<LibrarySearchResults>();
    _pending[id] = c;
    _requests!.send((id, raw, off, sort, onlyShas, playlists));
    return c.future;
  }

  /// [search], answered at once; only for an [isInline] worker.
  LibrarySearchResults searchNow(
    String raw, {
    Set<FacetKind> off = const {},
    SongSort sort = SongSort.best,
    Set<String>? onlyShas,
    List<SearchPlaylist> playlists = const [],
  }) => _local!.search(
    raw,
    off: off,
    sort: sort,
    onlyWhere: onlyShas == null ? null : (t) => onlyShas.contains(t.sha),
    playlists: playlists,
  );

  void dispose() {
    _closed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _replies?.close();
    for (final c in _pending.values) {
      c.completeError(StateError('search worker closed'));
    }
    _pending.clear();
  }

  static void _main(
    (
      SendPort,
      List<ManifestTrack>,
      List<ManifestRelease>,
      List<ManifestArtist>,
      Map<String, int>,
    )
    args,
  ) {
    final (out, tracks, releases, artists, plays) = args;
    final index = SearchIndex(
      tracks: tracks,
      releases: releases,
      artists: artists,
      plays: plays,
    );
    final inbox = ReceivePort();
    out.send(inbox.sendPort);
    inbox.listen((m) {
      final (
        int id,
        String raw,
        Set<FacetKind> off,
        SongSort sort,
        Set<String>? only,
        List<SearchPlaylist> playlists,
      ) = m
          as (
            int,
            String,
            Set<FacetKind>,
            SongSort,
            Set<String>?,
            List<SearchPlaylist>,
          );
      out.send((
        id,
        index.search(
          raw,
          off: off,
          sort: sort,
          onlyWhere: only == null ? null : (t) => only.contains(t.sha),
          playlists: playlists,
        ),
      ));
    });
    // Lyrics after the first queries can be answered; then say so.
    unawaited(index.warmLyrics().then((_) => out.send('lyricsReady')));
  }
}

/// A bare "something happened" signal, so this file needs no Flutter.
class ValueNotifierLike {
  final _listeners = <void Function()>[];
  var _fired = false;

  bool get value => _fired;
  void addListener(void Function() f) => _listeners.add(f);
  void removeListener(void Function() f) => _listeners.remove(f);
  void fire() {
    _fired = true;
    for (final f in List.of(_listeners)) {
      f();
    }
  }
}
