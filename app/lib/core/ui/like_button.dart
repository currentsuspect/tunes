import 'package:flutter/material.dart';

import '../data/likes_store.dart';
import '../theme/tokens.dart';

/// The heart, wherever a track appears.
///
/// Reads the store through the scope rather than taking a value, so every
/// heart in the app agrees the moment one of them is tapped -- liking from
/// the player has to fill the heart on the list row behind it.
///
/// Renders nothing at all when no [LikesScope] is above it. That is not a
/// silent failure: a widget test that pumps a row on its own has no store,
/// and a heart that cannot record anything is worse than no heart.
class LikeButton extends StatelessWidget {
  const LikeButton({
    super.key,
    required this.sha,
    this.size = 22,
    this.padding = const EdgeInsets.all(Space.sm),
  });

  final String sha;
  final double size;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final likes = LikesScope.maybeOf(context);
    if (likes == null) return const SizedBox.shrink();
    final liked = likes.isLiked(sha);
    return IconButton(
      onPressed: () => likes.toggle(sha),
      padding: padding,
      constraints: const BoxConstraints(),
      iconSize: size,
      visualDensity: VisualDensity.compact,
      tooltip: liked ? 'Remove from liked' : 'Like',
      icon: Icon(
        liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        color: liked ? Tones.primary : Tones.textMuted,
        size: size,
      ),
    );
  }
}
