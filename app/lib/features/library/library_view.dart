import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/download_store.dart';
import '../../core/data/manifest_store.dart';
import '../../core/data/queue_store.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/generated_artwork.dart';
import '../../core/ui/initials.dart';
import '../../domain/manifest.dart';
import 'library_widgets.dart';

class LibraryView extends StatefulWidget {
  const LibraryView({
    super.key,
    required this.tracks,
    required this.releases,
    this.artists = const [],
    required this.filter,
    required this.player,
    required this.store,
    required this.downloading,
    required this.onDownload,
    required this.offline,
    required this.artUrlFor,
    required this.onArtistTap,
    required this.onAlbumTap,
    this.queueStore,
    this.manifestStore,
  });

  final List<ManifestTrack> tracks;
  final List<ManifestRelease> releases;
  final List<ManifestArtist> artists;
  final String filter;
  final TunePlayer player;
  final DownloadStore store;
  final Set<String> downloading;
  final void Function(ManifestTrack) onDownload;
  final bool offline;
  final String Function(String sha) artUrlFor;
  final void Function(String artist) onArtistTap;
  final void Function(ManifestRelease release) onAlbumTap;
  final QueueStore? queueStore;
  final ManifestStore? manifestStore;

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  int _segment = 0;

  bool get _hasActions =>
      widget.queueStore != null && widget.manifestStore != null;

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
            player: widget.player,
            track: t,
            onTap: () => _play(filtered, i),
            store: widget.store,
            downloading: widget.downloading.contains(t.sha),
            onDownload: () => widget.onDownload(t),
            offline: widget.offline,
            artUrlFor: widget.artUrlFor,
            onPlayNext: _hasActions
                ? () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final q = await widget.queueStore!.load();
                    await widget.queueStore!.replace([
                      t.sha,
                      ...q.map((e) => e.track.sha),
                    ]);
                    if (!mounted) return;
                    messenger.showSnackBar(
                      SnackBar(content: Text('"${t.title}" will play next')),
                    );
                  }
                : null,
            onAddToQueue: _hasActions
                ? () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await widget.queueStore!.append(t.sha);
                    if (!mounted) return;
                    messenger.showSnackBar(
                      SnackBar(content: Text('"${t.title}" added to queue')),
                    );
                  }
                : null,
            onEdit: _hasActions
                ? ({
                    // Tri-state: a non-null value replaces the edit;
                    // a null (including empty string) clears the edit so
                    // the field falls back to embedded-tag or daemon.
                    String? title,
                    String? artist,
                    String? album,
                    String? year,
                  }) async {
                    final messenger = ScaffoldMessenger.of(context);
                    final ms = widget.manifestStore!;
                    await ms.setEdit(t.sha, 'title', title);
                    await ms.setEdit(t.sha, 'artist', artist);
                    await ms.setEdit(t.sha, 'album', album);
                    await ms.setEdit(t.sha, 'year', year);
                    if (!mounted) return;
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Edit saved')),
                    );
                  }
                : null,
          );
        },
      );
    }
    if (_segment == 1) {
      final available = filtered.map((t) => t.releaseId).toSet();
      final entries = widget.releases
          .where((r) => available.contains(r.id))
          .toList();
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
          final r = entries[i];
          return InkWell(
            onTap: () => widget.onAlbumTap(r),
            borderRadius: BorderRadius.circular(RadiusTokens.card),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(RadiusTokens.card),
                    child: SizedBox.expand(
                      child: r.artSha != null
                          ? Image.network(
                              widget.artUrlFor(r.artSha!),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => GeneratedArtwork(
                                title: r.title,
                                artist: r.artist,
                              ),
                            )
                          : GeneratedArtwork(title: r.title, artist: r.artist),
                    ),
                  ),
                ),
                const SizedBox(height: Space.xs),
                Text(
                  r.title,
                  style: TypeScale.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${r.artist} · ${r.trackShas.length}',
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
    // Group by the act, not the raw credit line: one album otherwise lands
    // under nine "artists" ("Yeat", "Yeat;Don Toliver", "Yeat, Kodak Black").
    // Group by the act, not the raw credit line. A guest also gets their own
    // entry so tapping them finds the tracks they appear on -- the "Featured
    // on" section will hang off this later.
    final artists = <String, List<ManifestTrack>>{};
    for (final t in filtered) {
      artists.putIfAbsent(t.artistKey, () => []).add(t);
      for (final guest in t.featured) {
        if (guest != t.artistKey) artists.putIfAbsent(guest, () => []).add(t);
      }
    }
    // Leads first, then one-off guests. Adding featured artists as their own
    // entries took this list from 14 names to 80, and alphabetical order buried
    // Yeat behind a dozen artists with a single guest verse each.
    final entries = artists.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.length.compareTo(a.value.length);
        if (byCount != 0) return byCount;
        return a.key.toLowerCase().compareTo(b.key.toLowerCase());
      });
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
        return InkWell(
          onTap: () => widget.onArtistTap(name),
          borderRadius: BorderRadius.circular(RadiusTokens.control),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: Space.sm,
              horizontal: Space.xs,
            ),
            child: Row(
              children: [
                () {
                  String? photo;
                  for (final a in widget.artists) {
                    if (a.name == name) photo = a.artSha;
                  }
                  if (photo == null) {
                    return InitialsAvatar(name: name, size: 48);
                  }
                  return ClipOval(
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Image.network(
                        widget.artUrlFor(photo),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            InitialsAvatar(name: name, size: 48),
                      ),
                    ),
                  );
                }(),
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
