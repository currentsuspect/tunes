import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'core/audio/tune_audio_handler.dart';
import 'core/audio/tune_player.dart';
import 'core/net/tunes_client.dart';
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
  final client = TunesClient(_tunesdUrl);
  final player = MediaKitTunePlayer(
    trackUrlFor: (sha) => '$_tunesdUrl/track/$sha',
  );
  await AudioService.init(
    builder: () => TuneAudioHandler(player),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.currentsuspect.tunes.channel.audio',
      androidNotificationChannelName: 'Tunes playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
  runApp(TunesApp(client: client, player: player));
}

class TunesApp extends StatelessWidget {
  const TunesApp({super.key, required this.client, required this.player});

  final TunesClient client;
  final TunePlayer player;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return MaterialApp(
      title: 'tunes',
      debugShowCheckedModeBanner: false,
      theme: buildTunesTheme(mq),
      home: LibraryHome(client: client, player: player),
    );
  }
}

class LibraryHome extends StatefulWidget {
  const LibraryHome({super.key, required this.client, required this.player});

  final TunesClient client;
  final TunePlayer player;

  @override
  State<LibraryHome> createState() => _LibraryHomeState();
}

class _LibraryHomeState extends State<LibraryHome> {
  int _tab = 0;
  late Future<List<ManifestTrack>> _tracks;

  static const _tabs = ['Tracks', 'Albums', 'Artists', 'Channels'];

  @override
  void initState() {
    super.initState();
    _tracks = widget.client.fetchManifest();
  }

  void _reload() {
    setState(() {
      _tracks = widget.client.fetchManifest();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
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
                        Text('codename — library', style: TypeScale.caption),
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
            Expanded(
              child: _tab == 0
                  ? _TracksView(
                      tracks: _tracks,
                      onRetry: _reload,
                      player: widget.player,
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
  });

  final Future<List<ManifestTrack>> tracks;
  final VoidCallback onRetry;
  final TunePlayer player;

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
              onTap: () => player.playQueue(tracks, i),
            );
          },
        );
      },
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.track, required this.onTap});

  final ManifestTrack track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
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
          ],
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
