import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/download_store.dart';
import '../../core/data/manifest_store.dart';
import '../../core/data/queue_store.dart';
import '../../core/nav/nav_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/artwork.dart';
import '../../core/ui/shared_sleeve.dart';
import '../../core/ui/generated_artwork.dart';
import '../../domain/manifest.dart';
import '../artist/artist_page.dart';
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
    required this.manifestStore,
    this.queueStore,
  });

  final ManifestRelease release;
  final TunesManifest manifest;
  final TunePlayer player;
  final DownloadStore store;
  final Set<String> downloading;
  final void Function(ManifestTrack) onDownload;
  final bool offline;
  final String Function(String sha) artUrlFor;
  final ManifestStore manifestStore;
  final QueueStore? queueStore;

  @override
  Widget build(BuildContext context) {
    final bySha = {for (final t in manifest.tracks) t.sha: t};
    final rows = release.tracks.isEmpty
        ? [
            for (final sha in release.trackShas)
              if (bySha[sha] != null)
                (track: bySha[sha]!, number: null, disc: null),
          ]
        : [
            for (final rt in release.tracks)
              if (bySha[rt.sha] != null)
                (
                  track: bySha[rt.sha]!,
                  number: rt.trackNumber,
                  disc: rt.discNumber,
                ),
          ];
    rows.sort((a, b) {
      final da = a.disc ?? 1;
      final db = b.disc ?? 1;
      if (da != db) return da - db;
      final na = a.number ?? 999;
      final nb = b.number ?? 999;
      if (na != nb) return na - nb;
      return a.track.sha.compareTo(b.track.sha);
    });
    final releaseTracks = [for (final r in rows) r.track];

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
                    onPressed: () => NavScope.of(context).back(),
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
                    child: SharedSleeve(
                      tag: 'album-${release.id}',
                      child: Artwork(
                        url: release.artSha == null
                            ? null
                            : artUrlFor(release.artSha!),
                        artSha: release.artSha,
                        size: 220,
                        shared: true,
                        fallback: GeneratedArtwork(
                          title: release.title,
                          artist: release.artist,
                          size: 220,
                          borderRadius: RadiusTokens.card,
                        ),
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
                    // One panel at a time: an album reached from an artist (or
                    // vice versa) replaces it, and the same artist twice is a
                    // no-op rather than a twin route.
                    onTap: () => NavScope.of(context).openPanel(
                      TunesPanels.artist(release.artist),
                      () => ArtistPage(
                        artist: release.artist,
                        manifest: manifest,
                        player: player,
                        store: store,
                        downloading: downloading,
                        onDownload: onDownload,
                        offline: offline,
                        artUrlFor: artUrlFor,
                        manifestStore: manifestStore,
                        queueStore: queueStore,
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
                    '${release.typeLabel} · ${release.year ?? '—'} · '
                    '${_trackCountLabel(release)} · ${_totalMinutes(releaseTracks)} min',
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
                  for (var i = 0; i < rows.length; i++) ...[
                    _AlbumTrackRow(
                      track: rows[i].track,
                      position:
                          rows[i].number ??
                          releaseTracks[i].trackNumber ??
                          i + 1,
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
        onTap: () => NavScope.of(context).openPanel(
          TunesPanels.nowPlaying,
          () => NowPlayingPage(
            player: player,
            manifest: manifest,
            store: store,
            downloading: downloading,
            onDownload: onDownload,
            offline: offline,
            artUrlFor: artUrlFor,
            manifestStore: manifestStore,
            queueStore: queueStore,
          ),
        ),
        artUrlFor: artUrlFor,
      ),
    );
  }
}

String _trackCountLabel(ManifestRelease release) {
  final owned = release.trackShas.length;
  final total = release.totalTracks;
  final plain = '$owned ${owned == 1 ? 'track' : 'tracks'}';
  if (total == null) return plain;
  // Holding more of a release than it is supposed to contain means the
  // enriched total describes a different edition than the files do -- one
  // library release has 35 tracks against a total of 22. Printing "35/22"
  // asserts a completeness we cannot vouch for, so fall back to counting
  // what is actually here.
  if (owned > total) return plain;
  if (owned == total) return '$owned/$total tracks · complete';
  return '$owned/$total tracks · ${total - owned} missing';
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
