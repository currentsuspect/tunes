import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/artwork.dart';
import '../../core/ui/generated_artwork.dart';
import '../../core/ui/like_button.dart';
import '../player/scrubber.dart';

/// The desktop player: always at the foot of the window, in three parts.
/// What is playing on the left, the transport and a seek bar in the middle,
/// and the extras (where the sound is, queue, volume) on the right.
class DesktopPlayBar extends StatefulWidget {
  const DesktopPlayBar({
    super.key,
    required this.player,
    required this.artUrlFor,
    required this.onOpenNowPlaying,
    required this.onQueue,
    required this.statusBuilder,
    this.volume = 1,
    this.onVolume,
  });

  /// The level to start at, and told when it changes so it can be kept.
  final double volume;
  final ValueChanged<double>? onVolume;

  final TunePlayer player;
  final String Function(String sha) artUrlFor;
  final VoidCallback onOpenNowPlaying;
  final VoidCallback? onQueue;

  /// The small "streaming / saved / playing on phone" label for the current
  /// track, built by whoever knows the connection and downloads.
  final Widget Function(BuildContext context) statusBuilder;

  static const height = 112.0;

  @override
  State<DesktopPlayBar> createState() => _DesktopPlayBarState();
}

class _DesktopPlayBarState extends State<DesktopPlayBar> {
  late double _volume = widget.volume;
  double _beforeMute = 1;

  @override
  void initState() {
    super.initState();
    // Put back the level the listener left it at.
    widget.player.setVolume(_volume);
  }

  void _setVolume(double v) {
    setState(() => _volume = v.clamp(0, 1));
    widget.player.setVolume(_volume);
    widget.onVolume?.call(_volume);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: DesktopPlayBar.height,
      decoration: const BoxDecoration(
        color: Tones.base,
        border: Border(top: BorderSide(color: Tones.hairline)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Space.md),
      child: ListenableBuilder(
        listenable: widget.player,
        builder: (context, _) {
          final p = widget.player;
          final track = p.current;
          return Row(
            children: [
              Expanded(
                flex: 3,
                child: track == null
                    ? const SizedBox.shrink()
                    : _NowPlayingCell(
                        player: p,
                        artUrlFor: widget.artUrlFor,
                        onTap: widget.onOpenNowPlaying,
                      ),
              ),
              Expanded(
                flex: 4,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Transport(player: p),
                        if (track != null)
                          SizedBox(
                            height: 58,
                            child: Scrubber(
                              player: p,
                              duration: p.duration > Duration.zero
                                  ? p.duration
                                  : Duration(
                                      milliseconds: track.durationMs ?? 0,
                                    ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (track != null) widget.statusBuilder(context),
                    const SizedBox(width: Space.sm),
                    if (widget.onQueue != null)
                      IconButton(
                        tooltip: 'Queue',
                        onPressed: widget.onQueue,
                        icon: const Icon(
                          Icons.queue_music_rounded,
                          color: Tones.textMuted,
                        ),
                      ),
                    IconButton(
                      tooltip: _volume == 0 ? 'Unmute' : 'Mute',
                      onPressed: () {
                        if (_volume == 0) {
                          _setVolume(_beforeMute == 0 ? 1 : _beforeMute);
                        } else {
                          _beforeMute = _volume;
                          _setVolume(0);
                        }
                      },
                      icon: Icon(
                        _volume == 0
                            ? Icons.volume_off_rounded
                            : _volume < 0.5
                            ? Icons.volume_down_rounded
                            : Icons.volume_up_rounded,
                        color: Tones.textMuted,
                      ),
                    ),
                    SizedBox(
                      width: 110,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: SliderComponentShape.noOverlay,
                          activeTrackColor: Tones.text,
                          inactiveTrackColor: Tones.hairline,
                          thumbColor: Tones.text,
                        ),
                        child: Slider(value: _volume, onChanged: _setVolume),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NowPlayingCell extends StatelessWidget {
  const _NowPlayingCell({
    required this.player,
    required this.artUrlFor,
    required this.onTap,
  });

  final TunePlayer player;
  final String Function(String sha) artUrlFor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final track = player.current!;
    return Row(
      children: [
        // The cover and the names open Now Playing together.
        Expanded(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Row(
                children: [
                  Artwork(
                    url: track.artSha == null ? null : artUrlFor(track.artSha!),
                    artSha: track.artSha,
                    size: 60,
                    borderRadius: 8,
                    fallback: GeneratedArtwork.fromTrack(
                      track,
                      size: 60,
                      borderRadius: 8,
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TypeScale.title.copyWith(fontSize: 14),
                        ),
                        Text(
                          track.artistDisplay,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TypeScale.caption,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        LikeButton(sha: track.sha),
      ],
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({required this.player});
  final TunePlayer player;

  @override
  Widget build(BuildContext context) {
    final on = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Shuffle',
          onPressed: () => player.setShuffle(!player.shuffle),
          icon: Icon(
            Icons.shuffle_rounded,
            size: 20,
            color: player.shuffle ? on : Tones.textMuted,
          ),
        ),
        IconButton(
          tooltip: 'Previous',
          onPressed: player.previous,
          icon: const Icon(Icons.skip_previous_rounded, color: Tones.text),
        ),
        const SizedBox(width: 4),
        Material(
          color: Tones.text,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: player.toggle,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Tones.base,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Next',
          onPressed: player.next,
          icon: const Icon(Icons.skip_next_rounded, color: Tones.text),
        ),
        IconButton(
          tooltip: 'Repeat',
          onPressed: () => player.setRepeat(switch (player.repeat) {
            PlaybackRepeat.off => PlaybackRepeat.all,
            PlaybackRepeat.all => PlaybackRepeat.one,
            PlaybackRepeat.one => PlaybackRepeat.off,
          }),
          icon: Icon(
            player.repeat == PlaybackRepeat.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            size: 20,
            color: player.repeat == PlaybackRepeat.off ? Tones.textMuted : on,
          ),
        ),
      ],
    );
  }
}
