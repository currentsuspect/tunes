import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/download_store.dart';
import '../../core/data/manifest_store.dart';
import '../../core/data/queue_store.dart';
import '../../core/data/settings_store.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/artwork.dart';
import '../../core/ui/generated_artwork.dart';
import '../../core/ui/like_button.dart';
import '../../core/ui/shared_sleeve.dart';
import '../player/scrubber.dart';
import '../../domain/manifest.dart';
import '../album/album_page.dart';
import '../artist/artist_page.dart';
import '../lyrics/lyrics_sheet.dart';
import '../queue/queue_sheet.dart';
import 'now_playing_details.dart';

class NowPlayingPage extends StatefulWidget {
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

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Pulls the drawer up, or puts it back.
  ///
  /// The details already live below the widget.player in the same scroll view, so
  /// this animates the view rather than pushing a route: the widget.player stays
  /// exactly where it was and the sheet arrives over it.
  void _toggleDrawer() {
    if (!_scroll.hasClients) return;
    final open = _scroll.offset > 8;
    _scroll.animateTo(
      open ? 0 : _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _openQueue(BuildContext context) {
    final qs = widget.queueStore;
    if (qs == null) return;
    QueueSheet.show(context, queueStore: qs, player: widget.player);
  }

  void _openArtist(BuildContext context, String artist) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArtistPage(
          artist: artist,
          manifest: widget.manifest,
          player: widget.player,
          store: widget.store,
          downloading: widget.downloading,
          onDownload: widget.onDownload,
          offline: widget.offline,
          artUrlFor: widget.artUrlFor,
          manifestStore: widget.manifestStore,
          queueStore: widget.queueStore,
        ),
      ),
    );
  }

  void _openLyrics(BuildContext context, ManifestTrack track) {
    LyricsSheet.show(
      context,
      track: track,
      player: widget.player,
      onSave: (text) async {
        await widget.manifestStore.setEdit(track.sha, 'lyrics', text);
      },
    );
  }

  void _openAlbum(BuildContext context, ManifestTrack track) {
    ManifestRelease? release;
    if (track.releaseId != null) {
      for (final r in widget.manifest.releases) {
        if (r.id == track.releaseId) {
          release = r;
          break;
        }
      }
    }
    if (release == null) {
      for (final r in widget.manifest.releases) {
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
          manifest: widget.manifest,
          player: widget.player,
          store: widget.store,
          downloading: widget.downloading,
          onDownload: widget.onDownload,
          offline: widget.offline,
          artUrlFor: widget.artUrlFor,
          manifestStore: widget.manifestStore,
          queueStore: widget.queueStore,
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
          listenable: widget.player,
          builder: (context, _) {
            final current = widget.player.current;
            if (current == null) {
              return const Center(
                child: Text('Nothing playing', style: TypeScale.body),
              );
            }
            final duration = widget.player.duration.inMilliseconds > 0
                ? widget.player.duration
                : Duration(milliseconds: current.durationMs ?? 0);
            final downloaded = widget.store.pathFor(current.sha) != null;

            return SafeArea(
              // The widget.player keeps a whole viewport to itself so nothing about
              // it changes; the details are a scroll away rather than a
              // squeeze. A fixed height also keeps the Expanded artwork
              // working, which it would not inside an unbounded scroll view.
              child: LayoutBuilder(
                builder: (context, viewport) => SingleChildScrollView(
                  controller: _scroll,
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
                                                manifest: widget.manifest,
                                                player: widget.player,
                                                store: widget.store,
                                                downloading: widget.downloading,
                                                onDownload: widget.onDownload,
                                                offline: widget.offline,
                                                artUrlFor: widget.artUrlFor,
                                                manifestStore:
                                                    widget.manifestStore,
                                                queueStore: widget.queueStore,
                                              ),
                                            ),
                                          );
                                          break;
                                        case 'album':
                                          _openAlbum(context, current);
                                          break;
                                        case 'download':
                                          if (downloaded) {
                                            widget.store.remove(current.sha);
                                          } else {
                                            widget.onDownload(current);
                                          }
                                          break;
                                        case 'stop':
                                          widget.player.stop();
                                          break;
                                        case 'info':
                                          _showTrackInfo(context, current);
                                          break;
                                        case 'lyrics':
                                          LyricsSheet.show(
                                            context,
                                            track: current,
                                            player: widget.player,
                                            onSave: (text) async {
                                              await widget.manifestStore
                                                  .setEdit(
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
                            // Sleeve and words are one centred unit. They
                            // used to be separate children of this column,
                            // with an Expanded between them that handed all
                            // the slack to the gap -- so the title floated a
                            // long way under the record it names. The slack
                            // now sits outside the pair, above and below.
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
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: SharedSleeve(
                                        tag: 'sleeve-${current.sha}',
                                        child: _Artwork(
                                          track: current,
                                          artUrlFor: widget.artUrlFor,
                                          playing: widget.player.playing,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: Space.lg),
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
                                  ],
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: Space.lg,
                              ),
                              child: Scrubber(
                                player: widget.player,
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
                                  IconButton(
                                    onPressed: widget.player.previous,
                                    iconSize: 36,
                                    icon: const Icon(
                                      Icons.skip_previous_rounded,
                                      color: Tones.text,
                                    ),
                                    tooltip: 'Previous',
                                  ),
                                  const SizedBox(width: Space.md),
                                  InkWell(
                                    onTap: widget.player.playing
                                        ? widget.player.pause
                                        : widget.player.play,
                                    borderRadius: BorderRadius.circular(40),
                                    child: Container(
                                      width: 72,
                                      height: 72,
                                      decoration: BoxDecoration(
                                        color: Tones.primary,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        widget.player.playing
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        size: 40,
                                        color: Tones.onPrimary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: Space.md),
                                  IconButton(
                                    onPressed: widget.player.next,
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
                            // One cluster, centred under the transport,
                            // rather than two icons shoved to opposite
                            // edges with a void between them. Shuffle and
                            // repeat belong together -- they are the two
                            // switches that change how the queue behaves --
                            // and the heart sits with them because it is a
                            // toggle too, not a way of moving through a
                            // track. The play button keeps the centre line
                            // to itself.
                            Padding(
                              padding: const EdgeInsets.only(bottom: Space.xs),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _ShuffleButton(player: widget.player),
                                  const SizedBox(width: Space.lg),
                                  LikeButton(sha: current.sha, size: 24),
                                  const SizedBox(width: Space.lg),
                                  _RepeatButton(player: widget.player),
                                ],
                              ),
                            ),
                            // Says there is something below, which a scroll view on a
                            // screen that exactly fills the viewport otherwise hides.
                            // A handle, not a footer. It used to be a small
                            // chevron over a caption at the very bottom of
                            // the screen, which reads as a label for the
                            // page rather than something to pull.
                            InkWell(
                              onTap: _toggleDrawer,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  top: Space.xs,
                                  bottom: Space.sm,
                                ),
                                child: Column(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: Tones.hairline,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    const SizedBox(height: Space.xs),
                                    Text(
                                      'Lyrics and credits',
                                      style: TypeScale.caption.copyWith(
                                        color: Tones.textMuted.withValues(
                                          alpha: 0.85,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Raised surface with a rounded top edge, so what
                      // arrives from below reads as a sheet over the player
                      // rather than more page.
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(RadiusTokens.card),
                        ),
                        child: ColoredBox(
                          color: Tones.surface,
                          child: NowPlayingDetails(
                            track: current,
                            manifest: widget.manifest,
                            artUrlFor: widget.artUrlFor,
                            onOpenArtist: (a) => _openArtist(context, a),
                            onOpenAlbum: () => _openAlbum(context, current),
                            onOpenLyrics: () => _openLyrics(context, current),
                          ),
                        ),
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
          // Same decode as the mini bar's copy, so the flight has nothing
          // left to load when it arrives.
          shared: true,
          fallback: GeneratedArtwork(
            title: track.title,
            artist: track.artistDisplay,
            size: side,
          ),
        );
        // Subtle "alive" motion: slow rotation while playing, snap-back on
        // pause. It is the only thing in the app that moves continuously, so
        // it is also the only animation with a switch of its own.
        // Off by choice, or off because the system asked for less motion.
        // A sleeve that turns for thirty seconds at a time is exactly what
        // that setting exists to stop.
        final wanted = SettingsScope.maybeOf(context)?.animatedArtwork ?? true;
        if (!wanted || MediaQuery.disableAnimationsOf(context)) return art;
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
