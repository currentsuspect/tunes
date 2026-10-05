import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/download_store.dart';
import '../../core/data/manifest_store.dart';
import '../../core/data/playlist_store.dart';
import '../../core/data/queue_store.dart';
import '../../core/data/settings_store.dart';
import '../../core/nav/nav_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/artwork.dart';
import '../../core/ui/generated_artwork.dart';
import '../../core/ui/like_button.dart';
import '../../core/data/reachability.dart';
import '../../core/ui/cover_tint.dart';
import '../../core/ui/shared_sleeve.dart';
import '../../core/ui/source_pill.dart';
import '../player/scrubber.dart';
import '../../domain/manifest.dart';
import '../album/album_page.dart';
import '../artist/artist_page.dart';
import '../lyrics/lyrics_sheet.dart';
import '../playlists/add_to_playlist_sheet.dart';
import '../queue/queue_sheet.dart';
import 'lyric_preview.dart';
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
    this.reachability,
    this.shareLyrics,
  });

  /// Saves a listener's lyrics and shares them with everyone. Without it they
  /// are kept on this phone only, which is all a screen outside the app shell
  /// (a test) can do.
  final Future<void> Function(String sha, String text)? shareLyrics;

  /// Live, so the source tag follows the connection rather than what it was
  /// when the page opened. Falls back to [offline] when absent.
  final Reachability? reachability;

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

  /// Leaving the player for an artist or an album goes through the shell
  /// history: the destination is recorded after the player, so Back returns
  /// here rather than skipping it.
  void _openArtist(BuildContext context, String artist) {
    NavScope.of(context).openPanel(
      TunesPanels.artist(artist),
      () => ArtistPage(
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
    );
  }

  void _openLyrics(BuildContext context, ManifestTrack track) {
    LyricsSheet.show(
      context,
      track: track,
      player: widget.player,
      onSave: (text) async {
        final share = widget.shareLyrics;
        if (share != null) {
          await share(track.sha, text);
        } else {
          await widget.manifestStore.setEdit(track.sha, 'lyrics', text);
        }
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
    // Recorded after the player, like _openArtist.
    NavScope.of(context).openPanel(
      TunesPanels.album(resolved.id),
      () => AlbumPage(
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
      body: ListenableBuilder(
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

          return _Backdrop(
            artSha: current.artSha,
            child: SafeArea(
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
                                        NavScope.of(context).back(),
                                    icon: const Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      color: Tones.textMuted,
                                    ),
                                  ),
                                  Expanded(
                                    child: Center(
                                      child: _SourceTag(
                                        held: downloaded,
                                        offline: widget.offline,
                                        reachability: widget.reachability,
                                      ),
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
                                          // The same opener the sleeve uses.
                                          // This was a second copy of the same
                                          // navigation, so the two routes could
                                          // — and did — behave differently.
                                          _openArtist(
                                            context,
                                            current.artistDisplay,
                                          );
                                          break;
                                        case 'album':
                                          _openAlbum(context, current);
                                          break;
                                        case 'playlist':
                                          final playlists =
                                              PlaylistScope.maybeOf(context);
                                          if (playlists != null) {
                                            AddToPlaylistSheet.show(
                                              context,
                                              store: playlists,
                                              shas: [current.sha],
                                            );
                                          }
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
                                          // Same opener the preview tap and
                                          // the details sheet use, so all
                                          // three routes save identically.
                                          _openLyrics(context, current);
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
                                      const PopupMenuItem(
                                        value: 'playlist',
                                        child: Text(
                                          'Add to playlist',
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
                            // The sleeve is the subject, lit from behind by its
                            // own colour. Title and artist sit under it, left
                            // aligned, with the heart at the end of the title
                            // line: the heart is a statement about this track,
                            // not a way of moving through it.
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: Space.lg,
                                  vertical: Space.sm,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Flexible(
                                      child: Center(
                                        child: SharedSleeve(
                                          tag: 'sleeve-${current.sha}',
                                          child: _Artwork(
                                            track: current,
                                            artUrlFor: widget.artUrlFor,
                                            playing: widget.player.playing,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: Space.lg),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                current.title,
                                                style: TypeScale.display,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: Space.xs),
                                              GestureDetector(
                                                onTap: () => _openArtist(
                                                  context,
                                                  current.artistDisplay,
                                                ),
                                                child: Text(
                                                  current.artistDisplay,
                                                  style: TypeScale.body
                                                      .copyWith(fontSize: 15),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (current.albumLabel != null)
                                                Text(
                                                  current.albumLabel!,
                                                  style: TypeScale.mono,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                            ],
                                          ),
                                        ),
                                        LikeButton(sha: current.sha, size: 26),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: Space.md,
                              ),
                              child: Scrubber(
                                player: widget.player,
                                duration: duration,
                              ),
                            ),
                            // Five controls on one line: the two switches that
                            // change how the queue behaves at the edges, and
                            // the transport between them. The play button is
                            // paper on ink, not the accent, so it stays the
                            // calmest thing on a screen already full of light.
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: Space.lg,
                                vertical: Space.xs,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  _ShuffleButton(player: widget.player),
                                  IconButton(
                                    onPressed: widget.player.previous,
                                    iconSize: 36,
                                    icon: const Icon(
                                      Icons.skip_previous_rounded,
                                      color: Tones.text,
                                    ),
                                    tooltip: 'Previous',
                                  ),
                                  _PlayButton(player: widget.player),
                                  IconButton(
                                    onPressed: widget.player.next,
                                    iconSize: 36,
                                    icon: const Icon(
                                      Icons.skip_next_rounded,
                                      color: Tones.text,
                                    ),
                                    tooltip: 'Next',
                                  ),
                                  _RepeatButton(player: widget.player),
                                ],
                              ),
                            ),
                            // The line being sung. A reactive surface, not a
                            // control: it shows where the words are and opens
                            // the full view on tap. With no lyrics it is one
                            // quiet line offering to add them, at the same
                            // height, so the sleeve, title and controls sit
                            // exactly where they do for a song that has them.
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: Space.lg,
                              ),
                              child: LyricPreview(
                                lyrics: current.lyrics,
                                player: widget.player,
                                onOpen: () => _openLyrics(context, current),
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
            ),
          );
        },
      ),
    );
  }
}

/// The page's room: ink wall, with the cover's colour pouring in from the top.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.artSha, required this.child});

  final String? artSha;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TintBuilder(
      artSha: artSha,
      builder: (context, tint) => Stack(
        fit: StackFit.expand,
        children: [
          AmbientGlow(tint: tint),
          child,
        ],
      ),
    );
  }
}

