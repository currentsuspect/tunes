import 'package:flutter/material.dart';

import 'core/net/tunes_client.dart';
import 'core/theme/theme.dart';
import 'core/theme/tokens.dart';
import 'domain/manifest.dart';

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

void main() {
  runApp(const TunesApp());
}

class TunesApp extends StatelessWidget {
  const TunesApp({super.key, this.client});

  final TunesClient? client;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return MaterialApp(
      title: 'tunes',
      debugShowCheckedModeBanner: false,
      theme: buildTunesTheme(mq),
      home: LibraryHome(client: client ?? TunesClient(_tunesdUrl)),
    );
  }
}

class LibraryHome extends StatefulWidget {
  const LibraryHome({super.key, required this.client});

  final TunesClient client;

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
                  ? _TracksView(tracks: _tracks, onRetry: _reload)
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
      bottomNavigationBar: NavigationBar(
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
    );
  }
}

class _TracksView extends StatelessWidget {
  const _TracksView({required this.tracks, required this.onRetry});

  final Future<List<ManifestTrack>> tracks;
  final VoidCallback onRetry;

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
            return _TrackRow(track: t);
          },
        );
      },
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.track});

  final ManifestTrack track;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
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
