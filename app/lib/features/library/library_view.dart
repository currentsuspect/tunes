import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/download_store.dart';
import '../../core/theme/tokens.dart';
import '../../domain/manifest.dart';
import 'library_widgets.dart';

class LibraryView extends StatefulWidget {
  const LibraryView({
    super.key,
    required this.tracks,
    required this.filter,
    required this.player,
    required this.store,
    required this.downloading,
    required this.onDownload,
    required this.offline,
    required this.artUrlFor,
  });

  final List<ManifestTrack> tracks;
  final String filter;
  final TunePlayer player;
  final DownloadStore store;
  final Set<String> downloading;
  final void Function(ManifestTrack) onDownload;
  final bool offline;
  final String Function(String sha) artUrlFor;

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  int _segment = 0;

  List<ManifestTrack> get _filtered {
    final f = widget.filter.trim().toLowerCase();
    if (f.isEmpty) return widget.tracks;
    return widget.tracks
        .where(
          (t) =>
              t.title.toLowerCase().contains(f) ||
              t.artist.toLowerCase().contains(f) ||
              t.album.toLowerCase().contains(f),
        )
        .toList();
  }

  void _play(List<ManifestTrack> list, int index) {
    widget.player.playQueue(list, index);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.md,
            Space.lg,
            Space.xs,
          ),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Tracks')),
              ButtonSegment(value: 1, label: Text('Albums')),
              ButtonSegment(value: 2, label: Text('Artists')),
            ],
            selected: {_segment},
            onSelectionChanged: (s) => setState(() => _segment = s.first),
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(TypeScale.body),
            ),
          ),
        ),
        Expanded(child: _buildBody(filtered)),
      ],
    );
  }

  Widget _buildBody(List<ManifestTrack> filtered) {
    if (filtered.isEmpty) {
      return const _Message(
        icon: Icons.music_note_outlined,
        title: 'Nothing matches',
        body: 'The library is empty or nothing matched the filter.',
      );
    }
    if (_segment == 0) {
      return ListView.separated(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        itemCount: filtered.length,
        separatorBuilder: (_, _) => const Divider(),
        itemBuilder: (context, i) {
          final t = filtered[i];
          return TrackRow(
            track: t,
            onTap: () => _play(filtered, i),
            store: widget.store,
            downloading: widget.downloading.contains(t.sha),
            onDownload: () => widget.onDownload(t),
            offline: widget.offline,
            artUrlFor: widget.artUrlFor,
          );
        },
      );
    }
    if (_segment == 1) {
      final albums = <String, List<ManifestTrack>>{};
      for (final t in filtered) {
        albums.putIfAbsent('${t.artist}\u0000${t.album}', () => []).add(t);
      }
      final entries = albums.entries.toList()
        ..sort((a, b) => a.value.first.album.compareTo(b.value.first.album));
      return GridView.builder(
        padding: const EdgeInsets.all(Space.lg),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          childAspectRatio: 0.78,
          mainAxisSpacing: Space.lg,
          crossAxisSpacing: Space.md,
        ),
        itemCount: entries.length,
        itemBuilder: (context, i) {
          final tracks = entries[i].value;
          final first = tracks.first;
          return InkWell(
            onTap: () => _play(tracks, 0),
            borderRadius: BorderRadius.circular(RadiusTokens.card),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(RadiusTokens.card),
                    child: SizedBox.expand(
                      child: first.artSha != null
                          ? Image.network(
                              widget.artUrlFor(first.artSha!),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const ArtPlaceholder(size: 200),
                            )
                          : const ArtPlaceholder(size: 200),
                    ),
                  ),
                ),
                const SizedBox(height: Space.xs),
                Text(
                  first.album,
                  style: TypeScale.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${first.artist} · ${tracks.length}',
                  style: TypeScale.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        },
      );
    }
    final artists = <String, List<ManifestTrack>>{};
    for (final t in filtered) {
      artists.putIfAbsent(t.artist, () => []).add(t);
    }
    final entries = artists.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return ListView.separated(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, i) {
        final name = entries[i].key;
        final tracks = entries[i].value;
        final art = tracks.firstWhere(
          (t) => t.artSha != null,
          orElse: () => tracks.first,
        );
        return InkWell(
          onTap: () => _play(tracks, 0),
          borderRadius: BorderRadius.circular(RadiusTokens.control),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: Space.sm,
              horizontal: Space.xs,
            ),
            child: Row(
              children: [
                ArtThumb(sha: art.artSha, artUrlFor: widget.artUrlFor),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TypeScale.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${tracks.length} ${tracks.length == 1 ? 'track' : 'tracks'}',
                        style: TypeScale.body,
                      ),
                    ],
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

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Tones.surfaceRaised,
                borderRadius: BorderRadius.circular(RadiusTokens.control),
              ),
              child: Icon(icon, size: 32, color: Tones.textMuted),
            ),
            const SizedBox(height: Space.lg),
            Text(title, style: TypeScale.title),
            const SizedBox(height: Space.sm),
            Text(body, textAlign: TextAlign.center, style: TypeScale.body),
          ],
        ),
      ),
    );
  }
}
