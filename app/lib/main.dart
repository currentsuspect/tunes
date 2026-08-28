import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'core/audio/tune_audio_handler.dart';
import 'core/audio/tune_player.dart';
import 'core/data/download_store.dart';
import 'core/data/reachability.dart';
import 'core/net/tunes_client.dart';
import 'core/platform/diag_log.dart';
import 'core/theme/theme.dart';
import 'core/theme/tokens.dart';
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
  MediaKit.ensureInitialized();
  await DiagLog.init();
  DiagLog.log('main start');
  final support = await getApplicationSupportDirectory();
  final store = DownloadStore(support);
  await store.load();
  final client = TunesClient(_tunesdUrl, support);
  final reachability = Reachability();
  Heartbeat(ping: client.ping, reachability: reachability).start();
  final player = MediaKitTunePlayer(
    trackUriFor: (track) {
      final path = store.pathFor(track.sha);
      if (path != null && File(path).existsSync()) return path;
      return '$_tunesdUrl/track/${track.sha}';
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
  });

  final TunesClient client;
  final TunePlayer player;
  final DownloadStore store;
  final Reachability reachability;

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
  });

  final TunesClient client;
  final TunePlayer player;
  final DownloadStore store;
  final Reachability reachability;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _tab = 0;
  late Future<TunesManifest> _tracks;
  final Set<String> _downloading = {};
  final String _libraryFilter = '';
  List<ManifestTrack> _recents = [];

  bool _wasOffline = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tracks = _fetch();
    _wasOffline = widget.reachability.offline;
    widget.reachability.addListener(_onReachability);
    widget.player.addListener(_trackRecents);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.reachability.removeListener(_onReachability);
    widget.player.removeListener(_trackRecents);
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

  Future<TunesManifest> _fetch() {
    return widget.client.fetchManifest().then(
      (manifest) {
        widget.reachability.setOffline(false);
        return manifest;
      },
      onError: (Object e) {
        widget.reachability.setOffline(true);
        throw e;
      },
    );
  }

  void _reload() {
    final future = _fetch();
    future.ignore();
    setState(() {
      _tracks = future;
    });
  }

  Future<void> _download(ManifestTrack track) async {
    if (_downloading.contains(track.sha)) return;
    setState(() => _downloading.add(track.sha));
    try {
      await widget.client.downloadTrack(
        track.sha,
        widget.store.newPathFor(track.sha),
      );
      await widget.store.add(track.sha, widget.store.newPathFor(track.sha));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('download failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _downloading.remove(track.sha));
    }
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
          player: widget.player,
          store: widget.store,
          downloading: _downloading,
          onDownload: _download,
          offline: widget.reachability.offline,
          artUrlFor: _artUrlFor,
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
        ),
      ),
    );
  }

  void _openNowPlaying() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NowPlayingPage(
          player: widget.player,
          manifest:
              _lastTracks ?? const TunesManifest(tracks: [], releases: []),
          store: widget.store,
          downloading: _downloading,
          onDownload: _download,
          offline: widget.reachability.offline,
          artUrlFor: _artUrlFor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                          final tracks = _tracksSnapshot;
                          _openProfile(tracks.length);
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
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.search_rounded),
                label: 'Search',
              ),
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music_rounded),
                label: 'Library',
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<ManifestTrack> get _tracksSnapshot => _lastTracks?.tracks ?? const [];

  TunesManifest? _lastTracks;

  Widget _buildContent(bool offline) {
    return FutureBuilder<TunesManifest>(
      future: _tracks,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: Tones.primary),
          );
        }
        if (snapshot.hasError) {
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
                  const SizedBox(height: Space.lg),
                  FilledButton(onPressed: _reload, child: const Text('Retry')),
                ],
              ),
            ),
          );
        }
        final manifest =
            snapshot.data ?? const TunesManifest(tracks: [], releases: []);
        _lastTracks = manifest;
        final tracks = manifest.tracks;
        final content = switch (_tab) {
          1 => SearchView(
            tracks: tracks,
            player: widget.player,
            store: widget.store,
            downloading: _downloading,
            onDownload: _download,
            offline: offline,
            artUrlFor: _artUrlFor,
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
          ),
          _ => HomeView(
            manifest: manifest,
            recents: _recents,
            onArtistTap: (artist) => _openArtist(artist, manifest),
            onAlbumTap: (release) => _openAlbum(release, manifest),
            onPlay: (list, index) {
              widget.player.playQueue(list, index);
            },
            artUrlFor: _artUrlFor,
          ),
        };
        return content;
      },
    );
  }
}
