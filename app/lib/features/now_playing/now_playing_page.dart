import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/download_store.dart';
import '../../core/data/manifest_store.dart';
import '../../core/data/queue_store.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/artwork.dart';
import '../../core/ui/generated_artwork.dart';
import '../../core/ui/like_button.dart';
import '../player/scrubber.dart';
import '../../domain/manifest.dart';
import '../album/album_page.dart';
import '../artist/artist_page.dart';
import '../lyrics/lyrics_sheet.dart';
import '../queue/queue_sheet.dart';
import 'now_playing_details.dart';

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

  void _openQueue(BuildContext context) {
    final qs = queueStore;
    if (qs == null) return;
    QueueSheet.show(context, queueStore: qs, player: player);
  }

  void _openArtist(BuildContext context, String artist) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArtistPage(
          artist: artist,
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

  void _openLyrics(BuildContext context, ManifestTrack track) {
    LyricsSheet.show(
      context,
      track: track,
      player: player,
      onSave: (text) async {
        await manifestStore.setEdit(track.sha, 'lyrics', text);
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
        if (r.artist == track.artistDisplay && r.title == track.album) {
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
                _InfoRow(label: 'Artist', value: track.artistDisplay),
                if (track.featured.isNotEmpty)
                  _InfoRow(label: 'Featured', value: track.featured.join(', ')),
                _InfoRow(label: 'Album', value: track.albumOrNull ?? '—'),
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
            final duration = player.duration.inMilliseconds > 0
                ? player.duration
                : Duration(milliseconds: current.durationMs ?? 0);
            final downloaded = store.pathFor(current.sha) != null;

            return SafeArea(
              // The player keeps a whole viewport to itself so nothing about
              // it changes; the details are a scroll away rather than a
              // squeeze. A fixed height also keeps the Expanded artwork
              // working, which it would not inside an unbounded scroll view.
              child: LayoutBuilder(
                builder: (context, viewport) => SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: viewport.maxHeight,
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
                                    onPressed: () =>
                                        Navigator.of(context).maybePop(),
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
                                                artist: current.artistDisplay,
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
                                        child: Text(
                                          'Queue',
                                          style: TypeScale.body,
                                        ),
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
                                        child: Text(
                                          'Go to album',
                                          style: TypeScale.body,
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'download',
                                        child: Text(
                                          downloaded
                                              ? 'Remove download'
                                              : 'Download',
                                          style: TypeScale.body,
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'stop',
                                        child: Text(
                                          'Stop',
                                          style: TypeScale.body,
                                        ),
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
                                        child: Text(
                                          'Lyrics',
                                          style: TypeScale.body,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                // lg, not xl: the sleeve is the subject of
                                // this screen and forty points of margin a
                                // side was giving away sixty-four points of
                                // it to nothing.
                                padding: const EdgeInsets.symmetric(
                                  horizontal: Space.lg,
                                  vertical: Space.sm,
                                ),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: Space.lg,
                              ),
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
                                    current.artistDisplay,
                                    style: TypeScale.title,
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (current.albumLabel != null)
                                    Text(
                                      current.albumLabel!,
                                      style: TypeScale.body,
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  const SizedBox(height: Space.md),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: Space.lg,
                              ),
                              child: Scrubber(
                                player: player,
                                duration: duration,
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
                                  // Sits with the transport rather than up by
                                  // the title: liking is something you do
                                  // while a track is playing, with the same
                                  // thumb that just pressed play.
                                  LikeButton(sha: current.sha, size: 26),
                                  const SizedBox(width: Space.sm),
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
                                    onTap: player.playing
                                        ? player.pause
                                        : player.play,
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
                                Space.xs,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  _ShuffleButton(player: player),
                                  _RepeatButton(player: player),
                                ],
                              ),
                            ),
                            // Says there is something below, which a scroll view on a
                            // screen that exactly fills the viewport otherwise hides.
                            Padding(
                              padding: const EdgeInsets.only(bottom: Space.sm),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.keyboard_arrow_up_rounded,
                                    size: 18,
                                    color: Tones.textMuted.withValues(
                                      alpha: 0.7,
                                    ),
                                  ),
                                  Text(
                                    'Lyrics and credits',
                                    style: TypeScale.caption.copyWith(
                                      color: Tones.textMuted.withValues(
                                        alpha: 0.7,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      NowPlayingDetails(
                        track: current,
                        manifest: manifest,
                        artUrlFor: artUrlFor,
                        onOpenArtist: (a) => _openArtist(context, a),
                        onOpenAlbum: () => _openAlbum(context, current),
                        onOpenLyrics: () => _openLyrics(context, current),
                      ),
                    ],
                  ),
                ),
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
        // Bounded by the shorter axis so it neither explodes on a tablet
        // nor overflows in landscape, where the Expanded parent can be about
        // eighty points tall. The cap rises with the viewport: on a tall
        // phone the leftover height used to become an empty band above and
        // below the sleeve rather than more sleeve.
        final side = available.clamp(0.0, 420.0);
        final art = Artwork(
          url: track.artSha == null ? null : artUrlFor(track.artSha!),
          size: side,
          fallback: GeneratedArtwork(
            title: track.title,
            artist: track.artistDisplay,
            size: side,
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
