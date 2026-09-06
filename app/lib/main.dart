import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'core/audio/audio_focus.dart';
import 'core/audio/tune_audio_handler.dart';
import 'core/audio/tune_player.dart';
import 'core/data/database.dart';
import 'core/data/download_manager.dart';
import 'core/data/download_store.dart';
import 'core/data/likes_store.dart';
import 'core/data/manifest_store.dart';
import 'core/data/play_history.dart';
import 'core/data/queue_store.dart';
import 'core/data/settings_store.dart';
import 'core/data/reachability.dart';
import 'core/net/tunes_client.dart';
import 'core/platform/diag_log.dart';
import 'core/theme/theme.dart';
import 'core/theme/tokens.dart';
import 'core/ui/profile_avatar.dart';
import 'domain/collection_gaps.dart';
import 'domain/discography.dart';
import 'domain/manifest.dart';
import 'features/album/album_page.dart';
import 'features/artist/artist_page.dart';
import 'features/discover/discover_view.dart';
import 'features/home/home_skeleton.dart';
import 'features/home/home_view.dart';
import 'features/library/library_view.dart';
import 'features/now_playing/now_playing_page.dart';
import 'features/player/mini_player_bar.dart';
import 'features/profile/settings_page.dart';
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
  // Loaded before the first frame so every screen can read a setting during
  // build. A setting that has to be awaited mid-build is one that flickers.
  final settings = SettingsStore(db);
  await settings.load();
  // Loaded before the first frame for the same reason as settings: a heart
  // that has to await its own state flickers on every row of every list.
  final likes = LikesStore(db);
  await likes.load();
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
        builder: () => TuneAudioHandler(
          player,
          artBase: _tunesdUrl,
          stopOnTaskRemoved: () => settings.stopOnClose,
        ),
        config: const AudioServiceConfig(
          androidNotificationChannelId:
              'com.currentsuspect.tunes.channel.audio',
          androidNotificationChannelName: 'Tunes playback',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
          // The notification carried all four transport controls and a
          // MediaStyle template, and the device drew none of them. Both of
          // these were at their defaults, and audio_service documents that
          // some devices will not render the controls or the seek bar unless
          // the small icon is a monochrome white silhouette and the colour is
          // opaque -- the default icon is the full-colour launcher mipmap and
          // the default colour is fully transparent.
          androidNotificationIcon: 'drawable/ic_stat_music',
          notificationColor: Tones.primary,
        ),
      );
      AudioService.asyncError.listen((e) => DiagLog.log('async error: $e'));
      DiagLog.log('audio_service init ok (lazy)');
    } catch (e) {
      audioServiceReady = false;
      DiagLog.log('AudioService.init failed (lazy): $e');
    }
  }

  // The player is built lazily on first play, so the stored choice has to be
  // handed to it up front rather than applied to an instance that does not
  // exist yet.
  unawaited(player.setGapless(settings.gapless));

  // Watches the player from here on, so a listen is recorded whether it was
  // started from the library, a notification, or a headset button.
  final history = PlayHistory(db, player);

  player.onFirstPlay = ensureAudioService;
  // Not awaited: it only has to be in place before the first track, and the
  // library should not wait on the audio session to draw.
  unawaited(AudioFocus(player).attach());

  DiagLog.log('runApp');
  runApp(
    TunesApp(
      client: client,
      player: player,
      store: store,
      reachability: reachability,
      manifestStore: manifestStore,
      queueStore: queueStore,
      settings: settings,
      history: history,
      likes: likes,
    ),
  );
}

class TunesApp extends StatefulWidget {
  const TunesApp({
    super.key,
    required this.client,
    required this.player,
    required this.store,
    required this.reachability,
    required this.manifestStore,
    required this.queueStore,
    required this.settings,
    required this.history,
    required this.likes,
  });

  final TunesClient client;
  final TunePlayer player;
  final DownloadStore store;
  final Reachability reachability;
  final ManifestStore manifestStore;
  final QueueStore queueStore;
  final SettingsStore settings;
  final PlayHistory history;
  final LikesStore likes;

  @override
  State<TunesApp> createState() => _TunesAppState();
}

