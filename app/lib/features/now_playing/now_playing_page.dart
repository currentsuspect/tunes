import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/download_store.dart';
import '../../core/data/manifest_store.dart';
import '../../core/data/queue_store.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/generated_artwork.dart';
import '../../domain/manifest.dart';
import '../artist/artist_page.dart';
import '../album/album_page.dart';
import '../lyrics/lyrics_sheet.dart';
import '../queue/queue_sheet.dart';

class NowPlayingPage extends StatelessWidget {
  const NowPlayingPage({
    super.key,
    required this.player,
    required this.manifest,
    required this.store,
    required this.downloading,
    required this.onDownload,
    required this.offline,
    required this.artUrlFor,
    required this.manifestStore,
    this.queueStore,
  });

  final TunePlayer player;
  final TunesManifest manifest;
  final DownloadStore store;
  final Set<String> downloading;
  final void Function(ManifestTrack) onDownload;
  final bool offline;
  final String Function(String sha) artUrlFor;
  final ManifestStore manifestStore;
  final QueueStore? queueStore;

  String _label(Duration d) {
    final s = d.inSeconds;
    final m = (s ~/ 60).toString().padLeft(2, '0');
    return '$m:${(s % 60).toString().padLeft(2, '0')}';
  }

  void _openQueue(BuildContext context) {
    final qs = queueStore;
    if (qs == null) return;
    QueueSheet.show(context, queueStore: qs, player: player);
  }

