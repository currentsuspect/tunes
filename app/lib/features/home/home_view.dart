import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../domain/manifest.dart';
import '../library/library_widgets.dart';

class HomeView extends StatelessWidget {
  const HomeView({
    super.key,
    required this.tracks,
    required this.recents,
    required this.onArtistTap,
    required this.onAlbumTap,
    required this.onPlay,
    required this.artUrlFor,
  });

  final List<ManifestTrack> tracks;
  final List<ManifestTrack> recents;
  final void Function(String artist) onArtistTap;
  final void Function(String album, String artist) onAlbumTap;
  final void Function(List<ManifestTrack> tracks, int index) onPlay;
  final String Function(String sha) artUrlFor;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(Space.lg),
          child: Text(
            'No library yet — channels are configured, content appears '
            'here as tunesd fetches it.',
            textAlign: TextAlign.center,
            style: TypeScale.body,
          ),
        ),
      );
    }

    final artists = <String, List<ManifestTrack>>{};
    final albums = <String, List<ManifestTrack>>{};
    for (final t in tracks) {
      artists.putIfAbsent(t.artist, () => []).add(t);
      albums.putIfAbsent('${t.artist}\u0000${t.album}', () => []).add(t);
    }
    final topArtists = artists.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    final albumEntries = albums.entries.toList()
      ..sort((a, b) => a.value.first.album.compareTo(b.value.first.album));

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.md,
        Space.lg,
        Space.lg,
      ),
      children: [
        Row(
          children: [
            _Stat(label: '${tracks.length}', caption: 'tracks'),
            const SizedBox(width: Space.lg),
            _Stat(label: '${artists.length}', caption: 'artists'),
            const SizedBox(width: Space.lg),
            _Stat(label: '${albums.length}', caption: 'albums'),
          ],
        ),
        const SizedBox(height: Space.lg),
        const Text('Artists', style: TypeScale.title),
        const SizedBox(height: Space.sm),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            for (final e in topArtists.take(10))
              ActionChip(
                label: Text(e.key, style: TypeScale.body),
                backgroundColor: Tones.surfaceRaised,
                side: const BorderSide(color: Tones.hairline),
                onPressed: () => onArtistTap(e.key),
              ),
          ],
        ),
        const SizedBox(height: Space.lg),
        const Text('Albums', style: TypeScale.title),
        const SizedBox(height: Space.sm),
        SizedBox(
          height: 170,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: albumEntries.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.md),
            itemBuilder: (context, i) {
              final e = albumEntries[i];
              final first = e.value.first;
              return InkWell(
                onTap: () => onAlbumTap(first.album, first.artist),
                borderRadius: BorderRadius.circular(RadiusTokens.card),
                child: SizedBox(
                  width: 120,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(RadiusTokens.card),
                        child: SizedBox(
                          width: 120,
                          height: 120,
                          child: first.artSha != null
                              ? Image.network(
                                  artUrlFor(first.artSha!),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      const ArtPlaceholder(size: 120),
                                )
                              : const ArtPlaceholder(size: 120),
                        ),
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        first.album,
                        style: TypeScale.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${first.artist} · ${e.value.length}',
                        style: TypeScale.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (recents.isNotEmpty) ...[
          const SizedBox(height: Space.lg),
          const Text('Recently played', style: TypeScale.title),
          const SizedBox(height: Space.sm),
          for (final t in recents.take(5))
            InkWell(
              onTap: () => onPlay(recents, recents.indexOf(t)),
              borderRadius: BorderRadius.circular(RadiusTokens.control),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: Space.sm,
                  horizontal: Space.xs,
                ),
                child: Row(
                  children: [
                    ArtThumb(sha: t.artSha, artUrlFor: artUrlFor),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.title,
                            style: TypeScale.title,
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
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.caption});

  final String label;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TypeScale.wordmark.copyWith(
            fontSize: 28,
            color: Tones.primary,
          ),
        ),
        Text(caption, style: TypeScale.caption),
      ],
    );
  }
}
