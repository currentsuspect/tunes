import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'core/audio/tune_audio_handler.dart';
import 'core/audio/tune_player.dart';
import 'core/data/database.dart';
import 'core/data/download_manager.dart';
import 'core/data/download_store.dart';
import 'core/data/manifest_store.dart';
import 'core/data/queue_store.dart';
import 'core/data/reachability.dart';
import 'core/net/tunes_client.dart';
import 'core/platform/diag_log.dart';
import 'core/theme/theme.dart';
import 'core/theme/tokens.dart';
import 'domain/discography.dart';
import 'domain/manifest.dart';
import 'features/album/album_page.dart';
import 'features/artist/artist_page.dart';
import 'features/home/home_view.dart';
import 'features/library/library_view.dart';
import 'features/now_playing/now_playing_page.dart';
import 'features/player/mini_player_bar.dart';
import 'features/profile/profile_sheet.dart';
import 'features/search/search_view.dart';

const _gitCommit = String.fromEnvironment('GIT_COMMIT', defaultValue: 'local');
const _buildNumber = String.fromEnvironment(
  'BUILD_NUMBER',
  defaultValue: 'local',
);
const _channel = String.fromEnvironment('CHANNEL', defaultValue: 'local');
const _tunesdUrl = String.fromEnvironment(
  'TUNESD_URL',
  defaultValue: 'http://192.168.100.6:4780',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('SKIP_MEDIAKIT')) {
    MediaKit.ensureInitialized();
  }
  await DiagLog.init();
  DiagLog.log('main start');
  final support = await getApplicationSupportDirectory();
  final store = DownloadStore(support);
  await store.load();
  final db = TunesDatabase();
  final manifestStore = ManifestStore(db);
  final queueStore = QueueStore(db);
  final client = TunesClient(_tunesdUrl, support);
  final reachability = Reachability();
  Heartbeat(ping: client.ping, reachability: reachability).start();
  final player = MediaKitTunePlayer(
    trackUriFor: (track) {
      final path = store.pathFor(track.sha);
      if (path != null && File(path).existsSync()) return path;
      return '$_tunesdUrl/track/${track.sha}';
    },
    onQueuePlayed: (tracks) {
      // Mirror the play queue into the persistent store so the
      // QueueSheet reflects what's playing, and the queue survives
      // restarts. All playback entry points (home, library, album,
      // artist, search) route through this single hook.
      unawaited(queueStore.replace(tracks.map((t) => t.sha).toList()));
    },
  );
  var audioServiceReady = false;
  Future<void> ensureAudioService() async {
    if (audioServiceReady) return;
    audioServiceReady = true;
    try {
      await AudioService.init(
        builder: () => TuneAudioHandler(player, artBase: _tunesdUrl),
        config: const AudioServiceConfig(
          androidNotificationChannelId:
              'com.currentsuspect.tunes.channel.audio',
          androidNotificationChannelName: 'Tunes playback',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );
      AudioService.asyncError.listen((e) => DiagLog.log('async error: $e'));
      DiagLog.log('audio_service init ok (lazy)');
    } catch (e) {
      audioServiceReady = false;
      DiagLog.log('AudioService.init failed (lazy): $e');
    }
  }

  player.onFirstPlay = ensureAudioService;

  DiagLog.log('runApp');
  runApp(
    TunesApp(
      client: client,
      player: player,
      store: store,
      reachability: reachability,
      manifestStore: manifestStore,
      queueStore: queueStore,
    ),
  );
}

class TunesApp extends StatelessWidget {
  const TunesApp({
    super.key,
    required this.client,
    required this.player,
    required this.store,
    required this.reachability,
    required this.manifestStore,
    required this.queueStore,
  });

  final TunesClient client;
  final TunePlayer player;
  final DownloadStore store;
  final Reachability reachability;
  final ManifestStore manifestStore;
  final QueueStore queueStore;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return MaterialApp(
      title: 'tunes',
      debugShowCheckedModeBanner: false,
      theme: buildTunesTheme(mq),
      home: AppShell(
        client: client,
        player: player,
        store: store,
        reachability: reachability,
        manifestStore: manifestStore,
        queueStore: queueStore,
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.client,
    required this.player,
    required this.store,
    required this.reachability,
    required this.manifestStore,
    required this.queueStore,
  });