class _TunesAppState extends State<TunesApp> {
  // Owned here, above MaterialApp, because DownloadScope has to sit above the
  // Navigator. It used to be created inside AppShell, which is MaterialApp's
  // `home` -- so every pushed route (album, artist) was a sibling of the
  // scope rather than a descendant, DownloadScope.maybeOf returned null
  // there, and tapping download on an album page showed nothing at all until
  // the route was rebuilt by leaving and coming back.
  late final DownloadManager _downloads;

  @override
  void initState() {
    super.initState();
    _downloads = DownloadManager(client: widget.client, store: widget.store);
  }

  @override
  void dispose() {
    _downloads.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return SettingsScope(
      settings: widget.settings,
      child: LikesScope(
        likes: widget.likes,
        child: DownloadScope(
          manager: _downloads,
          child: MaterialApp(
            title: 'tunes',
            debugShowCheckedModeBanner: false,
            theme: buildTunesTheme(mq),
            home: AppShell(
              client: widget.client,
              player: widget.player,
              store: widget.store,
              reachability: widget.reachability,
              manifestStore: widget.manifestStore,
              queueStore: widget.queueStore,
              settings: widget.settings,
              history: widget.history,
              downloads: _downloads,
            ),
          ),
        ),
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
    required this.settings,
    required this.history,
    required this.downloads,
  });

  final TunesClient client;
  final TunePlayer player;
  final DownloadStore store;
  final Reachability reachability;
  final ManifestStore manifestStore;
  final QueueStore queueStore;
  final SettingsStore settings;
  final PlayHistory history;

  /// Owned by [TunesApp], which publishes it above the Navigator so pushed
  /// routes can reach it too.
  final DownloadManager downloads;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _tab = 0;
  TunesManifest? _manifest;
  Map<String, int> _playsByArtist = const {};
  List<ManifestTrack> _onRepeat = const [];
  List<ManifestTrack> _listenAgain = const [];
  bool _syncing = false;
  Object? _lastSyncError;
  DateTime? _lastSyncAt;
  final Set<String> _downloading = {};
  DownloadManager get _downloads => widget.downloads;
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
    // The screens below still take a Set<String> of in-flight shas; keep it in
    // step with the manager rather than re-plumbing six widgets.
    _downloads.addListener(_onDownloadsChanged);
    _wasOffline = widget.reachability.offline;
    widget.reachability.addListener(_onReachability);
    widget.player.addListener(_trackRecents);
    // Recents used to live only in memory, so closing the app forgot what you
    // had been listening to. They come from the recorded history now.
    widget.history.addListener(_onHistoryChanged);
    _onHistoryChanged();
    // Hydrate from the store before kicking off a sync, so the sync's
    // setState doesn't race against a stale in-memory snapshot.
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.reachability.removeListener(_onReachability);
    widget.player.removeListener(_trackRecents);
    widget.history.removeListener(_onHistoryChanged);
    // Only the listener: the manager itself belongs to TunesApp, which
    // outlives this shell.
    _downloads.removeListener(_onDownloadsChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !widget.reachability.offline) {
      _reload();
    }
    if (state == AppLifecycleState.paused) {
      // Settle the listen in progress. Leaving mid-track is ordinary, and an
      // unsettled listen is one that never happened.
      widget.history.flush();
    }
  }

  /// Newest first, and only tracks still in the library -- history outlives
  /// the files it refers to, and a recent play of something since removed is
  /// not something to put on the home screen.
  Future<void> _loadRecents() async {
    final shas = await widget.history.recentShas();
    if (!mounted) return;
    final manifest = _manifest;
    if (manifest == null) return;
    final bySha = {for (final t in manifest.tracks) t.sha: t};
    final tracks = [
      for (final sha in shas)
        if (bySha[sha] case final ManifestTrack t) t,
    ];
    if (tracks.isEmpty) return;
    setState(() => _recents = tracks);
  }

  /// A listen finished. Both the recents rail and the discover ranking read
  /// from history, and they are refreshed together so the two views can never
  /// disagree about what was played.
  Future<void> _onHistoryChanged() async {
    await _loadRecents();
    await _loadPlays();
    await _loadDerivedRails();
  }

