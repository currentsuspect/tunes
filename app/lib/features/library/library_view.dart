import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/download_store.dart';
import '../../core/data/likes_store.dart';
import '../../core/data/playlist_store.dart';
import '../../core/data/manifest_store.dart';
import '../../core/data/queue_store.dart';
import '../../core/nav/nav_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/artwork.dart';
import '../../core/ui/shared_sleeve.dart';
import '../../core/ui/empty_state.dart';
import '../../core/ui/generated_artwork.dart';
import '../../core/ui/initials.dart';
import '../../core/ui/shelf_widgets.dart';
import '../../domain/manifest.dart';
import '../playlists/playlist_page.dart';
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
    this.recents = const [],
  });

  /// Newest first. Shown above the track list: it used to sit at the bottom of
  /// Home, a long scroll from where anyone looks for what they just played.
  final List<ManifestTrack> recents;

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

  /// Only what is on this phone: the songs that play with no connection. A
  /// choice while online; offline the shell has already cut the library to this.
  bool _onPhone = false;

  int get _heldCount =>
      widget.tracks.where((t) => widget.store.pathFor(t.sha) != null).length;

  bool get _hasActions =>
      widget.queueStore != null && widget.manifestStore != null;

  List<ManifestTrack> get _filtered {
    final f = widget.filter.trim().toLowerCase();
    var base = widget.tracks;
    if (_onPhone) {
      base = [
        for (final t in base)
          if (widget.store.pathFor(t.sha) != null) t,
      ];
    }
    if (f.isEmpty) return base;
    return base
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
          child: _LibraryTabs(
            labels: const ['Tracks', 'Albums', 'Artists', 'Playlists'],
            selected: _segment,
            onSelect: (i) => setState(() => _segment = i),
          ),
        ),
        if (_segment != 3 && !widget.offline)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
            child: ListenableBuilder(
              listenable: widget.store,
              builder: (context, _) => Row(
                children: [
                  _FilterChip(
                    label: 'All',
                    selected: !_onPhone,
                    onTap: () => setState(() => _onPhone = false),
                  ),
                  const SizedBox(width: Space.sm),
                  _FilterChip(
                    icon: Icons.offline_pin_rounded,
                    label: 'On this phone',
                    count: _heldCount,
                    selected: _onPhone,
                    onTap: () => setState(() => _onPhone = true),
                  ),
                ],
              ),
            ),
          ),
        Expanded(child: _buildBody(filtered)),
      ],
    );
  }

  /// How many, and a way to hear them in a random order. Above every list of
  /// songs, so the library has a shuffle that is always one tap away.
  Widget _countBar(List<ManifestTrack> tracks, {bool play = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${tracks.length} ${tracks.length == 1 ? 'song' : 'songs'}',
              style: TypeScale.mono,
            ),
          ),
          if (play) ...[
            PlayPill(onTap: () => _play(tracks, 0)),
            const SizedBox(width: Space.sm),
          ],
          PlayPill(
            label: 'Shuffle',
            icon: Icons.shuffle_rounded,
            onTap: () => widget.player.shufflePlay(tracks),
          ),
        ],
      ),
    );
  }

  /// What you played last, as a rail of sleeves above the list.
  Widget _recentRail() {
    final recents = widget.recents.take(12).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Text(
              'Recently played',
              style: TypeScale.heading.copyWith(fontSize: 20),
            ),
          ),
          SizedBox(
            height: 136,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: recents.length,
              separatorBuilder: (_, _) => const SizedBox(width: Space.md),
              itemBuilder: (context, i) {
                final t = recents[i];
                return SizedBox(
                  width: 92,
                  child: InkWell(
                    onTap: () => _play(recents, i),
                    borderRadius: BorderRadius.circular(RadiusTokens.control),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Artwork(
                          url: t.artSha == null
                              ? null
                              : widget.artUrlFor(t.artSha!),
                          artSha: t.artSha,
                          size: 92,
                          borderRadius: 12,
                          fallback: GeneratedArtwork.fromTrack(
                            t,
                            size: 92,
                            borderRadius: 12,
                          ),
                        ),
                        const SizedBox(height: Space.xs),
                        Text(
                          t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: cardTitleStyle().copyWith(fontSize: 12.5),
                        ),
                        Text(
                          t.artistDisplay,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TypeScale.caption.copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _trackList(List<ManifestTrack> tracks, {bool play = false}) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      // One extra item at the top for the count and shuffle.
      itemCount: tracks.length + 1,
      // Air between rows rather than a rule under each one: the sleeves and the
      // type already separate them.
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.recents.isNotEmpty && widget.filter.trim().isEmpty)
                _recentRail(),
              _countBar(tracks, play: play),
            ],
          );
        }
        final i = index - 1;
        final t = tracks[i];
        return TrackRow(
          player: widget.player,
          track: t,
          onTap: () => _play(tracks, i),
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

  /// The tracks the listener said yes to, most recently liked first.
  ///
  /// Deliberately not filtered by the search box: the filter narrows the
  /// library, and this is a different list that happens to live behind the
  /// same control. Resolved against the manifest so a like whose track has
  /// left the library is simply not shown rather than rendered as a blank.
  Widget _likedPage() {
    return Scaffold(
      backgroundColor: Tones.surface,
      appBar: AppBar(
        backgroundColor: Tones.surface,
        title: const Text('Liked songs', style: TypeScale.heading),
        leading: IconButton(
          onPressed: () => NavScope.of(context).back(),
          icon: const Icon(Icons.arrow_back_rounded, color: Tones.textMuted),
        ),
      ),
      body: ListenableBuilder(
        listenable: LikesScope.maybeOf(context) ?? _never,
        builder: (context, _) {
          final likes = LikesScope.maybeOf(context);
          if (likes == null || likes.count == 0) {
            return const EmptyState(
              icon: Icons.favorite_border_rounded,
              title: 'Nothing liked yet',
              body:
                  'Tap the heart in the player, or open the menu on any '
                  'track.',
            );
          }
          final bySha = {for (final t in widget.tracks) t.sha: t};
          final tracks = [
            for (final sha in likes.shas)
              if (bySha[sha] case final ManifestTrack t) t,
          ];
          if (tracks.isEmpty) {
            return const EmptyState(
              icon: Icons.favorite_border_rounded,
              title: 'Liked tracks are not in the library',
              body:
                  'Everything you liked has since left the library. The '
                  'likes are kept in case it comes back.',
            );
          }
          return _trackList(tracks, play: true);
        },
      ),
    );
  }

  /// A listenable that never fires, for the case where there is no scope to
  /// listen to. Rebuilding on nothing is better than a nullable listenable.
  static final _never = ValueNotifier<int>(0);

  /// The lists you made, most recently changed first.
  ///
  /// Rebuilt whenever the store changes, so a playlist created from a track
  /// menu on another screen is here when you arrive rather than after a
  /// restart.
  Future<void> _createPlaylist(PlaylistStore store) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Tones.surfaceRaised,
        title: const Text('New playlist', style: TypeScale.title),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TypeScale.body,
          decoration: const InputDecoration(
            hintText: 'Name it',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null) return;
    await store.create(name);
  }

  Widget _buildPlaylists() {
    final store = PlaylistScope.maybeOf(context);
    if (store == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => FutureBuilder<List<PlaylistSummary>>(
        future: store.summaries(),
        builder: (context, snap) {
          final lists = snap.data;
          // Nothing while it loads: this resolves in a frame or two off a
          // local database, and a spinner that flashes is worse than a beat
          // of empty space.
          if (lists == null) return const SizedBox.shrink();
          // Liked songs sits at the top and is always there, empty or not.
          // It is a playlist in everything but how it is filled -- the app
          // keeps the order, you supply the members -- and giving it a
          // segment of its own cost a tab for something that belongs in
          // this list. There is no empty state here any more, because this
          // screen is never empty.
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            itemCount: lists.length + 2,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == 0) {
                final n = LikesScope.maybeOf(context)?.count ?? 0;
                return ListTile(
                  leading: const Icon(
                    Icons.favorite_rounded,
                    color: Tones.primary,
                  ),
                  title: const Text('Liked songs', style: TypeScale.title),
                  subtitle: Text(
                    n == 0
                        ? 'Nothing liked yet'
                        : '$n ${n == 1 ? 'track' : 'tracks'}',
                    style: TypeScale.caption,
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: Tones.textMuted,
                  ),
                  onTap: () =>
                      NavScope.of(context)
                          .openPanel(TunesPanels.liked, () => _likedPage()),
                );
              }
              if (index == 1) {
                // A screen called Playlists with no way to make one sends
                // you off to find a track first. Creating an empty list and
                // filling it later is how most of them actually start.
                return ListTile(
                  leading: const Icon(Icons.add_rounded, color: Tones.primary),
                  title: const Text('New playlist', style: TypeScale.title),
                  onTap: () => _createPlaylist(store),
                );
              }
              final p = lists[index - 2];
              return ListTile(
                leading: const Icon(
                  Icons.queue_music_rounded,
                  color: Tones.textMuted,
                ),
                title: Text(p.name, style: TypeScale.title),
                subtitle: Text(
                  '${p.trackCount} '
                  '${p.trackCount == 1 ? 'track' : 'tracks'}',
                  style: TypeScale.caption,
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: Tones.textMuted,
                ),
                onTap: () => NavScope.of(context).openPanel(
                  TunesPanels.playlist(p.id),
                  () => PlaylistPage(
                    summary: p,
                    store: store,
                    player: widget.player,
                    tracks: widget.tracks,
                    artUrlFor: widget.artUrlFor,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildBody(List<ManifestTrack> filtered) {
    // Ahead of the empty check, because "nothing matched the filter" is the
    // wrong thing to say about a list the filter does not apply to.
    if (_segment == 3) return _buildPlaylists();
    if (filtered.isEmpty) {
      // Two different situations were sharing one sentence. "Your library is
      // empty or your filter matched nothing" tells someone who typed three
      // letters that their whole library might be gone.
      if (_onPhone && widget.filter.trim().isEmpty) {
        return const EmptyState(
          icon: Icons.offline_pin_outlined,
          title: 'Nothing on this phone yet',
          body:
              'Tap the arrow beside a song to download it. Downloaded songs '
              'play with no connection, and are all you see when offline.',
        );
      }
      return widget.tracks.isEmpty
          ? const EmptyState(
              icon: Icons.library_music_outlined,
              title: 'Your library is empty',
              body:
                  'Tracks appear here as the daemon fetches them. Pull down '
                  'on Home to check again.',
            )
          : EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Nothing matches',
              body:
                  'No track, album or artist here matches '
                  '"${widget.filter.trim()}".',
            );
    }
    if (_segment == 0) return _trackList(filtered);
    if (_segment == 1) {
      final available = filtered.map((t) => t.releaseId).toSet();
      final entries = widget.releases
          .where((r) => available.contains(r.id))
          .toList();
      return ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) => GridView.builder(
          padding: const EdgeInsets.all(Space.lg),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            childAspectRatio: 0.76,
            mainAxisSpacing: Space.lg,
            crossAxisSpacing: Space.md,
          ),
          itemCount: entries.length,
          itemBuilder: (context, i) {
            final r = entries[i];
            final held = r.trackShas
                .where((sha) => widget.store.pathFor(sha) != null)
                .length;
            final all = r.trackShas.isNotEmpty && held == r.trackShas.length;
            return InkWell(
              onTap: () => widget.onAlbumTap(r),
              borderRadius: BorderRadius.circular(RadiusTokens.card),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        SharedSleeve(
                          tag: 'album-${r.id}',
                          child: Artwork.fill(
                            url: r.artSha == null
                                ? null
                                : widget.artUrlFor(r.artSha!),
                            artSha: r.artSha,
                            shared: true,
                            borderRadius: 14,
                            fallback: GeneratedArtwork(
                              title: r.title,
                              artist: r.artist,
                              borderRadius: 14,
                            ),
                          ),
                        ),
                        // On the phone: a green tick when all of it is, a small
                        // count when some is. Nothing when none is, so the mark
                        // always means "this plays with no connection".
                        if (held > 0)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Tones.base.withValues(alpha: 0.78),
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(color: Tones.held),
                              ),
                              child: all
                                  ? const Icon(
                                      Icons.check_rounded,
                                      size: 12,
                                      color: Tones.held,
                                    )
                                  : Text(
                                      '$held/${r.trackShas.length}',
                                      style: TypeScale.mono.copyWith(
                                        fontSize: 10,
                                        color: Tones.held,
                                      ),
                                    ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                  Text(
                    r.title,
                    style: cardTitleStyle(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    r.artist,
                    style: TypeScale.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    [
                      if (r.year != null) r.year!.split('-').first,
                      '${r.trackShas.length} ${r.trackShas.length == 1 ? 'song' : 'songs'}',
                    ].join('  ·  '),
                    style: TypeScale.mono.copyWith(fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          },
        ),
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
    return GridView.builder(
      padding: const EdgeInsets.all(Space.lg),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.74,
        mainAxisSpacing: Space.lg,
        crossAxisSpacing: Space.md,
      ),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final name = entries[i].key;
        final tracks = entries[i].value;
        String? photo;
        for (final a in widget.artists) {
          if (a.name == name) photo = a.artSha;
        }
        return InkWell(
          onTap: () => widget.onArtistTap(name),
          borderRadius: BorderRadius.circular(RadiusTokens.control),
          child: LayoutBuilder(
            builder: (context, c) {
              final face = c.maxWidth - Space.sm;
              return Column(
                children: [
                  SharedSleeve(
                    tag: 'artist-$name',
                    child: Artwork(
                      url: photo == null ? null : widget.artUrlFor(photo),
                      artSha: photo,
                      size: face,
                      borderRadius: face / 2,
                      shared: true,
                      fallback: InitialsAvatar(name: name, size: face),
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                  Text(
                    name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TypeScale.caption.copyWith(
                      color: Tones.text,
                      height: 1.2,
                    ),
                  ),
                  Text(
                    '${tracks.length} ${tracks.length == 1 ? 'song' : 'songs'}',
                    style: TypeScale.mono.copyWith(fontSize: 10.5),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// A small choice above a list: All, or only what is on this phone.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? Tones.surfaceRaised : Colors.transparent,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(99),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.md,
              vertical: Space.sm - 2,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: selected ? Tones.held : Tones.hairline),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 15,
                    color: selected ? Tones.held : Tones.textMuted,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TypeScale.caption.copyWith(
                    color: selected ? Tones.text : Tones.textMuted,
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Text('$count', style: TypeScale.mono.copyWith(fontSize: 11)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The Library's sections as words with a line under the one you are on.
///
/// The stock segmented control was a bordered pill of four equal boxes, the one
/// heavy thing on a screen of light type. This is the serif and a short accent
/// rule that slides to the chosen word.
class _LibraryTabs extends StatelessWidget {
  const _LibraryTabs({
    required this.labels,
    required this.selected,
    required this.onSelect,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final fade = still ? Duration.zero : const Duration(milliseconds: 200);
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: Space.lg),
            child: Semantics(
              button: true,
              selected: i == selected,
              child: InkWell(
                onTap: () => onSelect(i),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.xs),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: fade,
                        style: TypeScale.display.copyWith(
                          fontSize: 19,
                          color: i == selected ? Tones.text : Tones.textMuted,
                        ),
                        child: Text(labels[i]),
                      ),
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        duration: fade,
                        width: i == selected ? 18 : 0,
                        height: 2,
                        decoration: BoxDecoration(
                          color: Tones.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
