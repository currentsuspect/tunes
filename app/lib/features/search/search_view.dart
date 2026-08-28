import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/download_store.dart';
import '../../core/net/tunes_client.dart';
import '../../core/ui/initials.dart';
import '../../core/theme/tokens.dart';
import '../../domain/manifest.dart';
import '../library/library_widgets.dart';

class SearchView extends StatefulWidget {
  const SearchView({
    super.key,
    required this.tracks,
    required this.releases,
    required this.client,
    required this.player,
    required this.store,
    required this.downloading,
    required this.onDownload,
    required this.offline,
    required this.artUrlFor,
    this.onAlbumTap,
    this.onArtistTap,
    this.searchOverride,
  });

  final List<ManifestTrack> tracks;
  final List<ManifestRelease> releases;
  final TunesClient client;
  final TunePlayer player;
  final DownloadStore store;
  final Set<String> downloading;
  final void Function(ManifestTrack) onDownload;
  final bool offline;
  final String Function(String sha) artUrlFor;
  final void Function(ManifestRelease)? onAlbumTap;
  final void Function(String artist)? onArtistTap;
  final Future<SearchResults> Function(String query)? searchOverride;

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  SearchResults? _server;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() => _query = v);
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      setState(() => _server = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (widget.offline) return;
      try {
        final q = v.trim();
        final future =
            widget.searchOverride?.call(q) ?? widget.client.search(q);
        final results = await future;
        if (_controller.text.trim() != q) return;
        if (!mounted) return;
        setState(() => _server = results);
      } catch (_) {
        // box unreachable — fall back to the local filter
        if (!mounted) return;
        setState(() => _server = null);
      }
    });
  }

  List<ManifestTrack> _localResults(String q) {
    return widget.tracks
        .where(
          (t) =>
              t.title.toLowerCase().contains(q) ||
              t.artist.toLowerCase().contains(q) ||
              t.album.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final fromServer = _server != null;
    final local = q.isEmpty ? const <ManifestTrack>[] : _localResults(q);
    final results = fromServer ? _server!.tracks : local;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
          child: TextField(
            controller: _controller,
            autofocus: false,
            onChanged: _onChanged,
            style: TypeScale.body,
            decoration: InputDecoration(
              hintText: 'Search tracks, artists, albums',
              hintStyle: TypeScale.body,
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: Tones.textMuted,
                size: 20,
              ),
              filled: true,
              fillColor: Tones.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(RadiusTokens.control),
                borderSide: const BorderSide(color: Tones.hairline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(RadiusTokens.control),
                borderSide: const BorderSide(color: Tones.hairline),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: Space.sm),
            ),
          ),
        ),
        Expanded(
          child: q.isEmpty
              ? const Center(
                  child: Text(
                    'Search your library — results appear as you type.',
                    style: TypeScale.body,
                  ),
                )
              : results.isEmpty && !fromServer
              ? const Center(
                  child: Text('Nothing matches.', style: TypeScale.body),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.lg,
                    vertical: Space.md,
                  ),
                  children: [
                    if (results.isNotEmpty) ...[
                      const Text('Tracks', style: TypeScale.title),
                      const SizedBox(height: Space.sm),
                      for (var i = 0; i < results.length; i++) ...[
                        TrackRow(
                          track: results[i],
                          onTap: () => widget.player.playQueue(results, i),
                          player: widget.player,
                          store: widget.store,
                          downloading: widget.downloading.contains(
                            results[i].sha,
                          ),
                          onDownload: () => widget.onDownload(results[i]),
                          offline: widget.offline,
                          artUrlFor: widget.artUrlFor,
                        ),
                        const Divider(),
                      ],
                    ],
                    if (fromServer && _server!.externalArtists.isNotEmpty) ...[
                      const SizedBox(height: Space.md),
                      const Text(
                        'Artists on MusicBrainz',
                        style: TypeScale.title,
                      ),
                      const SizedBox(height: Space.sm),
                      for (final a in _server!.externalArtists) ...[
                        InkWell(
                          onTap: widget.onArtistTap == null
                              ? null
                              : () => widget.onArtistTap!(a.name),
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
                                InitialsAvatar(name: a.name, size: 44),
                                const SizedBox(width: Space.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        a.name,
                                        style: TypeScale.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        [
                                          if (a.type != null) a.type!,
                                          if (a.disambiguation != null)
                                            a.disambiguation!,
                                        ].join(' · '),
                                        style: TypeScale.caption,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.open_in_new_rounded,
                                  size: 16,
                                  color: Tones.textMuted,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Divider(),
                      ],
                    ],
                    if (fromServer) ...[
                      if (_server!.releases.isNotEmpty) ...[
                        const SizedBox(height: Space.md),
                        const Text('Albums', style: TypeScale.title),
                        const SizedBox(height: Space.sm),
                        for (final r in _server!.releases) ...[
                          InkWell(
                            onTap: widget.onAlbumTap == null
                                ? null
                                : () => widget.onAlbumTap!(r),
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
                                  ArtThumb(
                                    sha: r.artSha,
                                    artUrlFor: widget.artUrlFor,
                                    size: 44,
                                  ),
                                  const SizedBox(width: Space.md),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          r.title,
                                          style: TypeScale.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          '${r.artist} · ${r.trackShas.length}/${r.totalTracks ?? '?'} tracks',
                                          style: TypeScale.caption,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: Tones.textMuted,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Divider(),
                        ],
                      ],
                      if (_server!.artists.isNotEmpty) ...[
                        const SizedBox(height: Space.md),
                        const Text('Artists', style: TypeScale.title),
                        const SizedBox(height: Space.sm),
                        for (final a in _server!.artists) ...[
                          InkWell(
                            onTap: widget.onArtistTap == null
                                ? null
                                : () => widget.onArtistTap!(a.name),
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
                                  ArtThumb(
                                    sha: a.artSha,
                                    artUrlFor: widget.artUrlFor,
                                    size: 44,
                                  ),
                                  const SizedBox(width: Space.md),
                                  Expanded(
                                    child: Text(
                                      a.name,
                                      style: TypeScale.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: Tones.textMuted,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Divider(),
                        ],
                      ],
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}
