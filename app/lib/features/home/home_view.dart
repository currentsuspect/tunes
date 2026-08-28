import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/ui/initials.dart';
import '../../domain/manifest.dart';
import '../library/library_widgets.dart';

class HomeView extends StatelessWidget {
  const HomeView({
    super.key,
    required this.manifest,
    required this.recents,
    required this.onArtistTap,
    required this.onAlbumTap,
    required this.onPlay,
    required this.artUrlFor,
  });

  final TunesManifest manifest;
  final List<ManifestTrack> recents;
  final void Function(String artist) onArtistTap;
  final void Function(ManifestRelease release) onAlbumTap;
  final void Function(List<ManifestTrack> tracks, int index) onPlay;
  final String Function(String sha) artUrlFor;

  @override
  Widget build(BuildContext context) {
    final tracks = manifest.tracks;
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
    for (final t in tracks) {
      artists.putIfAbsent(t.artist, () => []).add(t);
    }
    final artistList = artists.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    final releases = manifest.releases;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.md,
        Space.lg,
        Space.lg,
      ),
      children: [
        Text(
          '${tracks.length} ${tracks.length == 1 ? 'track' : 'tracks'} · '
          '${artists.length} ${artists.length == 1 ? 'artist' : 'artists'} · '
          '${releases.length} ${releases.length == 1 ? 'release' : 'releases'}',
          style: TypeScale.caption,
        ),
        const SizedBox(height: Space.lg),
        const Text('Artists', style: TypeScale.title),
        const SizedBox(height: Space.sm),
        SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: artistList.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.md),
            itemBuilder: (context, i) {
              final e = artistList[i];
              final artSha = manifest.artistArt(e.key);
              return InkWell(
                onTap: () => onArtistTap(e.key),
                borderRadius: BorderRadius.circular(RadiusTokens.control),
                child: SizedBox(
                  width: 76,
                  child: Column(
                    children: [
                      if (artSha != null)
                        ClipOval(
                          child: SizedBox(
                            width: 64,
                            height: 64,
                            child: Image.network(
                              artUrlFor(artSha),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  InitialsAvatar(name: e.key, size: 64),
                            ),
                          ),
                        )
                      else
                        InitialsAvatar(name: e.key, size: 64),
                      const SizedBox(height: Space.xs),
                      Text(
                        e.key,
                        style: TypeScale.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: Space.lg),
        const Text('Albums', style: TypeScale.title),
        const SizedBox(height: Space.sm),
        SizedBox(
          height: 178,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: releases.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.md),
            itemBuilder: (context, i) {
              final r = releases[i];
              return InkWell(
                onTap: () => onAlbumTap(r),
                borderRadius: BorderRadius.circular(RadiusTokens.card),
                child: SizedBox(
                  width: 130,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(RadiusTokens.card),
                        child: SizedBox(
                          width: 130,
                          height: 130,
                          child: r.artSha != null
                              ? Image.network(
                                  artUrlFor(r.artSha!),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      const ArtPlaceholder(size: 130),
                                )
                              : const ArtPlaceholder(size: 130),
                        ),
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        r.title,
                        style: TypeScale.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${r.artist} · ${r.trackShas.length} ${r.trackShas.length == 1 ? 'track' : 'tracks'}',
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
