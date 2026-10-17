import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/download_store.dart';
import '../../core/data/manifest_store.dart';
import '../../core/data/queue_store.dart';
import '../../core/nav/nav_controller.dart';
import '../../core/theme/looks.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/artwork.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/cover_tint.dart';
import '../../core/data/download_manager.dart';
import '../../core/data/settings_store.dart';
import '../../core/ui/collection_download.dart';
import '../../core/ui/double_tap_cover.dart';
import '../../core/ui/download_button.dart';
import '../../core/ui/playing_bars.dart';
import '../../core/ui/shared_sleeve.dart';
import '../../core/ui/generated_artwork.dart';
import '../../domain/manifest.dart';
import '../artist/artist_page.dart';

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
      body: TintBuilder(
        artSha: release.artSha,
        builder: (context, tint) => _CollapseOnScroll(
          // About where the title leaves the screen under the bar: the cover,
          // the gap and the first line of the name.
          threshold: 290,
          builder: (context, controller, collapsed) => Stack(
            fit: StackFit.expand,
            children: [
              AmbientGlow(tint: tint, strength: 0.34),
              SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Once the cover and name have scrolled away, the bar says
                    // which record this is: a small sleeve, the title and the
                    // artist, and a play button, so a long tracklist never
                    // leaves you on a page with no name.
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      decoration: BoxDecoration(
                        color: collapsed
                            ? Color.alphaBlend(
                                tint.withValues(alpha: 0.10),
                                Tones.base,
                              ).withValues(alpha: 0.96)
                            : Colors.transparent,
                        border: Border(
                          bottom: BorderSide(
                            color: collapsed
                                ? Tones.hairline
                                : Colors.transparent,
                          ),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(
                        Space.xs,
                        Space.sm,
                        Space.sm,
                        Space.xs,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => NavScope.of(context).back(),
                            icon: Icon(
                              Icons.arrow_back_rounded,
                              color: Tones.textMuted,
                            ),
                          ),
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              // Built only once it is showing, so the hidden copy of the name
                              // is never a second thing to find or tap.
                              layoutBuilder: (current, previous) => Stack(
                                alignment: Alignment.centerLeft,
                                children: [...previous, ?current],
                              ),
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween(
                                        begin: const Offset(0, 0.25),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  ),
                              child: !collapsed
                                  ? const SizedBox.shrink()
                                  : GestureDetector(
                                      // Tapping the name goes back to the top,
                                      // like tapping a phone's status bar.
                                      onTap: () => controller.animateTo(
                                        0,
                                        duration: const Duration(
                                          milliseconds: 380,
                                        ),
                                        curve: Curves.easeOutCubic,
                                      ),
                                      child: Row(
                                        children: [
                                          Artwork(
                                            url: release.artSha == null
                                                ? null
                                                : artUrlFor(release.artSha!),
                                            artSha: release.artSha,
                                            size: 32,
                                            borderRadius: 6,
                                            fallback: GeneratedArtwork(
                                              title: release.title,
                                              artist: release.artist,
                                              size: 32,
                                              borderRadius: 6,
                                            ),
                                          ),
                                          const SizedBox(width: Space.sm),
                                          Expanded(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  release.title,
                                                  style: TypeScale.title
                                                      .copyWith(fontSize: 14),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  release.artist,
                                                  style: TypeScale.caption,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
                          ),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: collapsed
                                ? IconButton(
                                    tooltip: 'Play',
                                    onPressed: () =>
                                        player.playQueue(releaseTracks, 0),
                                    icon: Icon(
                                      Icons.play_circle_fill_rounded,
                                      color: Tones.text,
                                      size: 30,
                                    ),
                                  )
                                : const SizedBox(width: 48, height: 48),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(
                          Space.lg,
                          Space.sm,
                          Space.lg,
                          Space.lg,
                        ),
                        children: [
                          Center(
                            child: DoubleTapCover(
                              // Double tap to download the album, for whoever
                              // chose that in Settings; otherwise it does
                              // nothing here.
                              onDoubleTap: () => _downloadAlbumByTap(
                                context,
                                releaseTracks,
                                onDownload,
                              ),
                              child: SharedSleeve(
                                tag: 'album-${release.id}',
                                // Lit by its own colour, like the player's sleeve.
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: tint.withValues(alpha: 0.5),
                                        blurRadius: 44,
                                        spreadRadius: -8,
                                        offset: const Offset(0, 18),
                                      ),
                                    ],
                                  ),
                                  child: Artwork(
                                    url: release.artSha == null
                                        ? null
                                        : artUrlFor(release.artSha!),
                                    artSha: release.artSha,
                                    size: 220,
                                    borderRadius: 16,
                                    shared: true,
                                    fallback: GeneratedArtwork(
                                      title: release.title,
                                      artist: release.artist,
                                      size: 220,
                                      borderRadius: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: Space.lg),
                          Text(
                            release.title,
                            textAlign: TextAlign.center,
                            style: TypeScale.display.copyWith(fontSize: 32),
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
                              style: TypeScale.title.copyWith(color: tint),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: Space.xs),
                          _AlbumFacts(
                            release: release,
                            minutes: _totalMinutes(releaseTracks),
                          ),
                          const SizedBox(height: Space.lg),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FilledButton.icon(
                                onPressed: () =>
                                    player.playQueue(releaseTracks, 0),
                                icon: const Icon(
                                  Icons.play_arrow_rounded,
                                  size: 20,
                                ),
                                label: const Text('Play'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Tones.text,
                                  foregroundColor: Tones.base,
                                ),
                              ),
                              const SizedBox(width: Space.sm),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    player.shufflePlay(releaseTracks),
                                icon: const Icon(
                                  Icons.shuffle_rounded,
                                  size: 18,
                                ),
                                label: const Text('Shuffle'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Tones.text,
                                  side: BorderSide(color: Tones.hairline),
                                ),
                              ),
                              const SizedBox(width: Space.sm),
                              CollectionDownload(
                                noun: 'album',
                                tracks: releaseTracks,
                                store: store,
                                offline: offline,
                                onDownload: onDownload,
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
                              downloading: downloading.contains(
                                releaseTracks[i].sha,
                              ),
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
            ],
          ),
        ),
      ),
    );
  }
}

/// Owns the album page's scroll position and says whether it has gone past
/// [threshold], rebuilding only when that flips -- not every scrolled pixel.
class _CollapseOnScroll extends StatefulWidget {
  const _CollapseOnScroll({required this.threshold, required this.builder});

  final double threshold;
  final Widget Function(
    BuildContext context,
    ScrollController controller,
    bool collapsed,
  )
  builder;

  @override
  State<_CollapseOnScroll> createState() => _CollapseOnScrollState();
}

class _CollapseOnScrollState extends State<_CollapseOnScroll> {
  final _controller = ScrollController();
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final collapsed = _controller.offset > widget.threshold;
      if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _controller, _collapsed);
}

/// The facts about a record, said quietly: what and when on one line, how much
/// and how long on the next, with completeness as a small mark rather than more
/// words in the same breath. It was a single line of five things joined by dots,
/// which wrapped and read as one crowded sentence.
class _AlbumFacts extends StatelessWidget {
  const _AlbumFacts({required this.release, required this.minutes});

  final ManifestRelease release;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final owned = release.trackShas.length;
    final total = release.totalTracks;
    // Holding more of a release than it is supposed to contain means the
    // enriched total describes a different edition than the files do (one
    // library release has 35 tracks against a total of 22). Printing "35 of 22"
    // would assert a completeness we cannot vouch for, so say only what is here.
    final known = total != null && owned <= total;
    final complete = known && owned == total;
    final missing = known ? total - owned : 0;
    final year = release.year?.split('-').first ?? '—';

    final count = known && !complete
        ? '$owned of $total songs'
        : '$owned ${owned == 1 ? 'song' : 'songs'}';

    return Column(
      children: [
        Text(
          '${release.typeLabel.toUpperCase()}  ·  $year',
          style: TypeScale.mono.copyWith(letterSpacing: 1.4, fontSize: 11),
        ),
        const SizedBox(height: Space.xs + 2),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Space.sm,
          runSpacing: 2,
          children: [
            Text(
              count,
              style: TypeScale.mono.copyWith(color: Tones.text, fontSize: 13),
            ),
            Text('·', style: TypeScale.mono),
            Text(
              '$minutes min',
              style: TypeScale.mono.copyWith(color: Tones.text, fontSize: 13),
            ),
            if (complete)
              Icon(Icons.check_circle_rounded, size: 15, color: Tones.held)
            else if (missing > 0)
              Text(
                '$missing missing',
                style: TypeScale.mono.copyWith(color: Tones.warn, fontSize: 12),
              ),
          ],
        ),
      ],
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
        return PressRow(
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
                  child: active
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: PlayingBars(playing: player.playing),
                        )
                      : Looks.current.kind == LookKind.crayon
                      // Crayon: each number in a coloured dot, in turn.
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: 26,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color:
                                  Looks.current.crayons[(position - 1) %
                                      Looks.current.crayons.length],
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Looks.current.text,
                                width: 2,
                              ),
                            ),
                            child: Text(
                              '$position',
                              style: TypeScale.caption.copyWith(
                                color: const Color(0xFF22201C),
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        )
                      : Text(
                          track.discNumber != null && track.discNumber! > 1
                              ? '${track.discNumber}.${position.toString().padLeft(2, '0')}'
                              : position.toString().padLeft(2, '0'),
                          style: TypeScale.mono.copyWith(
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
                DownloadButton(
                  sha: track.sha,
                  title: track.title,
                  store: store,
                  offline: offline,
                  fallbackActive: downloading,
                  onDownload: onDownload,
                ),
                Text(track.durationLabel, style: TypeScale.mono),
              ],
            ),
          ),
        );
      },
    );
  }
}

IconData? _downloadAlbumByTap(
  BuildContext context,
  List<ManifestTrack> tracks,
  void Function(ManifestTrack) onDownload,
) {
  if (!(SettingsScope.maybeOf(context)?.doubleTapDownloads ?? false)) {
    return null;
  }
  final downloads = DownloadScope.maybeOf(context);
  final missing = [
    for (final t in tracks)
      if (downloads?.store.pathFor(t.sha) == null &&
          !(downloads?.isActive(t.sha) ?? false))
        t,
  ];
  if (missing.isEmpty) return Icons.download_done_rounded;
  for (final t in missing) {
    onDownload(t);
  }
  return Icons.arrow_circle_down_rounded;
}
