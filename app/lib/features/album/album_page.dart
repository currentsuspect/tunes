import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/download_store.dart';
import '../../core/theme/tokens.dart';
import '../../domain/manifest.dart';
import '../artist/artist_page.dart';
import '../library/library_widgets.dart';
import '../now_playing/now_playing_page.dart';
import '../player/mini_player_bar.dart';

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
                    '${release.typeLabel} · ${release.year ?? '—'} · ${release.trackShas.length} ${release.trackShas.length == 1 ? 'track' : 'tracks'} · ${_totalMinutes(releaseTracks)} min',
                    textAlign: TextAlign.center,
                    style: TypeScale.caption,
                  ),
                  const SizedBox(height: Space.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: () => player.playQueue(releaseTracks, 0),
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: const Text('Play'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Tones.primary,
                          foregroundColor: Tones.onPrimary,
                        ),
                      ),
                      const SizedBox(width: Space.md),
                      OutlinedButton.icon(
                        onPressed: () {
                          for (final t in releaseTracks) {
                            onDownload(t);
                          }
                        },
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: const Text('Download'),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.md),
                  const SizedBox(height: Space.lg),
                  for (var i = 0; i < releaseTracks.length; i++) ...[
                    _AlbumTrackRow(
                      track: releaseTracks[i],
                      position: releaseTracks[i].trackNumber ?? i + 1,
                      player: player,
                      onPlay: () => player.playQueue(releaseTracks, i),
                      store: store,
                      downloading: downloading.contains(releaseTracks[i].sha),
                      onDownload: () => onDownload(releaseTracks[i]),
                      offline: offline,
                    ),
                    if (i < releaseTracks.length - 1) const Divider(),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: MiniPlayerBar(
        player: player,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => NowPlayingPage(
              player: player,
              manifest: manifest,
              store: store,
              downloading: downloading,
              onDownload: onDownload,
              offline: offline,
              artUrlFor: artUrlFor,
            ),
          ),
        ),
        artUrlFor: artUrlFor,
      ),
    );
  }
}

int _totalMinutes(List<ManifestTrack> tracks) {
  final ms = tracks.fold<int>(0, (sum, t) => sum + (t.durationMs ?? 0));
  return (ms / 60000).round();
}

class _AlbumTrackRow extends StatelessWidget {
  const _AlbumTrackRow({
    required this.track,
    required this.position,
    required this.player,
    required this.onPlay,
    required this.store,
    required this.downloading,
    required this.onDownload,
    required this.offline,
  });

  final ManifestTrack track;
  final int position;
  final TunePlayer player;
  final VoidCallback onPlay;
  final DownloadStore store;
  final bool downloading;
  final VoidCallback onDownload;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final active = player.current?.sha == track.sha;
        return InkWell(
          onTap: onPlay,
          borderRadius: BorderRadius.circular(RadiusTokens.control),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: Space.sm,
              horizontal: Space.xs,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  child: active && player.playing
                      ? const Icon(
                          Icons.graphic_eq_rounded,
                          size: 16,
                          color: Tones.primary,
                        )
                      : Text(
                          track.discNumber != null && track.discNumber! > 1
                              ? '${track.discNumber}.${position.toString().padLeft(2, '0')}'
                              : position.toString().padLeft(2, '0'),
                          style: TypeScale.caption.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: active ? Tones.primary : Tones.textMuted,
                          ),
                        ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(
                    track.title,
                    style: TypeScale.title.copyWith(
                      color: active ? Tones.primary : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: Space.md),
                ListenableBuilder(
                  listenable: store,
                  builder: (context, _) {
                    if (downloading) {
                      return const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Tones.primary,
                        ),
                      );
                    }
                    final dl = store.pathFor(track.sha) != null;
                    return IconButton(
                      onPressed: dl || offline ? null : onDownload,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        dl ? Icons.offline_pin_rounded : Icons.download_rounded,
                        color: dl ? Tones.primary : Tones.textMuted,
                        size: 18,
                      ),
                    );
                  },
                ),
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
      },
    );
  }
}