/// "held offline", "streaming" or "not on this phone yet", following the
/// connection live when it can.
class _SourceTag extends StatelessWidget {
  const _SourceTag({
    required this.held,
    required this.offline,
    required this.reachability,
  });

  final bool held;
  final bool offline;
  final Reachability? reachability;

  @override
  Widget build(BuildContext context) {
    final r = reachability;
    if (r == null) {
      return SourcePill(
        source: sourceFor(held: held, offline: offline),
      );
    }
    return ListenableBuilder(
      listenable: r,
      builder: (context, _) => SourcePill(
        source: sourceFor(held: held, offline: r.offline),
      ),
    );
  }
}

/// Paper on ink. The accent belongs to the line and the light; this is just
/// the thing you press.
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.player});

  final TunePlayer player;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: player.playing ? 'Pause' : 'Play',
      child: InkWell(
        onTap: player.playing ? player.pause : player.play,
        customBorder: const CircleBorder(),
        child: Container(
          width: 68,
          height: 68,
          decoration: const BoxDecoration(
            color: Tones.text,
            shape: BoxShape.circle,
          ),
          child: Icon(
            player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 38,
            color: Tones.base,
          ),
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
          artSha: track.artSha,
          size: side,
          borderRadius: 16,
          // Same decode as the mini bar's copy, so the flight has nothing
          // left to load when it arrives.
          shared: true,
          fallback: GeneratedArtwork(
            title: track.title,
            artist: track.artistDisplay,
            size: side,
            borderRadius: 16,
          ),
        );
        // Lit by its own colour: the glow under the sleeve is the same tint
        // as the wash behind it, so the cover looks like the lamp.
        final lit = DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AccentScope.of(context).withValues(alpha: 0.55),
                blurRadius: 48,
                spreadRadius: -8,
                offset: const Offset(0, 22),
              ),
            ],
          ),
          child: art,
        );
        // Off unless asked for, and off whenever the system asks for less
        // motion. A square sleeve turning for thirty seconds at a time is a
        // choice, not a default.
        final wanted = SettingsScope.maybeOf(context)?.animatedArtwork ?? false;
        if (!wanted || MediaQuery.disableAnimationsOf(context)) return lit;
        return AnimatedRotation(
          turns: playing ? 1 : 0,
          duration: const Duration(seconds: 30),
          curve: Curves.linear,
          child: lit,
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
            color: on ? AccentScope.of(context) : Tones.textMuted,
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
          icon: Icon(
            icon,
            color: isActive ? AccentScope.of(context) : Tones.textMuted,
          ),
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
