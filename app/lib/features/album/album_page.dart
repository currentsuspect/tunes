import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/download_store.dart';
import '../../core/data/manifest_store.dart';
import '../../core/data/queue_store.dart';
import '../../core/nav/nav_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/artwork.dart';
import '../../core/data/download_manager.dart';
import '../../core/ui/cover_tint.dart';
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
        builder: (context, tint) => Stack(
          fit: StackFit.expand,
          children: [
            AmbientGlow(tint: tint, strength: 0.34),
            SafeArea(
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
                        const Spacer(),
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
                              icon: const Icon(Icons.shuffle_rounded, size: 18),
                              label: const Text('Shuffle'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Tones.text,
                                side: const BorderSide(color: Tones.hairline),
                              ),
                            ),
                            const SizedBox(width: Space.sm),
                            _AlbumDownload(
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
    );
  }
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
              const Icon(
                Icons.check_circle_rounded,
                size: 15,
                color: Tones.held,
              )
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

/// Download the whole album, and say how it is going.
///
/// This was an outlined button that queued every track and then did nothing: the
/// rows underneath had their own state, but nothing on the button said anything
/// had started. It now shows the album as one: an arrow when none of it is on
/// the phone, a ring filling with the count while it comes down, and a green
/// tick when all of it is.
class _AlbumDownload extends StatelessWidget {
  const _AlbumDownload({
    required this.tracks,
    required this.store,
    required this.offline,
    required this.onDownload,
  });

  final List<ManifestTrack> tracks;
  final DownloadStore store;
  final bool offline;
  final void Function(ManifestTrack) onDownload;

  @override
  Widget build(BuildContext context) {
    final manager = DownloadScope.maybeOf(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final held = tracks.where((t) => store.pathFor(t.sha) != null).length;
        final total = tracks.length;
        final inFlight = manager == null
            ? 0
            : tracks.where((t) => manager.isActive(t.sha)).length;
        var partial = 0.0;
        if (manager != null) {
          for (final t in tracks) {
            final j = manager.jobFor(t.sha);
            if (j != null && j.phase == DownloadPhase.running) {
              partial += j.progress ?? 0;
            }
          }
        }
        final all = total > 0 && held == total;
        final working = inFlight > 0;
        final value = total == 0
            ? 0.0
            : ((held + partial) / total).clamp(0.0, 1.0);

        final Widget face;
        final String label;
        if (all) {
          face = const Icon(
            Icons.check_circle_rounded,
            key: ValueKey('all'),
            size: 22,
            color: Tones.held,
          );
          label = 'All $total songs are on this phone';
        } else if (working) {
          face = Stack(
            key: const ValueKey('working'),
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: value),
                  duration: const Duration(milliseconds: 220),
                  builder: (context, v, _) => CircularProgressIndicator(
                    value: v,
                    strokeWidth: 2.4,
                    color: Tones.primary,
                    backgroundColor: Tones.hairline,
                  ),
                ),
              ),
              Text('$held', style: TypeScale.mono.copyWith(fontSize: 9)),
            ],
          );
          label = 'Downloading, $held of $total done';
        } else {
          face = Icon(
            Icons.arrow_circle_down_outlined,
            key: const ValueKey('idle'),
            size: 22,
            color: offline ? Tones.hairline : Tones.text,
          );
          label = held == 0
              ? 'Download the album'
              : 'Download the other ${total - held} songs';
        }

        return Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: Tooltip(
            message: label,
            child: InkResponse(
              radius: 26,
              onTap: offline && !all
                  ? null
                  : () {
                      if (all) {
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            SnackBar(
                              content: Text(
                                'All $total songs are on this phone. Remove '
                                'them one at a time from the tick beside each.',
                              ),
                            ),
                          );
                        return;
                      }
                      for (final t in tracks) {
                        if (store.pathFor(t.sha) == null &&
                            !(manager?.isActive(t.sha) ?? false)) {
                          onDownload(t);
                        }
                      }
                    },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: all ? Tones.held : Tones.hairline),
                ),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutBack,
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: ScaleTransition(scale: a, child: child),
                    ),
                    child: face,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
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
                  child: active
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: PlayingBars(playing: player.playing),
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
