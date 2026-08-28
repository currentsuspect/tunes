import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/download_store.dart';
import '../../core/theme/tokens.dart';
import '../../domain/manifest.dart';
import '../library/library_widgets.dart';

class SearchView extends StatefulWidget {
  const SearchView({
    super.key,
    required this.tracks,
    required this.player,
    required this.store,
    required this.downloading,
    required this.onDownload,
    required this.offline,
    required this.artUrlFor,
  });

  final List<ManifestTrack> tracks;
  final TunePlayer player;
  final DownloadStore store;
  final Set<String> downloading;
  final void Function(ManifestTrack) onDownload;
  final bool offline;
  final String Function(String sha) artUrlFor;

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final results = q.isEmpty
        ? const <ManifestTrack>[]
        : widget.tracks
              .where(
                (t) =>
                    t.title.toLowerCase().contains(q) ||
                    t.artist.toLowerCase().contains(q) ||
                    t.album.toLowerCase().contains(q),
              )
              .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
          child: TextField(
            controller: _controller,
            autofocus: false,
            onChanged: (v) => setState(() => _query = v),
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
              : results.isEmpty
              ? const Center(
                  child: Text('Nothing matches.', style: TypeScale.body),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.lg,
                    vertical: Space.md,
                  ),
                  itemCount: results.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, i) {
                    final t = results[i];
                    return TrackRow(
                      track: t,
                      onTap: () => widget.player.playQueue(results, i),
                      player: widget.player,
                      store: widget.store,
                      downloading: widget.downloading.contains(t.sha),
                      onDownload: () => widget.onDownload(t),
                      offline: widget.offline,
                      artUrlFor: widget.artUrlFor,
                    );
                  },
                ),
        ),
      ],
    );
  }
}