  final TunesClient client;
  final TunePlayer player;
  final DownloadStore store;
  final Reachability reachability;
  final ManifestStore manifestStore;
  final QueueStore queueStore;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _tab = 0;
  TunesManifest? _manifest;
  bool _syncing = false;
  Object? _lastSyncError;
  DateTime? _lastSyncAt;
  final Set<String> _downloading = {};
  late final DownloadManager _downloads;
  final String _libraryFilter = '';
  List<ManifestTrack> _recents = [];
  // Fetched, not derived: deciding what is missing entirely needs the artist
  // discographies, which live on the daemon. Failure is silent -- the section
  // simply does not appear, which is the right answer when we cannot say.
  List<MissingRelease> _missingAlbums = const [];

  bool _wasOffline = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _downloads = DownloadManager(client: widget.client, store: widget.store);
    // The screens below still take a Set<String> of in-flight shas; keep it in
    // step with the manager rather than re-plumbing six widgets.
    _downloads.addListener(_onDownloadsChanged);
    _wasOffline = widget.reachability.offline;
    widget.reachability.addListener(_onReachability);
    widget.player.addListener(_trackRecents);
    // Hydrate from the store before kicking off a sync, so the sync's
    // setState doesn't race against a stale in-memory snapshot.
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.reachability.removeListener(_onReachability);
    widget.player.removeListener(_trackRecents);
    _downloads.removeListener(_onDownloadsChanged);
    _downloads.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !widget.reachability.offline) {
      _reload();
    }
  }

  void _onReachability() {
    final offline = widget.reachability.offline;
    if (_wasOffline && !offline) {
      _reload();
    }
    _wasOffline = offline;
  }

  void _trackRecents() {
    final current = widget.player.current;
    if (widget.player.playing && current != null) {
      final next = [
        current,
        ..._recents.where((t) => t.sha != current.sha),
      ].take(10).toList();
      if (next.length != _recents.length ||
          next.first.sha != (_recents.isEmpty ? '' : _recents.first.sha)) {
        setState(() => _recents = next);
      }
    }
  }

  Future<void> _hydrateFromStore() async {
    try {
      final manifest = await _manifestFromStore();
      if (mounted) setState(() => _manifest = manifest);
    } catch (_) {
      // cold start with empty db is fine; _sync will fill it.
    }
  }

  Future<void> _bootstrap() async {
    await _hydrateFromStore();
    if (mounted) await _sync();
  }

  Future<TunesManifest> _manifestFromStore() async {
    final tracks = await widget.manifestStore.allTracksNewestFirst();
    final releases = await widget.manifestStore.allReleases();
    final artists = await widget.manifestStore.allArtists();
    return TunesManifest(tracks: tracks, releases: releases, artists: artists);
  }

  Future<void> _sync() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _lastSyncError = null;
    });
    // True iff the local store is now in sync with the daemon. Only
    // advance the watermark when this is true — otherwise a transient
    // error could mask new tracks behind a stale timestamp.
    var synced = false;
    // Try the delta endpoint first. If the daemon says nothing has
    // changed since our last sync, skip the full manifest download
    // entirely. Falls through to /manifest on any error.
    var needFull = true;
    var lastSync = _lastSyncAt;
    if (lastSync != null) {
      try {
        final changes = await widget.client.fetchChanges(lastSync);
        if (changes.addedShas.isEmpty) {
          needFull = false;
          widget.reachability.setOffline(false);
          synced = true;
        }
      } catch (_) {
        // Any /changes failure → fall through to /manifest.
      }
    }
    if (needFull) {
      TunesManifest? raw;
      Object? fetchError;
      try {
        raw = await widget.client.fetchManifest();
        widget.reachability.setOffline(false);
      } catch (e) {
        fetchError = e;
        widget.reachability.setOffline(true);
      }
      if (raw != null && mounted) {
        var applyOk = false;
        try {
          await widget.manifestStore.apply(raw);
          applyOk = true;
        } catch (e) {
          if (mounted) setState(() => _lastSyncError = e);
        }
        if (mounted && applyOk) {
          final fresh = await _manifestFromStore();
          if (mounted) setState(() => _manifest = fresh);
          synced = true;
        }
      } else if (fetchError != null && mounted) {
        setState(() => _lastSyncError = fetchError);
      }
    }
    if (mounted) {
      setState(() {
        if (synced) _lastSyncAt = DateTime.now();
        _syncing = false;
      });
    }
    // Not awaited: this is a suggestion rail, and the library must not wait
    // on it. Only refreshed after a real sync, since the answer changes only
    // when what we hold changes.
    if (mounted && synced) unawaited(_loadMissing());
  }

  Future<void> _loadMissing() async {
    try {
      final albums = await widget.client.missing();
      if (mounted) setState(() => _missingAlbums = albums);
    } catch (_) {
      // An older daemon answers 404 here, and offline answers nothing. Both
      // mean "cannot say", so leave whatever we last knew on screen rather
      // than blanking a section that was correct a minute ago.
    }
  }

  void _reload() {
    _sync();
  }

  void _onDownloadsChanged() {
    if (!mounted) return;
    final active = _downloads.jobs.entries
        .where((e) => e.value.phase != DownloadPhase.failed)
        .map((e) => e.key)
        .toSet();
    // Progress fires per chunk — roughly 300 times for a 20 MB track. Only the
    // membership of this set matters to the screens below, so rebuild the shell
    // when a download starts or stops, never on every chunk. The rows that show
    // progress rebuild through DownloadScope instead.
    if (active.length == _downloading.length &&
        active.every(_downloading.contains)) {
      return;
    }
    setState(() {
      _downloading
        ..clear()
        ..addAll(active);
    });
  }

  /// Hands the track to the queue. The transfer used to run inline here with
  /// no progress callback and no way to stop it.
  Future<void> _download(ManifestTrack track) async {
    _downloads.enqueue(track.sha);
  }

  String _artUrlFor(String sha) => '${widget.client.baseUrl}/art/$sha';

  void _openProfile(int trackCount) {
    showProfileSheet(
      context,
      endpoint: widget.client.baseUrl,
      offline: widget.reachability.offline,
      commit: _gitCommit,
      buildNumber: _buildNumber,
      channel: _channel,
      downloadCount: widget.store.shas.length,
      trackCount: trackCount,
    );
  }

  void _openArtist(String artist, TunesManifest manifest) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArtistPage(
          artist: artist,
          manifest: manifest,
          client: widget.client,
          player: widget.player,
          store: widget.store,
          downloading: _downloading,
          onDownload: _download,
          offline: widget.reachability.offline,
          artUrlFor: _artUrlFor,
          manifestStore: widget.manifestStore,
          queueStore: widget.queueStore,
        ),
      ),
    );
  }

  void _openAlbum(ManifestRelease release, TunesManifest manifest) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AlbumPage(
          release: release,
          manifest: manifest,
          player: widget.player,
          store: widget.store,
          downloading: _downloading,
          onDownload: _download,
          offline: widget.reachability.offline,
          artUrlFor: _artUrlFor,
          manifestStore: widget.manifestStore,
          queueStore: widget.queueStore,
        ),
      ),
    );
  }

  void _openNowPlaying() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NowPlayingPage(
          player: widget.player,
          manifest: _manifest ?? const TunesManifest(tracks: [], releases: []),
          store: widget.store,
          downloading: _downloading,
          onDownload: _download,
          offline: widget.reachability.offline,
          artUrlFor: _artUrlFor,
          manifestStore: widget.manifestStore,
          queueStore: widget.queueStore,
        ),
      ),
    );
  }

  Widget _buildUnreachableState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              color: Tones.textMuted,
              size: 40,
            ),
            const SizedBox(height: Space.md),
            Text('No library yet', style: TypeScale.title),
            const SizedBox(height: Space.sm),
            Text(
              'tunesd is not answering at $_tunesdUrl.\n'
              'Start the daemon on the box, then refresh.',
              textAlign: TextAlign.center,
              style: TypeScale.body,
            ),
            const SizedBox(height: Space.sm),
            Text(
              'debug: ${_lastSyncError.runtimeType}\n$_lastSyncError',
              textAlign: TextAlign.center,
              style: TypeScale.caption,
            ),
            const SizedBox(height: Space.lg),
            FilledButton(onPressed: _reload, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Exposed here so any row can reach the queue without threading the
    // manager through six screens.
    return DownloadScope(manager: _downloads, child: _buildShell(context));
  }

  Widget _buildShell(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.reachability,
          builder: (context, _) {
            final offline = widget.reachability.offline;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    Space.lg,
                    Space.lg,
                    0,
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          final count = _manifest?.tracks.length ?? 0;
                          _openProfile(count);
                        },
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Tones.surfaceRaised,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.person_rounded,
                            size: 22,
                            color: Tones.textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.md),
                      const Expanded(
                        child: Text('tunes', style: TypeScale.wordmark),
                      ),
                      IconButton(
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh, color: Tones.textMuted),
                        tooltip: 'Refresh library',
                      ),
                    ],
                  ),
                ),
                if (offline) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(
                      Space.lg,
                      Space.md,
                      Space.lg,
                      0,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.md,
                      vertical: Space.sm,
                    ),
                    decoration: BoxDecoration(
                      color: Tones.surfaceRaised,
                      borderRadius: BorderRadius.circular(RadiusTokens.control),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.cloud_off_rounded,
                          size: 16,
                          color: Tones.textMuted,
                        ),
                        SizedBox(width: Space.sm),
                        Expanded(
                          child: Text(
                            'Offline — playing downloads only',
                            style: TypeScale.body,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                Expanded(child: _buildContent(offline)),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MiniPlayerBar(
            player: widget.player,
            onTap: _openNowPlaying,
            artUrlFor: _artUrlFor,
          ),
          NavigationBarTheme(
            data: NavigationBarThemeData(
              height: 64,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              indicatorColor: Colors.transparent,
              backgroundColor: Tones.surface,
              surfaceTintColor: Colors.transparent,
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                final selected = states.contains(WidgetState.selected);
                return TypeScale.caption.copyWith(
                  color: selected ? Tones.text : Tones.textMuted,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                );
              }),
            ),
            child: NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined, color: Tones.textMuted),
                  selectedIcon: Icon(Icons.home_rounded, color: Tones.text),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.search_rounded, color: Tones.textMuted),
                  selectedIcon: Icon(Icons.search_rounded, color: Tones.text),
                  label: 'Search',
                ),
                NavigationDestination(
                  icon: Icon(
                    Icons.library_music_outlined,
                    color: Tones.textMuted,
                  ),
                  selectedIcon: Icon(
                    Icons.library_music_rounded,
                    color: Tones.text,
                  ),
                  label: 'Library',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(bool offline) {
    if (_manifest == null) {
      if (_lastSyncError != null) {
        return _buildUnreachableState();
      }
      return const Center(
        child: CircularProgressIndicator(color: Tones.primary),
      );
    }
    if (_manifest!.tracks.isEmpty && _lastSyncError != null) {
      return _buildUnreachableState();
    }
    final manifest = _manifest!;
    final tracks = manifest.tracks;
    final content = switch (_tab) {
      1 => SearchView(
        tracks: tracks,
        releases: manifest.releases,
        client: widget.client,
        player: widget.player,
        store: widget.store,
        downloading: _downloading,
        onDownload: _download,
        offline: offline,
        artUrlFor: _artUrlFor,
        onAlbumTap: (release) => _openAlbum(release, manifest),
        onArtistTap: (artist) => _openArtist(artist, manifest),
      ),
      2 => LibraryView(
        tracks: tracks,
        releases: manifest.releases,
        artists: manifest.artists,
        filter: _libraryFilter,
        player: widget.player,
        store: widget.store,
        downloading: _downloading,
        onDownload: _download,
        offline: offline,
        artUrlFor: _artUrlFor,
        onArtistTap: (artist) => _openArtist(artist, manifest),
        onAlbumTap: (release) => _openAlbum(release, manifest),
        queueStore: widget.queueStore,
        manifestStore: widget.manifestStore,
      ),
      _ => HomeView(
        manifest: manifest,
        recents: _recents,
        missingAlbums: _missingAlbums,
        onArtistTap: (artist) => _openArtist(artist, manifest),
        onAlbumTap: (release) => _openAlbum(release, manifest),
        onPlay: (list, index) {
          // Mirror is handled by the player's onQueuePlayed hook.
          widget.player.playQueue(list, index);
        },
        artUrlFor: _artUrlFor,
      ),
    };
    return content;
  }
}
