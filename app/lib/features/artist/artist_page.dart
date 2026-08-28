import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/download_store.dart';
import '../../core/theme/tokens.dart';
import '../../domain/manifest.dart';
import '../album/album_page.dart';
import '../library/library_widgets.dart';

class ArtistPage extends StatelessWidget {
  const ArtistPage({
    super.key,
    required this.artist,
    required this.manifest,
    required this.player,
    required this.store,
    required this.downloading,
    required this.onDownload,
    required this.offline,
    required this.artUrlFor,
  });

  final String artist;
  final TunesManifest manifest;
  final TunePlayer player;
  final DownloadStore store;
  final Set<String> downloading;
  final void Function(ManifestTrack) onDownload;
  final bool offline;
  final String Function(String sha) artUrlFor;

  @override
  Widget build(BuildContext context) {
    final tracks = manifest.tracks.where((t) => t.artist == artist).toList();
    final releases = manifest.releasesFor(artist);
    final portrait = tracks.firstWhere(
      (t) => t.artSha != null,
      orElse: () => tracks.first,
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.xs,
                Space.sm,
                Space.sm,
                0,
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Tones.textMuted,
                    ),
                  ),
                  const Expanded(
                    child: Text('Artist', style: TypeScale.caption),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  Space.lg,
                  Space.sm,
                  Space.lg,
                  Space.lg,
                ),
                children: [
                  Center(
                    child: ClipOval(
                      child: SizedBox(
                        width: 140,
                        height: 140,
                        child: portrait.artSha != null
                            ? Image.network(
                                artUrlFor(portrait.artSha!),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    const ArtPlaceholder(size: 140),
                              )
                            : const ArtPlaceholder(size: 140),
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.lg),
                  Text(
                    artist,
                    textAlign: TextAlign.center,
                    style: TypeScale.wordmark,
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    '${tracks.length} ${tracks.length == 1 ? 'track' : 'tracks'} · ${releases.length} ${releases.length == 1 ? 'release' : 'releases'}',
                    textAlign: TextAlign.center,
                    style: TypeScale.body,
                  ),
                  const SizedBox(height: Space.lg),
                  FilledButton.icon(
                    onPressed: () => player.playQueue(tracks, 0),
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: const Text('Play all'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Tones.primary,
                      foregroundColor: Tones.onPrimary,
                    ),
                  ),
                  const SizedBox(height: Space.lg),
                  for (final r in releases) ...[
                    _ReleaseCard(
                      release: r,
                      manifest: manifest,
                      artUrlFor: artUrlFor,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => AlbumPage(
                            release: r,
                            manifest: manifest,
                            player: player,
                            store: store,
                            downloading: downloading,
                            onDownload: onDownload,
                            offline: offline,
                            artUrlFor: artUrlFor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: Space.md),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({
    required this.release,
    required this.manifest,
    required this.artUrlFor,
    required this.onTap,
  });

  final ManifestRelease release;
  final TunesManifest manifest;
  final String Function(String sha) artUrlFor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(RadiusTokens.card),
      child: Row(
        children: [
          ArtThumb(sha: release.artSha, artUrlFor: artUrlFor, size: 56),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  release.title,
                  style: TypeScale.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${release.typeLabel} · ${release.year ?? '—'} · ${release.trackShas.length} ${release.trackShas.length == 1 ? 'track' : 'tracks'}',
                  style: TypeScale.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Tones.textMuted),
        ],
      ),
    );
  }
}
