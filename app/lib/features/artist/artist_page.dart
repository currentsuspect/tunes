import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/download_store.dart';
import '../../core/data/manifest_store.dart';
import '../../core/data/queue_store.dart';
import '../../core/nav/nav_controller.dart';
import '../../core/net/tunes_client.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/artwork.dart';
import '../../core/ui/shared_sleeve.dart';
import '../../core/ui/initials.dart';
import '../../domain/discography.dart';
import '../../domain/manifest.dart';
import '../album/album_page.dart';
import '../now_playing/now_playing_page.dart';
import '../library/library_widgets.dart';
import '../player/mini_player_bar.dart';

class ArtistPage extends StatefulWidget {
  const ArtistPage({
    super.key,
    required this.artist,
    required this.manifest,
    this.client,
    required this.player,
    required this.store,
    required this.downloading,
    required this.onDownload,
    required this.offline,
    required this.artUrlFor,
    required this.manifestStore,
    this.queueStore,
  });

  final String artist;
  final TunesManifest manifest;
  final TunesClient? client;
  final TunePlayer player;
  final DownloadStore store;
  final Set<String> downloading;
  final void Function(ManifestTrack) onDownload;
  final bool offline;
  final String Function(String sha) artUrlFor;
  final ManifestStore manifestStore;
  final QueueStore? queueStore;

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  ArtistDiscography? _discography;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.offline) return;
    final client = widget.client;
    if (client == null) return;
    setState(() => _loading = true);
    try {
      final d = await client.discography(widget.artist);
      if (!mounted) return;
      setState(() => _discography = d);
    } catch (_) {
      // box unreachable — the owned section still renders
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final artist = widget.artist;
    // Match the act, not the raw credit line, so a collaboration still shows
    // under its lead. A track where this artist is a guest counts too.
    final tracks = widget.manifest.tracks
        .where((t) => t.artistKey == artist || t.featured.contains(artist))
        .toList();
    final releases = widget.manifest.releasesFor(artist);
    final d = _discography;
    final missing = <DiscographyGroup>[
      if (d != null) ...d.groups.where((g) => !g.owned),
    ]..sort((a, b) => (b.year ?? '').compareTo(a.year ?? ''));
    final ownedCount = d == null ? 0 : d.groups.where((g) => g.owned).length;

    return Scaffold(
      body: SafeArea(
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
                  const Expanded(
                    child: Text('Artist', style: TypeScale.caption),
                  ),
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
                    child: () {
                      final photo = widget.manifest.artistArt(artist);
                      return SharedSleeve(
                        tag: 'artist-$artist',
                        child: Artwork(
                          url: photo == null ? null : widget.artUrlFor(photo),
                          artSha: photo,
                          size: 140,
                          borderRadius: 70,
                          shared: true,
                          fallback: InitialsAvatar(name: artist, size: 140),
                        ),
                      );
                    }(),
                  ),
                  const SizedBox(height: Space.lg),
                  Text(
                    artist,
                    textAlign: TextAlign.center,
                    style: TypeScale.wordmark,
                  ),
                  if (tracks.isNotEmpty) ...[
                    const SizedBox(height: Space.xs),
                    Text(
                      '${tracks.length} ${tracks.length == 1 ? 'track' : 'tracks'} · ${releases.length} ${releases.length == 1 ? 'release' : 'releases'}',
                      textAlign: TextAlign.center,
                      style: TypeScale.body,
                    ),
                    const SizedBox(height: Space.lg),
                    FilledButton.icon(
                      onPressed: () => widget.player.playQueue(tracks, 0),
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: const Text('Play all'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Tones.primary,
                        foregroundColor: Tones.onPrimary,
                      ),
                    ),
                  ],
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(Space.lg),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else if (d != null && d.groups.isNotEmpty) ...[
                    const SizedBox(height: Space.lg),
                    Text(
                      'Discography · $ownedCount of ${d.groups.length} in your library',
                      style: TypeScale.title,
                    ),
                    const SizedBox(height: Space.sm),
                    if (missing.isEmpty)
                      Text(
                        'Complete — everything in your library.',
                        style: TypeScale.caption,
                      )
                    else
                      for (final g in missing) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: Space.sm,
                            horizontal: Space.xs,
                          ),
                          child: Row(
                            children: [
                              Opacity(
                                opacity: 0.45,
                                child: ArtThumb(
                                  sha: null,
                                  artUrlFor: widget.artUrlFor,
                                  size: 48,
                                  title: g.title,
                                  artist: widget.artist,
                                ),
                              ),
                              const SizedBox(width: Space.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      g.title,
                                      style: TypeScale.title.copyWith(
                                        color: Tones.textMuted,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      '${g.typeLabel} · ${g.year ?? '—'}',
                                      style: TypeScale.caption,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: Space.sm),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: Space.sm,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Tones.surfaceRaised,
                                  borderRadius: BorderRadius.circular(
                                    RadiusTokens.control,
                                  ),
                                  border: Border.all(color: Tones.hairline),
                                ),
                                child: Text(
                                  'not in library',
                                  style: TypeScale.caption.copyWith(
                                    color: Tones.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (g != missing.last) const Divider(),
                      ],
                  ],
                  const SizedBox(height: Space.lg),
                  for (final r in releases) ...[
                    _ReleaseCard(
                      release: r,
                      manifest: widget.manifest,
                      artUrlFor: widget.artUrlFor,
                      onTap: () => NavScope.of(context).openPanel(
                        TunesPanels.album(r.id),
                        () => AlbumPage(
                          release: r,
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
                      ),
                    ),
                    const SizedBox(height: Space.md),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: MiniPlayerBar(
        player: widget.player,
        onTap: () => NavScope.of(context).openPanel(
          TunesPanels.nowPlaying,
          () => NowPlayingPage(
            player: widget.player,
            manifest: widget.manifest,
            store: widget.store,
            downloading: widget.downloading,
            onDownload: widget.onDownload,
            offline: widget.offline,
            artUrlFor: widget.artUrlFor,
            manifestStore: widget.manifestStore,
            queueStore: widget.queueStore,
          ),
        ),
        artUrlFor: widget.artUrlFor,
      ),
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({
    required this.release,
    required this.manifest,
    required this.artUrlFor,
    required this.onTap,
  });

  final ManifestRelease release;
  final TunesManifest manifest;
  final String Function(String sha) artUrlFor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(RadiusTokens.card),
      child: Row(
        children: [
          ArtThumb(
            sha: release.artSha,
            artUrlFor: artUrlFor,
            size: 56,
            title: release.title,
            artist: release.artist,
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  release.title,
                  style: TypeScale.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${release.typeLabel} · ${release.year ?? '—'} · ${release.trackShas.length} ${release.trackShas.length == 1 ? 'track' : 'tracks'}',
                  style: TypeScale.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Tones.textMuted),
        ],
      ),
    );
  }
}
