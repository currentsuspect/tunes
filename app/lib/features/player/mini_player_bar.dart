import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/theme/tokens.dart';

class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({
    super.key,
    required this.player,
    required this.onTap,
    this.artUrlFor,
  });

  final TunePlayer player;
  final VoidCallback onTap;
  final String Function(String sha)? artUrlFor;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final current = player.current;
        if (current == null) return const SizedBox.shrink();
        return InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(
              Space.md,
              Space.sm,
              Space.md,
              Space.sm,
            ),
            decoration: const BoxDecoration(
              color: Tones.surface,
              border: Border(top: BorderSide(color: Tones.hairline)),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: current.artSha != null && artUrlFor != null
                      ? Image.network(
                          artUrlFor!(current.artSha!),
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const _MiniArtPlaceholder(),
                        )
                      : const _MiniArtPlaceholder(),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        current.title,
                        style: TypeScale.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        current.artist,
                        style: TypeScale.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: player.toggle,
                  icon: Icon(
                    player.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 30,
                    color: Tones.primary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MiniArtPlaceholder extends StatelessWidget {
  const _MiniArtPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      color: Tones.surfaceRaised,
      child: const Icon(
        Icons.music_note_rounded,
        size: 18,
        color: Tones.textMuted,
      ),
    );
  }
}