  /// The sections the app assembles from listening rather than from choice.
  ///
  /// Resolved against the current manifest and dropped if the track has left
  /// the library, so a rail never offers something that cannot be played.
  Future<void> _loadDerivedRails() async {
    final top = await widget.history.topShas();
    final again = await widget.history.listenAgainShas();
    if (!mounted) return;
    final manifest = _manifest;
    if (manifest == null) return;
    final bySha = {for (final t in manifest.tracks) t.sha: t};
    List<ManifestTrack> resolve(List<String> shas) => [
      for (final sha in shas)
        if (bySha[sha] case final ManifestTrack t) t,
    ];
    setState(() {
      _onRepeat = resolve(top);
      _listenAgain = resolve(again);
    });
  }

  /// Folds the play counters into a per-act tally for the discover ranking.
  ///
  /// Recomputed on the same signal as recents rather than on a timer: the
  /// only thing that changes it is a listen finishing, which is exactly when
  /// the history notifies.
  Future<void> _loadPlays() async {
    final counts = await widget.history.playCounts();
    if (!mounted) return;
    final manifest = _manifest;
    if (manifest == null) return;
    final plays = playsByArtist(counts, manifest.tracks);
    setState(() => _playsByArtist = plays);
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
          // The first load happens before the manifest exists, so recents
          // cannot resolve their tracks until now.
          unawaited(_onHistoryChanged());
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
      // The daemon caps at 200. The home rail only shows a handful, but the
      // discover screen counts what it was given and says so out loud -- a
      // default of forty made it report "40 releases by 4 artists" for a
      // library with fifty-four by six.
      final albums = await widget.client.missing(limit: 200);
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

  /// Pull to refresh. Awaits the sync so the indicator stays until the work
  /// is actually done.
  ///
  /// A failure keeps whatever is on screen and says so quietly. Blanking a
  /// feed that was correct a moment ago is a worse outcome than a stale one,
  /// and a refresh that succeeded needs no announcement at all.
  Future<void> _refresh() async {
    await _sync();
    if (!mounted) return;
    if (_lastSyncError != null && _manifest != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't refresh"),
          duration: Duration(seconds: 2),
        ),
      );
    }
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

  /// The header avatar now goes straight to settings. The old sheet was a
  /// read-only diagnostics panel, and its contents live under Library there.
  void _openProfile(int trackCount) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(
          settings: widget.settings,
          player: widget.player,
          endpoint: widget.client.baseUrl,
          offline: widget.reachability.offline,
          commit: _gitCommit,
          buildNumber: _buildNumber,
          channel: _channel,
          trackCount: trackCount,
          downloadCount: widget.store.shas.length,
        ),
      ),
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
    // The scope lives in TunesApp, above the Navigator. Re-publishing it here
    // would cover this shell only, which is the bug that was.
    return _buildShell(context);
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
                        // Listens to settings directly: choosing a picture in
                        // the screen this opens should change the thing you
                        // came back to, without a restart.
                        child: ListenableBuilder(
                          listenable: widget.settings,
                          builder: (context, _) => ProfileAvatar(
                            name: widget.settings.displayName,
                            path: widget.settings.avatarPath,
                            size: 38,
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.md),
                      const Expanded(
                        child: Text('tunes', style: TypeScale.wordmark),
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
                  icon: Icon(
                    Icons.travel_explore_outlined,
                    color: Tones.textMuted,
                  ),
                  selectedIcon: Icon(
                    Icons.travel_explore_rounded,
                    color: Tones.text,
                  ),
                  label: 'Discover',
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
      // Geometry, not a spinner: the skeleton is built to the same shape as
      // the feed, so the library replaces it without anything moving.
      return const HomeSkeleton();
    }
    if (_manifest!.tracks.isEmpty && _lastSyncError != null) {
      return _buildUnreachableState();
    }
    final manifest = _manifest!;
    final tracks = manifest.tracks;
    final content = switch (_tab) {
      1 => DiscoverView(
        gaps: collectionGaps(missing: _missingAlbums, plays: _playsByArtist),
        offline: offline,
        artUrlFor: _artUrlFor,
        onArtistTap: (artist) => _openArtist(artist, manifest),
        hasHistory: _playsByArtist.isNotEmpty,
      ),
      2 => SearchView(
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
      3 => LibraryView(
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
        onRefresh: _refresh,
        onRepeat: _onRepeat,
        listenAgain: _listenAgain,
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
