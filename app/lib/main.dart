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
import 'core/platform/notifications.dart';
import 'core/theme/theme.dart';
import 'core/theme/tokens.dart';
import 'domain/manifest.dart';
import 'features/now_playing/now_playing_page.dart';

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
  DiagLog.log('init begin');
  try {
    await AudioService.init(
      builder: () => TuneAudioHandler(player),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.currentsuspect.tunes.channel.audio',
        androidNotificationChannelName: 'Tunes playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
    AudioService.asyncError.listen((e) => DiagLog.log('async error: $e'));
    DiagLog.log('audio_service init ok');
  } catch (e) {
    DiagLog.log('AudioService.init failed: $e');
    debugPrint('AudioService.init failed (notification disabled): $e');
  }
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
      home: LibraryHome(
        client: client,
        player: player,
        store: store,
        reachability: reachability,
      ),
    );
  }
}

class LibraryHome extends StatefulWidget {
  const LibraryHome({
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
  State<LibraryHome> createState() => _LibraryHomeState();
}

class _LibraryHomeState extends State<LibraryHome> {
  int _tab = 0;
  late Future<List<ManifestTrack>> _tracks;
  final Set<String> _downloading = {};

  static const _tabs = ['Tracks', 'Albums', 'Artists', 'Channels'];

  @override
  void initState() {
    super.initState();
    _tracks = _fetch();
  }

  Future<List<ManifestTrack>> _fetch() {
    return widget.client.fetchManifest().then(
      (tracks) {
        widget.reachability.setOffline(false);
        return tracks;
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('tunes', style: TypeScale.wordmark),
                            const SizedBox(height: Space.xs),
                            Text(
                              'codename — library',
                              style: TypeScale.caption,
                            ),
                          ],
                        ),
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
                Expanded(
                  child: _tab == 0
                      ? _TracksView(
                          tracks: _tracks,
                          onRetry: _reload,
                          player: widget.player,
                          store: widget.store,
                          downloading: _downloading,
                          onDownload: _download,
                          offline: offline,
                        )
                      : _NotYetView(label: _tabs[_tab]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    0,
                    Space.lg,
                    Space.sm,
                  ),
                  child: Text(
                    '$_channel · ${_gitCommit.length > 7 ? _gitCommit.substring(0, 7) : _gitCommit} · $_buildNumber',
                    style: TypeScale.caption,
                  ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MiniPlayerBar(player: widget.player),
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                label: 'Tracks',
              ),
              NavigationDestination(
                icon: Icon(Icons.album_outlined),
                label: 'Albums',
              ),
              NavigationDestination(
                icon: Icon(Icons.people_outline),
                label: 'Artists',
              ),
              NavigationDestination(
                icon: Icon(Icons.send_outlined),
                label: 'Channels',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TracksView extends StatelessWidget {
  const _TracksView({
    required this.tracks,
    required this.onRetry,
    required this.player,
    required this.store,
    required this.downloading,
    required this.onDownload,
    required this.offline,
  });

  final Future<List<ManifestTrack>> tracks;
  final VoidCallback onRetry;
  final TunePlayer player;
  final DownloadStore store;
  final Set<String> downloading;
  final void Function(ManifestTrack) onDownload;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ManifestTrack>>(
      future: tracks,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: Tones.primary),
          );
        }
        if (snapshot.hasError) {
          return _Message(
            icon: Icons.cloud_off_outlined,
            title: 'No library yet',
            body:
                'tunesd is not answering at $_tunesdUrl.\n'
                'Start the daemon on the box, then refresh.',
            action: 'Retry',
            onAction: onRetry,
          );
        }
        final tracks = snapshot.data ?? const <ManifestTrack>[];
        if (tracks.isEmpty) {
          return const _Message(
            icon: Icons.music_note_outlined,
            title: 'No Tracks yet',
            body:
                'Channels are configured, nothing has landed in the '
                'library yet. New content appears here as tunesd fetches it.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: Space.md,
          ),
          itemCount: tracks.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, i) {
            final t = tracks[i];
            return _TrackRow(
              track: t,
              onTap: () {
                unawaited(requestNotificationPermissionIfNeeded());
                player.playQueue(tracks, i);
              },
              store: store,
              downloading: downloading.contains(t.sha),
              onDownload: () => onDownload(t),
              offline: offline,
            );
          },
        );
      },
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.track,
    required this.onTap,
    required this.store,
    required this.downloading,
    required this.onDownload,
    required this.offline,
  });

