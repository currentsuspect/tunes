import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/platform/notifications.dart';
import '../../core/theme/tokens.dart';

class NowPlayingPage extends StatelessWidget {
  const NowPlayingPage({super.key, required this.player});

  final TunePlayer player;

  String _label(Duration d) {
    final s = d.inSeconds;
    final m = (s ~/ 60).toString().padLeft(2, '0');
    return '$m:${(s % 60).toString().padLeft(2, '0')}';
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

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.sm,
                    Space.sm,
                    Space.sm,
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
                      const Text('Now Playing', style: TypeScale.caption),
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
                              child: const Icon(
                                Icons.music_note_rounded,
                                size: 72,
                                color: Tones.textMuted,
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    Space.sm,
                    Space.lg,
                    Space.xs,
                  ),
                  child: Text('Up next', style: TypeScale.caption),
                ),
                Expanded(
                  flex: 4,
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
                          unawaited(requestNotificationPermissionIfNeeded());
                          player.playAt(i);
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
                                (i + 1).toString().padLeft(2, '0'),
                                style: TypeScale.caption.copyWith(
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                  color: isCurrent
                                      ? Tones.primary
                                      : Tones.textMuted,
                                ),
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
                              if (isCurrent)
                                const Icon(
                                  Icons.graphic_eq_rounded,
                                  size: 18,
                                  color: Tones.primary,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
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