  void _openAlbum(BuildContext context, ManifestTrack track) {
    ManifestRelease? release;
    if (track.releaseId != null) {
      for (final r in manifest.releases) {
        if (r.id == track.releaseId) {
          release = r;
          break;
        }
      }
    }
    if (release == null) {
      for (final r in manifest.releases) {
        if (r.artist == track.artist && r.title == track.album) {
          release = r;
          break;
        }
      }
    }
    final resolved = release;
    if (resolved == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AlbumPage(
          release: resolved,
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
    );
  }

  void _showTrackInfo(BuildContext context, ManifestTrack track) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Tones.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(RadiusTokens.card),
        ),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(track.title, style: TypeScale.title),
                const SizedBox(height: Space.md),
                _InfoRow(label: 'Artist', value: track.artist),
                _InfoRow(label: 'Album', value: track.album),
                _InfoRow(label: 'Quality', value: track.qualityLabel),
                _InfoRow(
                  label: 'Sample rate',
                  value: track.sampleRate != null
                      ? '${track.sampleRate} Hz'
                      : '—',
                ),
                _InfoRow(
                  label: 'Channels',
                  value: track.channels != null ? '${track.channels}' : '—',
                ),
                _InfoRow(
                  label: 'Bitrate',
                  value: track.bitrate != null
                      ? '${(track.bitrate! / 1000).round()} kbps'
                      : '—',
                ),
                _InfoRow(label: 'Duration', value: track.durationLabel),
                _InfoRow(
                  label: 'Size',
                  value: track.size > 0
                      ? '${(track.size / 1048576).toStringAsFixed(1)} MB'
                      : '—',
                ),
                _InfoRow(label: 'Release', value: track.releaseId ?? '—'),
                const SizedBox(height: Space.sm),
                const Text(
                  'Quality and identity are derived from the source file '
                  'and enrichment providers. Enrichment never changes audio.',
                  style: TypeScale.caption,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: player,
          builder: (context, _) {
            final current = player.current;
            if (current == null) {
              return const Center(
                child: Text('Nothing playing', style: TypeScale.body),
              );
            }
            final position = player.position;
            final duration = player.duration.inMilliseconds > 0
                ? player.duration
                : Duration(milliseconds: current.durationMs ?? 0);
            final value = position.inMilliseconds
                .clamp(0, duration.inMilliseconds)
                .toDouble();
            final downloaded = store.pathFor(current.sha) != null;

            return SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.xs,
                      Space.sm,
                      Space.xs,
                      0,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: Tones.textMuted,
                          ),
                        ),
                        const Expanded(
                          child: Text(
                            'Now Playing',
                            textAlign: TextAlign.center,
                            style: TypeScale.caption,
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(
                            Icons.more_horiz_rounded,
                            color: Tones.textMuted,
                          ),
                          color: Tones.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              RadiusTokens.control,
                            ),
                          ),
                          onSelected: (action) {
                            switch (action) {
                              case 'queue':
                                _openQueue(context);
                                break;
                              case 'artist':
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => ArtistPage(
                                      artist: current.artist,
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
                                );
                                break;
                              case 'album':
                                _openAlbum(context, current);
                                break;
                              case 'download':
                                if (downloaded) {
                                  store.remove(current.sha);
                                } else {
                                  onDownload(current);
                                }
                                break;
                              case 'stop':
                                player.stop();
                                break;
                              case 'info':
                                _showTrackInfo(context, current);
                                break;
                              case 'lyrics':
                                LyricsSheet.show(
                                  context,
                                  track: current,
                                  player: player,
                                  onSave: (text) async {
                                    await manifestStore.setEdit(
                                      current.sha,
                                      'lyrics',
                                      text,
                                    );
                                  },
                                );
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'queue',
                              child: Text('Queue', style: TypeScale.body),
                            ),
                            const PopupMenuItem(
                              value: 'artist',
                              child: Text(
                                'Go to artist',
                                style: TypeScale.body,
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'album',
                              child: Text('Go to album', style: TypeScale.body),
                            ),
                            PopupMenuItem(
                              value: 'download',
                              child: Text(
                                downloaded ? 'Remove download' : 'Download',
                                style: TypeScale.body,
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'stop',
                              child: Text('Stop', style: TypeScale.body),
                            ),
                            const PopupMenuItem(
                              value: 'info',
                              child: Text(
                                'Track information',
                                style: TypeScale.body,
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'lyrics',
                              child: Text('Lyrics', style: TypeScale.body),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                      child: Center(
                        child: _Artwork(
                          track: current,
                          artUrlFor: artUrlFor,
                          playing: player.playing,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                    child: Column(
                      children: [
                        Text(
                          current.title,
                          style: TypeScale.wordmark,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: Space.sm),
                        Text(
                          current.artist,
                          style: TypeScale.title,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          current.album,
                          style: TypeScale.body,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: Space.lg),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                    child: Row(
                      children: [
                        Text(
                          _label(position),
                          style: TypeScale.caption.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: value,
                            max: duration.inMilliseconds.toDouble().clamp(
                              1,
                              double.infinity,
                            ),
                            onChanged: (v) =>
                                player.seek(Duration(milliseconds: v.round())),
                          ),
                        ),
                        Text(
                          _label(duration),
                          style: TypeScale.caption.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(
                      top: Space.sm,
                      bottom: Space.sm,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: player.previous,
                          iconSize: 36,
                          icon: const Icon(
                            Icons.skip_previous_rounded,
                            color: Tones.text,
                          ),
                          tooltip: 'Previous',
                        ),
                        const SizedBox(width: Space.md),
                        InkWell(
                          onTap: player.playing ? player.pause : player.play,
                          borderRadius: BorderRadius.circular(40),
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: Tones.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              player.playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 40,
                              color: Tones.onPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: Space.md),
                        IconButton(
                          onPressed: player.next,
                          iconSize: 36,
                          icon: const Icon(
                            Icons.skip_next_rounded,
                            color: Tones.text,
                          ),
                          tooltip: 'Next',
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.xl,
                      0,
                      Space.xl,
                      Space.lg,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _ShuffleButton(player: player),
                        _RepeatButton(player: player),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(label, style: TypeScale.caption)),
          Expanded(
            child: Text(
              value,
              style: TypeScale.body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({
    required this.track,
    required this.artUrlFor,
    required this.playing,
  });

  final ManifestTrack track;
  final String Function(String sha) artUrlFor;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    // Cap the artwork by the smaller available axis, so it never
    // explodes on tablets and never overflows in landscape (where the
    // Expanded parent can be ~80dp tall). The lower bound is 0 (not
    // 96) so a layout smaller than 96dp still renders without
    // overflow — at that size the artwork is essentially invisible
    // anyway, but the parent layout doesn't throw.
    return LayoutBuilder(
      builder: (context, c) {
        final available = c.biggest.shortestSide.isFinite
            ? c.biggest.shortestSide
            : 320.0;
        final side = available.clamp(0.0, 360.0);
        final art = ClipRRect(
          borderRadius: BorderRadius.circular(RadiusTokens.card),
          child: SizedBox(
            width: side,
            height: side,
            child: track.artSha != null
                ? Image.network(
                    artUrlFor(track.artSha!),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => GeneratedArtwork(
                      title: track.title,
                      artist: track.artist,
                      size: side,
                    ),
                  )
                : GeneratedArtwork(
                    title: track.title,
                    artist: track.artist,
                    size: side,
                  ),
          ),
        );
        // Subtle "alive" motion: slow rotation while playing, snap-back
        // on pause. Cheap, gives the screen presence.
        return AnimatedRotation(
          turns: playing ? 1 : 0,
          duration: const Duration(seconds: 30),
          curve: Curves.linear,
          child: art,
        );
      },
    );
  }
}

class _ShuffleButton extends StatelessWidget {
  const _ShuffleButton({required this.player});
  final TunePlayer player;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final on = player.shuffle;
        return IconButton(
          tooltip: 'Shuffle',
          icon: Icon(
            Icons.shuffle_rounded,
            color: on ? Tones.primary : Tones.textMuted,
          ),
          onPressed: () => player.setShuffle(!on),
        );
      },
    );
  }
}

class _RepeatButton extends StatelessWidget {
  const _RepeatButton({required this.player});
  final TunePlayer player;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final mode = player.repeat;
        final isActive = mode != PlaybackRepeat.off;
        final icon = switch (mode) {
          PlaybackRepeat.off => Icons.repeat_rounded,
          PlaybackRepeat.all => Icons.repeat_rounded,
          PlaybackRepeat.one => Icons.repeat_one_rounded,
        };
        return IconButton(
          tooltip: switch (mode) {
            PlaybackRepeat.off => 'Repeat: off',
            PlaybackRepeat.all => 'Repeat: all',
            PlaybackRepeat.one => 'Repeat: one',
          },
          icon: Icon(icon, color: isActive ? Tones.primary : Tones.textMuted),
          onPressed: () {
            final next = switch (mode) {
              PlaybackRepeat.off => PlaybackRepeat.all,
              PlaybackRepeat.all => PlaybackRepeat.one,
              PlaybackRepeat.one => PlaybackRepeat.off,
            };
            player.setRepeat(next);
          },
        );
      },
    );
  }
}