  final ManifestTrack track;
  final VoidCallback onTap;
  final DownloadStore store;
  final bool downloading;
  final VoidCallback onDownload;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final local = store.pathFor(track.sha) != null;
    final dimmed = offline && !local;
    return Opacity(
      opacity: dimmed ? 0.45 : 1,
      child: IgnorePointer(
        ignoring: dimmed,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(RadiusTokens.control),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: Space.sm,
              horizontal: Space.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        style: TypeScale.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${track.artist} — ${track.album}',
                        style: TypeScale.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.md),
                _QualityBadge(label: track.qualityLabel),
                const SizedBox(width: Space.md),
                Text(
                  track.durationLabel,
                  style: TypeScale.caption.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                ListenableBuilder(
                  listenable: store,
                  builder: (context, _) {
                    if (downloading) {
                      return const Padding(
                        padding: EdgeInsets.all(Space.sm),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Tones.primary,
                          ),
                        ),
                      );
                    }
                    final local = store.pathFor(track.sha) != null;
                    return IconButton(
                      onPressed: local || offline ? null : onDownload,
                      icon: Icon(
                        local
                            ? Icons.offline_pin_rounded
                            : Icons.download_rounded,
                        color: local ? Tones.primary : Tones.textMuted,
                        size: 20,
                      ),
                      tooltip: local
                          ? 'Downloaded — offline ready'
                          : 'Download to device',
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniPlayerBar extends StatelessWidget {
  const _MiniPlayerBar({required this.player});

  final TunePlayer player;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final current = player.current;
        if (current == null) return const SizedBox.shrink();
        final max = player.duration.inMilliseconds.toDouble();
        final value = player.position.inMilliseconds
            .clamp(0, player.duration.inMilliseconds)
            .toDouble();
        return InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => NowPlayingPage(player: player),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(
              Space.md,
              Space.sm,
              Space.md,
              Space.sm,
            ),
            decoration: const BoxDecoration(
              color: Tones.surface,
              border: Border(top: BorderSide(color: Tones.hairline)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        current.title,
                        style: TypeScale.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        player.playing
                            ? 'playing · ${current.durationLabel}'
                            : 'paused · ${current.durationLabel}',
                        style: TypeScale.caption,
                      ),
                    ],
                  ),
                ),
                if (max > 0)
                  SizedBox(
                    width: 120,
                    child: Slider(
                      value: value,
                      max: max,
                      onChanged: (v) =>
                          player.seek(Duration(milliseconds: v.round())),
                    ),
                  ),
                IconButton(
                  onPressed: player.stop,
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: Tones.textMuted,
                  ),
                  tooltip: 'Stop playback',
                ),
                IconButton(
                  onPressed: player.toggle,
                  icon: Icon(
                    player.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 30,
                    color: Tones.primary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QualityBadge extends StatelessWidget {
  const _QualityBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 3),
      decoration: BoxDecoration(
        color: Tones.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TypeScale.caption),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Tones.surfaceRaised,
                borderRadius: BorderRadius.circular(RadiusTokens.control),
              ),
              child: Icon(icon, size: 32, color: Tones.textMuted),
            ),
            const SizedBox(height: Space.lg),
            Text(title, style: TypeScale.title),
            const SizedBox(height: Space.sm),
            Text(body, textAlign: TextAlign.center, style: TypeScale.body),
            if (action != null) ...[
              const SizedBox(height: Space.lg),
              FilledButton(onPressed: onAction, child: Text(action!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _NotYetView extends StatelessWidget {
  const _NotYetView({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return _Message(
      icon: Icons.construction_outlined,
      title: '$label coming in M4',
      body: 'This surface lands with deep identity and collections.',
    );
  }
}
