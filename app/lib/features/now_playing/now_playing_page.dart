import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/download_store.dart';
import '../../core/theme/tokens.dart';
import '../../domain/manifest.dart';
import '../artist/artist_page.dart';
import '../album/album_page.dart';
import '../library/library_widgets.dart';

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
  });

  final TunePlayer player;
  final TunesManifest manifest;
  final DownloadStore store;
  final Set<String> downloading;
  final void Function(ManifestTrack) onDownload;
  final bool offline;
  final String Function(String sha) artUrlFor;

  String _label(Duration d) {
    final s = d.inSeconds;
    final m = (s ~/ 60).toString().padLeft(2, '0');
    return '$m:${(s % 60).toString().padLeft(2, '0')}';
  }

  void _openQueue(BuildContext context) {
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
          child: SizedBox(
            height: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    Space.md,
                    Space.lg,
                    Space.sm,
                  ),
                  child: Text('Queue', style: TypeScale.title),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      Space.lg,
                      0,
                      Space.lg,
                      Space.lg,
                    ),
                    itemCount: player.queue.length,
                    itemBuilder: (context, i) {
                      final t = player.queue[i];
                      final isCurrent = i == player.index;
                      return InkWell(
                        onTap: () {
                          player.playAt(i);
                          Navigator.of(sheetContext).pop();
                        },
                        borderRadius: BorderRadius.circular(
                          RadiusTokens.control,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: Space.sm,
                            horizontal: Space.xs,
                          ),
                          child: Row(
                            children: [
                              Text(
                                isCurrent ? 'Now playing' : (i + 1).toString(),
                                style: TypeScale.caption.copyWith(
                                  color: isCurrent
                                      ? Tones.primary
                                      : Tones.textMuted,
                                ),
                              ),
                              const SizedBox(width: Space.md),
                              ArtThumb(
                                sha: t.artSha,
                                artUrlFor: artUrlFor,
                                size: 36,
                              ),
                              const SizedBox(width: Space.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t.title,
                                      style: TypeScale.title.copyWith(
                                        color: isCurrent ? Tones.primary : null,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      t.artist,
                                      style: TypeScale.body,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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

            return Column(
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
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'queue',
                            child: Text('Queue', style: TypeScale.body),
                          ),
                          const PopupMenuItem(
                            value: 'artist',
                            child: Text('Go to artist', style: TypeScale.body),
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
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: 280,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.xl,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 220,
                              height: 220,
                              decoration: BoxDecoration(
                                color: Tones.surfaceRaised,
                                borderRadius: BorderRadius.circular(
                                  RadiusTokens.card,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  RadiusTokens.card,
                                ),
                                child: current.artSha != null
                                    ? Image.network(
                                        artUrlFor(current.artSha!),
                                        width: 220,
                                        height: 220,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) =>
                                            ArtPlaceholder(size: 220),
                                      )
                                    : const ArtPlaceholder(size: 220),
                              ),
                            ),
                            const SizedBox(height: Space.md),
                            Text(
                              current.title,
                              style: TypeScale.wordmark,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: Space.sm),
                            Text(current.artist, style: TypeScale.title),
                            const SizedBox(height: Space.xs),
                            Text(current.album, style: TypeScale.body),
                          ],
                        ),
                      ),
                    ),
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
                    bottom: Space.lg,
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
              ],
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
