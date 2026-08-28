import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/download_store.dart';
import '../../core/theme/tokens.dart';
import '../../domain/manifest.dart';
import '../artist/artist_page.dart';
import '../library/library_widgets.dart';

class AlbumPage extends StatelessWidget {
  const AlbumPage({
    super.key,
    required this.release,
    required this.manifest,
    required this.player,
    required this.store,
    required this.downloading,
    required this.onDownload,
    required this.offline,
    required this.artUrlFor,
  });

  final ManifestRelease release;
  final TunesManifest manifest;
  final TunePlayer player;
  final DownloadStore store;
  final Set<String> downloading;
  final void Function(ManifestTrack) onDownload;
  final bool offline;
  final String Function(String sha) artUrlFor;

  @override
  Widget build(BuildContext context) {
    final trackShas = release.trackShas;
    final releaseTracks = trackShas
        .map(
          (sha) => manifest.tracks.firstWhere(
            (t) => t.sha == sha,
            orElse: () => manifest.tracks.firstWhere(
              (t) => t.sha == sha,
              orElse: () => throw StateError('track $sha missing'),
            ),
          ),
        )
        .toList();

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
                    child: Text('Album', style: TypeScale.caption),
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
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(RadiusTokens.card),
                      child: SizedBox(
                        width: 220,
                        height: 220,
                        child: release.artSha != null
                            ? Image.network(
                                artUrlFor(release.artSha!),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    const ArtPlaceholder(size: 220),
                              )
                            : const ArtPlaceholder(size: 220),
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.lg),
                  Text(
                    release.title,
                    textAlign: TextAlign.center,
                    style: TypeScale.wordmark,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: Space.xs),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ArtistPage(
                          artist: release.artist,
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
                    child: Text(
                      release.artist,
                      textAlign: TextAlign.center,
                      style: TypeScale.title.copyWith(color: Tones.primary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    '${release.typeLabel} · ${release.year ?? '—'} · ${release.trackShas.length} ${release.trackShas.length == 1 ? 'track' : 'tracks'}',
                    textAlign: TextAlign.center,
                    style: TypeScale.caption,
                  ),
                  const SizedBox(height: Space.lg),
                  FilledButton.icon(
                    onPressed: () => player.playQueue(releaseTracks, 0),
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: const Text('Play'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Tones.primary,
                      foregroundColor: Tones.onPrimary,
                    ),
                  ),
                  const SizedBox(height: Space.lg),
                  for (var i = 0; i < releaseTracks.length; i++) ...[
                    TrackRow(
                      track: releaseTracks[i],
                      onTap: () => player.playQueue(releaseTracks, i),
                      store: store,
                      downloading: downloading.contains(releaseTracks[i].sha),
                      onDownload: () => onDownload(releaseTracks[i]),
                      offline: offline,
                      artUrlFor: artUrlFor,
                    ),
                    if (i < releaseTracks.length - 1) const Divider(),
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
