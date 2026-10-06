import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/sync/now_sync.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/artwork.dart';
import '../../core/ui/generated_artwork.dart';
import '../../domain/manifest.dart';

/// "Playing on Laptop" -- where the listener's music is on another device, with
/// one button to carry on here from the same second.
///
/// Absent when there is nothing to say: no other device has played, this
/// device is already playing, or what was playing is not in this library.
class ContinueCard extends StatelessWidget {
  const ContinueCard({
    super.key,
    required this.remote,
    required this.player,
    required this.manifest,
    required this.serverNow,
    required this.onContinue,
  });

  final RemoteNow remote;
  final TunePlayer player;
  final TunesManifest manifest;

  /// The server's clock in ms, as this device believes it to be.
  final int Function() serverNow;

  /// Plays [tracks] from [index], [at] this far in.
  final void Function(List<ManifestTrack> tracks, int index, Duration at)
  onContinue;

  /// Older than this and it is history, not where the listener is.
  static const _stale = Duration(days: 7);

  ManifestTrack? _find(String? sha) {
    if (sha == null) return null;
    for (final t in manifest.tracks) {
      if (t.sha == sha) return t;
    }
    return null;
  }

  void _continue() {
    final shas = remote.queueToContinue;
    final byId = {for (final t in manifest.tracks) t.sha: t};
    final tracks = [
      for (final s in shas)
        if (byId[s] != null) byId[s]!,
    ];
    if (tracks.isEmpty) return;
    var index = tracks.indexWhere((t) => t.sha == remote.sha);
    if (index < 0) index = 0;
    onContinue(tracks, index, remote.estimatedPosition(serverNow()));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([remote, player]),
      builder: (context, _) {
        // While this device is showing the other one's music there is nothing to
        // continue: it is already on screen.
        if (!remote.hasState ||
            player.playing ||
            player.remoteDeviceLabel != null) {
          return const SizedBox.shrink();
        }
        final now = serverNow();
        if (now - remote.updatedAt > _stale.inMilliseconds) {
          return const SizedBox.shrink();
        }
        final track = _find(remote.sha);
        if (track == null) return const SizedBox.shrink();
        final live = remote.isLive(now);
        final at = remote.estimatedPosition(now);
        final label = (remote.deviceLabel ?? 'another device').toUpperCase();
        final accent = Theme.of(context).colorScheme.primary;
        return Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
          child: Material(
            color: Tones.surfaceRaised,
            borderRadius: BorderRadius.circular(RadiusTokens.card),
            child: InkWell(
              borderRadius: BorderRadius.circular(RadiusTokens.card),
              onTap: _continue,
              child: Padding(
                padding: const EdgeInsets.all(Space.md),
                child: Row(
                  children: [
                    Artwork(
                      url: null,
                      artSha: track.artSha,
                      size: 56,
                      borderRadius: 10,
                      fallback: GeneratedArtwork.fromTrack(
                        track,
                        size: 56,
                        borderRadius: 10,
                      ),
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (live) ...[
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: accent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Flexible(
                                child: Text(
                                  live
                                      ? 'PLAYING ON $label'
                                      : 'LAST PLAYED ON $label',
                                  style: TypeScale.mono.copyWith(
                                    fontSize: 10,
                                    color: live ? accent : Tones.textMuted,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            track.title,
                            style: TypeScale.display.copyWith(
                              fontSize: 18,
                              height: 1.15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${track.artistDisplay} · ${_clock(at)}',
                            style: TypeScale.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    FilledButton(
                      onPressed: _continue,
                      style: FilledButton.styleFrom(
                        backgroundColor: Tones.text,
                        foregroundColor: Tones.base,
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.md,
                        ),
                      ),
                      child: const Text('Continue here'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static String _clock(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s in';
  }
}
