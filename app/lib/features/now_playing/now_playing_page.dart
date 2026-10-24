import '../../core/platform/device.dart';

import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/download_store.dart';
import '../../core/data/manifest_store.dart';
import '../../core/data/playlist_store.dart';
import '../../core/data/queue_store.dart';
import '../../core/data/settings_store.dart';
import '../../core/nav/nav_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/looks.dart';
import '../../core/ui/crayon_marks.dart';
import '../../core/ui/tunes_menu.dart';
import '../../core/audio/sleep_timer.dart';
import 'sleep_sheet.dart';
import '../../core/ui/look_extras.dart';
import '../../core/ui/artwork.dart';
import '../../core/ui/generated_artwork.dart';
import '../../core/data/download_manager.dart';
import '../../core/data/likes_store.dart';
import '../../core/ui/double_tap_cover.dart';
import '../../core/ui/download_button.dart';
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
import '../lyrics/share_moment.dart' show MomentClipper;
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
    this.clipMoment,
  });

  /// Saves a listener's lyrics and shares them with everyone. Without it they
  /// are kept on this phone only, which is all a screen outside the app shell
  /// (a test) can do.
  final Future<void> Function(String sha, String text)? shareLyrics;

  /// Cuts a moment of a song on the box, for sharing a lyric line.
  final MomentClipper? clipMoment;

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
      clip: widget.clipMoment,
      artUrlFor: widget.artUrlFor,
      onSave: (saved, text) async {
        final share = widget.shareLyrics;
        if (share != null) {
          await share(saved.sha, text);
        } else {
          await widget.manifestStore.setEdit(saved.sha, 'lyrics', text);
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
      shape: RoundedRectangleBorder(
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
                Text(
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
            return Center(
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
                                    icon: Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      color: Tones.textMuted,
                                    ),
                                  ),
                                  Expanded(
                                    child: Center(
                                      // While a sleep timer runs, the time
                                      // left takes the source's place: it is
                                      // what matters at that hour.
                                      child: _SleepOrSource(
                                        source: SourceTag(
                                          player: widget.player,
                                          held: downloaded,
                                          offline: widget.offline,
                                          reachability: widget.reachability,
                                        ),
                                      ),
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    icon: Icon(
                                      Icons.more_horiz_rounded,
                                      color: Tones.textMuted,
                                    ),
                                    tooltip: 'More',
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
                                        case 'sleep':
                                          final sleep = SleepScope.maybeOf(
                                            context,
                                          );
                                          if (sleep != null) {
                                            SleepSheet.show(context, sleep);
                                          }
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
                                      tunesMenuItem(
                                        'queue',
                                        Icons.queue_music_rounded,
                                        'Queue',
                                      ),
                                      // Beside the player already when the window is wide
                                      // and the song has lyrics; otherwise this is the way
                                      // in (to read them, or to add some).
                                      if (!(isWideWindow(
                                            MediaQuery.sizeOf(context),
                                          ) &&
                                          (SettingsScope.maybeOf(context)
                                                  ?.showLyrics ??
                                              true) &&
                                          (current.lyrics ?? '')
                                              .trim()
                                              .isNotEmpty))
                                        tunesMenuItem(
                                          'lyrics',
                                          Icons.lyrics_outlined,
                                          'Lyrics',
                                        ),
                                      tunesMenuDivider(),
                                      tunesMenuItem(
                                        'artist',
                                        Icons.person_outline_rounded,
                                        'Go to artist',
                                      ),
                                      tunesMenuItem(
                                        'album',
                                        Icons.album_outlined,
                                        'Go to album',
                                      ),
                                      tunesMenuDivider(),
                                      tunesMenuItem(
                                        'playlist',
                                        Icons.playlist_add_rounded,
                                        'Add to playlist',
                                      ),
                                      tunesMenuItem(
                                        'download',
                                        downloaded
                                            ? Icons.cloud_off_outlined
                                            : Icons.download_rounded,
                                        downloaded
                                            ? 'Remove download'
                                            : 'Download',
                                        danger: downloaded,
                                      ),
                                      tunesMenuItem(
                                        'info',
                                        Icons.info_outline_rounded,
                                        'Track information',
                                      ),
                                      tunesMenuDivider(),
                                      if (SleepScope.maybeOf(context) != null)
                                        tunesMenuItem(
                                          'sleep',
                                          Icons.bedtime_outlined,
                                          'Sleep timer',
                                        ),
                                      tunesMenuItem(
                                        'stop',
                                        Icons.stop_circle_outlined,
                                        'Stop',
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
                                        child: DoubleTapCover(
                                          onDoubleTap: () =>
                                              _doubleTap(context, current),
                                          child: SharedSleeve(
                                            tag: 'sleeve-${current.sha}',
                                            child: _Artwork(
                                              player: widget.player,
                                              track: current,
                                              artUrlFor: widget.artUrlFor,
                                              playing: widget.player.playing,
                                            ),
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
                                              // Noir: the music's details as
                                              // fine print.
                                              if (Looks.current.kind ==
                                                  LookKind.noir)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: Space.xs,
                                                      ),
                                                  child: Text(
                                                    audioSpec(current),
                                                    style: TypeScale.mono
                                                        .copyWith(
                                                          color: Tones.primary,
                                                          letterSpacing: 1.4,
                                                          fontSize: 10,
                                                        ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        _CoverActionButton(track: current),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // The desktop player along the foot of the window has the
                            // seek bar and the transport, so a wide page does not
                            // repeat them.
                            if (!isWideWindow(MediaQuery.sizeOf(context))) ...[
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
                                      icon: Icon(
                                        Icons.skip_previous_rounded,
                                        color: Tones.text,
                                      ),
                                      tooltip: 'Previous',
                                    ),
                                    _PlayButton(player: widget.player),
                                    IconButton(
                                      onPressed: widget.player.next,
                                      iconSize: 36,
                                      icon: Icon(
                                        Icons.skip_next_rounded,
                                        color: Tones.text,
                                      ),
                                      tooltip: 'Next',
                                    ),
                                    _RepeatButton(player: widget.player),
                                  ],
                                ),
                              ),
                            ],
                            // The line being sung, only when there is one to sing.
                            // A song with no lyrics, a listener who has turned
                            // them off, and a window wide enough to show them
                            // beside the player all leave this out, rather than
                            // holding an empty strip: the page is the player.
                            if ((SettingsScope.maybeOf(context)?.showLyrics ??
                                    true) &&
                                (current.lyrics ?? '').trim().isNotEmpty &&
                                !isWideWindow(MediaQuery.sizeOf(context)))
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
                                      'About this track',
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
                        borderRadius: BorderRadius.vertical(
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

/// "saved", "streaming" or "not here yet", following the
/// connection live when it can.
class SourceTag extends StatelessWidget {
  const SourceTag({
    super.key,
    required this.player,
    required this.held,
    required this.offline,
    required this.reachability,
  });

  final TunePlayer player;
  final bool held;
  final bool offline;
  final Reachability? reachability;

  @override
  Widget build(BuildContext context) {
    final remote = player.remoteDeviceLabel;
    if (remote != null) {
      return _StatusPill(
        icon: player.remoteStalled
            ? Icons.portable_wifi_off_rounded
            : _kind(remote).contains('computer')
            ? Icons.computer_rounded
            : Icons.smartphone_rounded,
        mark: player.remoteStalled
            ? CrayonMark.cloudOff
            : _kind(remote).contains('computer')
            ? CrayonMark.computer
            : CrayonMark.phone,
        text: player.remoteStalled
            ? "${_kind(remote)} isn't answering"
            : 'playing on ${_kind(remote)}',
        color: player.remoteStalled
            ? Tones.warn
            : Theme.of(context).colorScheme.primary,
        // The music is elsewhere and these controls drive it. This brings it
        // here, from the same second.
        action: 'Play here',
        onTap: player.playHere,
      );
    }
    final r = reachability;
    if (r == null) {
      return _sourcePill(sourceFor(held: held, offline: offline));
    }
    return ListenableBuilder(
      listenable: r,
      builder: (context, _) =>
          _sourcePill(sourceFor(held: held, offline: r.offline)),
    );
  }

  static Widget _sourcePill(TrackSource source) {
    final (icon, mark, text, color) = switch (source) {
      TrackSource.saved => (
        Icons.download_done_rounded,
        CrayonMark.tick,
        'saved on ${Device.thisOne}',
        Tones.held,
      ),
      TrackSource.streaming => (
        Icons.cloud_queue_rounded,
        CrayonMark.cloud,
        'streaming',
        Tones.textMuted,
      ),
      TrackSource.unavailable => (
        Icons.cloud_off_rounded,
        CrayonMark.cloudOff,
        'not on ${Device.thisOne} yet',
        Tones.warn,
      ),
    };
    return _StatusPill(icon: icon, mark: mark, text: text, color: color);
  }

  /// "Dylan's phone" -> "phone": the kind of device is what you need to see.
  static String _kind(String label) {
    final m = RegExp(r"'s\s+(.+)$").firstMatch(label);
    return (m?.group(1) ?? label).toLowerCase();
  }
}

/// Where the sound is, at the top of Now Playing: an icon and a few words on a
/// faint wash of the colour that means it, with an optional action set apart
/// at the end. One shape for held, streaming, missing and on another device,
/// so they read as states of the same thing rather than four different tags.
class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.mark,
    required this.text,
    required this.color,
    this.action,
    this.onTap,
  });

  final IconData icon;

  /// The same thing, hand-drawn, for Crayon.
  final CrayonMark mark;
  final String text;
  final Color color;
  final String? action;
  final VoidCallback? onTap;

  /// Crayon's version (design approved 23 Oct): the "a fave!" sticker's
  /// shape -- ink edge, hard shadow, a slight tilt -- with a drawn mark in
  /// its crayon and the words in ink, not tinted, so they read on paper.
  Widget _crayon() {
    final look = Looks.current;
    final markColor = switch (mark) {
      CrayonMark.tick => Tones.held,
      CrayonMark.cloud => Tones.badge,
      CrayonMark.cloudOff => Tones.warn,
      CrayonMark.computer || CrayonMark.phone => Tones.text,
    };
    final paper = mark == CrayonMark.cloudOff
        ? Color.alphaBlend(
            Tones.warn.withValues(alpha: 0.18),
            Tones.surfaceRaised,
          )
        : Tones.surfaceRaised;
    final words = TypeScale.caption.copyWith(
      fontSize: 13,
      height: 1.1,
      letterSpacing: 0,
      color: Tones.text,
    );
    return Transform.rotate(
      angle: -0.026,
      child: Container(
        padding: EdgeInsets.fromLTRB(10, 5, action == null ? 13 : 5, 5),
        decoration: BoxDecoration(
          color: paper,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Tones.text, width: 2),
          boxShadow: [
            BoxShadow(color: look.inkShadow, offset: const Offset(2, 2)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CrayonMarkIcon(mark, size: 18, color: markColor),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: words,
              ),
            ),
            if (action != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: Tones.primary,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: Tones.text, width: 2),
                ),
                child: Text(
                  action!,
                  maxLines: 1,
                  style: words.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: look.isDark ? Tones.base : Tones.text,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = Looks.current.kind == LookKind.crayon
        ? _crayon()
        : Container(
            padding: EdgeInsets.fromLTRB(10, 5, action == null ? 12 : 5, 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TypeScale.mono.copyWith(
                      fontSize: 11.5,
                      height: 1.2,
                      color: color,
                    ),
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      action!,
                      maxLines: 1,
                      style: TypeScale.mono.copyWith(
                        fontSize: 11,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: Tones.base,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
    return Semantics(
      button: onTap != null,
      label: action == null ? text : '$text. $action',
      child: onTap == null
          ? body
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: body,
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
    final crayon = Looks.current.kind == LookKind.crayon;
    return Semantics(
      button: true,
      label: player.playing ? 'Pause' : 'Play',
      child: InkWell(
        onTap: player.playing ? player.pause : player.play,
        customBorder: const CircleBorder(),
        child: Container(
          width: 68,
          height: 68,
          // Crayon: coloured in with the cover's crayon, ink edge, a hard
          // shadow. The others: paper on ink.
          decoration: crayon
              ? BoxDecoration(
                  color: AccentScope.of(context),
                  shape: BoxShape.circle,
                  border: Border.all(color: Tones.text, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: Looks.current.inkShadow,
                      offset: const Offset(3, 3),
                    ),
                  ],
                )
              : BoxDecoration(color: Tones.text, shape: BoxShape.circle),
          child: Icon(
            player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 38,
            // Ink on a crayon: every crayon in the box is light enough.
            color: crayon ? const Color(0xFF22201C) : Tones.base,
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
    required this.player,
    required this.track,
    required this.artUrlFor,
    required this.playing,
  });

  final TunePlayer player;
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
        // Crayon: the real cover, taped into the notebook a little crooked,
        // with a sticker on a liked song. (It used to be redrawn as line art
        // by a shader, which was ugly on real covers and upside down on
        // phones whose GPU did not need the flip it applied.) Elsewhere this
        // is the cover as it was.
        final crayon = Looks.current.kind == LookKind.crayon;
        final lit = DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: coverLift(
              AccentScope.of(context),
              alpha: 0.55,
              blur: 48,
              dy: 22,
              ink: 7,
            ),
          ),
          child: art,
        );
        final drawn = !crayon
            ? lit
            : Stack(
                clipBehavior: Clip.none,
                children: [
                  Transform.rotate(angle: -0.028, child: lit),
                  Positioned(
                    left: side * 0.05,
                    top: -12,
                    child: CrayonTape(
                      // The cover's crayon (cover_tint.dart), both pieces.
                      color: AccentScope.of(context),
                      angle: -0.24,
                      length: side * 0.23,
                    ),
                  ),
                  Positioned(
                    right: side * 0.03,
                    top: -10,
                    child: CrayonTape(
                      color: AccentScope.of(context),
                      angle: 0.19,
                      length: side * 0.23,
                    ),
                  ),
                  if (LikesScope.maybeOf(context)?.isLiked(track.sha) ?? false)
                    const Positioned(
                      right: -8,
                      bottom: -10,
                      child: _Sticker('a fave!'),
                    ),
                ],
              );
        // Off unless asked for, and off whenever the system asks for less
        // motion. A square sleeve turning for thirty seconds at a time is a
        // choice, not a default.
        final wanted = SettingsScope.maybeOf(context)?.animatedArtwork ?? false;
        if (!wanted || MediaQuery.disableAnimationsOf(context)) return drawn;
        return AnimatedRotation(
          turns: playing ? 1 : 0,
          duration: const Duration(seconds: 30),
          curve: Curves.linear,
          child: drawn,
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

/// What a double tap on the Now Playing cover does, by the listener's
/// setting: like the song (and say which way it went), or download it.
IconData? _doubleTap(BuildContext context, ManifestTrack track) {
  final settings = SettingsScope.maybeOf(context);
  if (settings?.doubleTapDownloads ?? false) {
    final downloads = DownloadScope.maybeOf(context);
    if (downloads == null) return null;
    if (downloads.store.pathFor(track.sha) != null) {
      return Icons.download_done_rounded;
    }
    downloads.enqueue(track.sha, artSha: track.artSha);
    return Icons.arrow_circle_down_rounded;
  }
  final likes = LikesScope.maybeOf(context);
  if (likes == null) return null;
  final nowLiked = !likes.isLiked(track.sha);
  if (nowLiked) ConfettiBurst.show(context);
  likes.toggle(track.sha);
  return nowLiked ? Icons.favorite_rounded : Icons.heart_broken_rounded;
}

/// The button beside the title: whichever action the double tap is not.
/// Liking by double tap puts the download here; downloading by double tap
/// keeps the heart. A small heart stays by the download so a liked song
/// still says so.
class _CoverActionButton extends StatelessWidget {
  const _CoverActionButton({required this.track});

  final ManifestTrack track;

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.maybeOf(context);
    final downloads = DownloadScope.maybeOf(context);
    if ((settings?.doubleTapDownloads ?? false) || downloads == null) {
      return LikeButton(sha: track.sha, size: 26);
    }
    final liked = LikesScope.maybeOf(context)?.isLiked(track.sha) ?? false;
    final offline = ReachabilityScope.maybeOf(context)?.offline ?? false;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (liked)
          Padding(
            padding: EdgeInsets.only(right: 2),
            child: Icon(
              Icons.favorite_rounded,
              size: 16,
              color: Tones.primary,
              semanticLabel: 'Liked',
            ),
          ),
        DownloadButton(
          sha: track.sha,
          title: track.title,
          store: downloads.store,
          offline: offline,
          onDownload: () => downloads.enqueue(track.sha, artSha: track.artSha),
        ),
      ],
    );
  }
}

/// A crayon sticker, tilted, with an ink edge and a hard shadow.
class _Sticker extends StatelessWidget {
  const _Sticker(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final look = Looks.current;
    return Transform.rotate(
      angle: 0.14,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: look.crayons[3],
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: look.text, width: 2),
          boxShadow: [
            BoxShadow(color: look.inkShadow, offset: const Offset(2, 2)),
          ],
        ),
        // Ink on the green in both modes: white on it was under 2.5:1.
        child: Text(
          text,
          style: TypeScale.caption.copyWith(
            color: const Color(0xFF22201C),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// "FLAC · 44.1 kHz · LOSSLESS": what Noir prints under the title.
String audioSpec(ManifestTrack t) {
  final codec = (t.codec ?? 'audio').toUpperCase();
  final lossless = const {'FLAC', 'ALAC', 'WAV', 'AIFF'}.contains(codec);
  final parts = [
    codec,
    if (t.sampleRate != null)
      '${(t.sampleRate! / 1000).toStringAsFixed(t.sampleRate! % 1000 == 0 ? 0 : 1)} kHz',
    if (!lossless && t.bitrate != null) '${(t.bitrate! / 1000).round()} kbps',
    if (lossless) 'LOSSLESS',
  ];
  return parts.join('  ·  ');
}

/// The sleep timer's time left, as a pill that opens the timer; otherwise
/// where the song is coming from.
class _SleepOrSource extends StatelessWidget {
  const _SleepOrSource({required this.source});

  final Widget source;

  @override
  Widget build(BuildContext context) {
    final sleep = SleepScope.maybeOf(context);
    if (sleep == null || !sleep.active) return source;
    final crayon = Looks.current.kind == LookKind.crayon;
    final left = sleep.remaining;
    final text = switch (sleep.mode) {
      SleepMode.timed => 'Sleeping in ${sleepClock(left ?? Duration.zero)}',
      SleepMode.endOfSong => 'Stopping after this song',
      SleepMode.endOfAlbum => 'Stopping after this album',
      SleepMode.off => '',
    };
    return Semantics(
      button: true,
      label: '$text. Sleep timer',
      child: Material(
        color: Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(
            color: crayon ? Tones.text : Tones.hairline,
            width: crayon ? 2 : 1,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => SleepSheet.show(context, sleep),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.bedtime_rounded,
                  size: 16,
                  color: crayon ? Looks.current.crayons[1] : Tones.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  text,
                  style: TypeScale.caption.copyWith(
                    color: Tones.text,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
