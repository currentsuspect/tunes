import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/download_manager.dart';
import '../../core/data/playlist_store.dart';
import '../../core/data/reachability.dart';
import '../../core/nav/nav_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/tunes_menu.dart';
import '../../core/ui/artwork.dart';
import '../../core/ui/collection_download.dart';
import '../../core/ui/download_button.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/cover_tint.dart';
import '../../core/ui/generated_artwork.dart';
import '../../domain/manifest.dart';
import 'add_songs_sheet.dart';

/// One playlist, in the order you made it.
///
/// Drag the handle to reorder, swipe a row to take it out (and undo it from the
/// bar that appears), Shuffle to play it in a random order, Add songs to go and
/// get more. The header is the playlist's own cover: the first four sleeves in
/// it, lit by the first.
class PlaylistPage extends StatefulWidget {
  const PlaylistPage({
    super.key,
    required this.summary,
    required this.store,
    required this.player,
    required this.tracks,
    required this.artUrlFor,
  });

  final PlaylistSummary summary;
  final PlaylistStore store;
  final TunePlayer player;
  final List<ManifestTrack> tracks;
  final String Function(String sha) artUrlFor;

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

/// One line of the playlist. Keyed by an id of its own, not by its sha or its
/// position: the same track can be in a list twice, and a position-based key
/// changes on every reorder, which is how the old list lost track of rows.
class _Entry {
  _Entry(this.sha, this.id);

  final String sha;
  final int id;
}

class _PlaylistPageState extends State<PlaylistPage> {
  late String _name = widget.summary.name;
  List<_Entry> _entries = [];
  int _nextId = 0;
  bool _loaded = false;
  late Map<String, ManifestTrack> _bySha;

  @override
  void initState() {
    super.initState();
    _bySha = {for (final t in widget.tracks) t.sha: t};
    _load();
  }

  @override
  void didUpdateWidget(PlaylistPage old) {
    super.didUpdateWidget(old);
    if (old.tracks != widget.tracks) {
      _bySha = {for (final t in widget.tracks) t.sha: t};
    }
  }

  Future<void> _load() async {
    final shas = await widget.store.itemsOf(widget.summary.id);
    if (!mounted) return;
    setState(() {
      _entries = [for (final s in shas) _Entry(s, _nextId++)];
      _loaded = true;
    });
  }

  /// The playable subset, in playlist order.
  ///
  /// An entry whose file has left the library is kept in the table -- it is a
  /// record of a decision, and the file may come back -- but it cannot be
  /// played, so it is not put in the queue.
  List<ManifestTrack> _playable() => [
    for (final e in _entries)
      if (_bySha[e.sha] case final ManifestTrack t) t,
  ];

  Future<void> _rename() async {
    final controller = TextEditingController(text: _name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Tones.surfaceRaised,
        title: Text('Rename playlist', style: TypeScale.title),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TypeScale.body.copyWith(color: Tones.text),
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    await widget.store.rename(widget.summary.id, name);
    if (mounted) {
      setState(() => _name = name.trim().isEmpty ? _name : name.trim());
    }
  }

  Future<void> _delete() async {
    // This page is a panel in the shell's own history, not a route on the
    // Navigator, so leaving it goes through that history. Popping the
    // Navigator here closed the whole shell and left a black screen: it was the
    // crash on deleting a playlist. Taken before the dialog, because the
    // dialog is a root route that cannot see the shell's scope.
    final nav = NavScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Tones.surfaceRaised,
        title: Text('Delete this playlist?', style: TypeScale.title),
        content: Text(
          'The list goes, and nothing else does. Every track stays in your '
          'library and every file stays on disk.',
          style: TypeScale.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.delete(widget.summary.id);
    nav.back();
  }

  void _shuffle() => widget.player.shufflePlay(_playable());

  Future<void> _addSongs() async {
    await AddSongsSheet.show(
      context,
      playlistId: widget.summary.id,
      store: widget.store,
      tracks: widget.tracks,
      alreadyIn: {for (final e in _entries) e.sha},
      artUrlFor: widget.artUrlFor,
    );
    // Reload once the sheet is closed, not on every tap inside it, so the list
    // underneath does not reshuffle while it is being used.
    if (mounted) await _load();
  }

  /// Takes a row out and offers it straight back.
  ///
  /// Swiping is easy to do by accident, and it used to be final. The entry is
  /// removed by its identity at this moment, not by an index captured when the
  /// row was built, which could be stale by the time the swipe finished.
  Future<void> _remove(_Entry entry) async {
    final at = _entries.indexOf(entry);
    if (at < 0) return;
    final title = _bySha[entry.sha]?.title ?? 'Track';
    setState(() => _entries.removeAt(at));
    await widget.store.removeAt(widget.summary.id, at);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Removed "$title"'),
        duration: const Duration(seconds: 5),
        // An action keeps a snackbar up until dismissed unless told otherwise.
        persist: false,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await widget.store.insertAt(widget.summary.id, entry.sha, at);
            if (mounted) await _load();
          },
        ),
      ),
    );
  }

  Future<void> _move(int from, int to) async {
    if (from == to || from < 0 || from >= _entries.length) return;
    setState(() => _entries.insert(to, _entries.removeAt(from)));
    await widget.store.move(widget.summary.id, from, to);
  }

  /// "9 h 12 min" or "47 min": enough to know what you are about to commit to.
  static String _span(int ms) {
    final minutes = (ms / 60000).round();
    if (minutes < 60) return '$minutes min';
    return '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')} min';
  }

  @override
  Widget build(BuildContext context) {
    final playable = _playable();
    final missing = _entries.length - playable.length;
    final totalMs = playable.fold<int>(0, (a, t) => a + (t.durationMs ?? 0));
    final covers = <String>[];
    for (final t in playable) {
      final a = t.artSha;
      if (a != null && !covers.contains(a)) covers.add(a);
      if (covers.length == 4) break;
    }
    return Scaffold(
      backgroundColor: Tones.base,
      body: TintBuilder(
        artSha: covers.isEmpty ? null : covers.first,
        builder: (context, tint) => Stack(
          fit: StackFit.expand,
          children: [
            AmbientGlow(tint: tint, strength: 0.34),
            SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.xs,
                      Space.sm,
                      Space.xs,
                      0,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => NavScope.of(context).back(),
                          tooltip: 'Back',
                          icon: Icon(
                            Icons.arrow_back_rounded,
                            color: Tones.textMuted,
                          ),
                        ),
                        const Spacer(),
                        PopupMenuButton<String>(
                          icon: Icon(
                            Icons.more_horiz_rounded,
                            color: Tones.textMuted,
                          ),
                          tooltip: 'More',
                          onSelected: (v) =>
                              v == 'rename' ? _rename() : _delete(),
                          itemBuilder: (_) => [
                            tunesMenuItem(
                              'rename',
                              Icons.edit_outlined,
                              'Rename',
                            ),
                            tunesMenuItem(
                              'delete',
                              Icons.delete_outline_rounded,
                              'Delete playlist',
                              danger: true,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: !_loaded
                        ? const SizedBox.shrink()
                        : ReorderableListView.builder(
                            padding: const EdgeInsets.only(bottom: Space.xl),
                            itemCount: _entries.length,
                            buildDefaultDragHandles: false,
                            header: _Header(
                              name: _name,
                              covers: covers,
                              tint: tint,
                              artUrlFor: widget.artUrlFor,
                              facts: [
                                '${_entries.length} '
                                    '${_entries.length == 1 ? 'song' : 'songs'}',
                                if (totalMs > 0) _span(totalMs),
                                // Named, not hidden: a playlist that quietly
                                // plays fewer tracks than it lists is one you
                                // stop trusting.
                                if (missing > 0) '$missing not in your library',
                              ].join('  ·  '),
                              empty: _entries.isEmpty,
                              onPlay: playable.isEmpty
                                  ? null
                                  : () => widget.player.playQueue(playable, 0),
                              onShuffle: playable.isEmpty ? null : _shuffle,
                              onAdd: _addSongs,
                              tracks: playable,
                            ),
                            // onReorderItem rather than onReorder: it reports
                            // the destination already adjusted for the row
                            // having been lifted out, which is the off-by-one
                            // every hand-written reorder gets wrong once.
                            onReorderItem: _move,
                            itemBuilder: (context, i) {
                              final entry = _entries[i];
                              final track = _bySha[entry.sha];
                              return Dismissible(
                                key: ValueKey(entry.id),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(
                                    right: Space.lg,
                                  ),
                                  color: Tones.surfaceRaised,
                                  child: Icon(
                                    Icons.remove_circle_outline_rounded,
                                    color: Tones.textMuted,
                                  ),
                                ),
                                onDismissed: (_) => _remove(entry),
                                child: _Row(
                                  index: i,
                                  track: track,
                                  player: widget.player,
                                  artUrlFor: widget.artUrlFor,
                                  onTap: track == null
                                      ? null
                                      : () => widget.player.playQueue(
                                          playable,
                                          playable.indexOf(track),
                                        ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.covers,
    required this.tint,
    required this.artUrlFor,
    required this.facts,
    required this.empty,
    required this.onPlay,
    required this.onShuffle,
    required this.onAdd,
    required this.tracks,
  });

  /// The songs that can be played, which are the ones that can be downloaded.
  final List<ManifestTrack> tracks;

  final String name;
  final List<String> covers;
  final Color tint;
  final String Function(String sha) artUrlFor;
  final String facts;
  final bool empty;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final downloads = DownloadScope.maybeOf(context);
    final offline = ReachabilityScope.maybeOf(context)?.offline ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.sm,
        Space.lg,
        Space.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _Mosaic(
                name: name,
                covers: covers,
                tint: tint,
                artUrlFor: artUrlFor,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PLAYLIST',
                      style: TypeScale.mono.copyWith(letterSpacing: 1.2),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TypeScale.display.copyWith(fontSize: 26),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Text(facts, style: TypeScale.mono),
          const SizedBox(height: Space.md),
          Row(
            children: [
              FilledButton.icon(
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('Play'),
                style: FilledButton.styleFrom(
                  backgroundColor: Tones.text,
                  foregroundColor: Tones.base,
                ),
              ),
              const SizedBox(width: Space.sm),
              OutlinedButton.icon(
                onPressed: onShuffle,
                icon: const Icon(Icons.shuffle_rounded, size: 18),
                label: const Text('Shuffle'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Tones.text,
                  side: BorderSide(color: Tones.hairline),
                ),
              ),
              const Spacer(),
              // Round, like the download beside it: two buttons with words
              // and two with marks fit a phone's width; four with words did
              // not.
              Tooltip(
                message: 'Add songs',
                child: InkResponse(
                  onTap: onAdd,
                  radius: 26,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Tones.hairline),
                    ),
                    child: Icon(Icons.add_rounded, size: 22, color: Tones.text),
                  ),
                ),
              ),
              if (tracks.isNotEmpty && downloads != null) ...[
                const SizedBox(width: Space.sm),
                // The whole playlist in one tap, with the same ring the
                // album page uses so it says how far it has got.
                CollectionDownload(
                  noun: 'playlist',
                  tracks: tracks,
                  store: downloads.store,
                  offline: offline,
                  onDownload: (t) => downloads.enqueue(t.sha, artSha: t.artSha),
                ),
              ],
            ],
          ),
          if (empty) ...[
            const SizedBox(height: Space.lg),
            Text(
              'Nothing in here yet. Add songs, or use "Add to playlist" from '
              'any track.',
              style: TypeScale.note.copyWith(
                fontSize: 14,
                color: Tones.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The playlist's cover: the first four sleeves in it, two by two. A playlist
/// with fewer than four covers fills the rest from its own name, so it is never
/// a grey square.
class _Mosaic extends StatelessWidget {
  const _Mosaic({
    required this.name,
    required this.covers,
    required this.tint,
    required this.artUrlFor,
  });

  final String name;
  final List<String> covers;
  final Color tint;
  final String Function(String sha) artUrlFor;

  static const _side = 124.0;

  @override
  Widget build(BuildContext context) {
    const cell = _side / 2;
    Widget tile(int i) {
      if (i < covers.length) {
        return Artwork(
          url: artUrlFor(covers[i]),
          artSha: covers[i],
          size: cell,
          borderRadius: 0,
          fallback: GeneratedArtwork(
            title: '$name $i',
            artist: '',
            size: cell,
            borderRadius: 0,
          ),
        );
      }
      return GeneratedArtwork(
        title: '$name $i',
        artist: '',
        size: cell,
        borderRadius: 0,
      );
    }

    return mosaicFrame(
      tint: tint,
      side: _side,
      grid: Column(
        children: [
          Row(children: [tile(0), tile(1)]),
          Row(children: [tile(2), tile(3)]),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.index,
    required this.track,
    required this.player,
    required this.artUrlFor,
    required this.onTap,
  });

  final int index;
  final ManifestTrack? track;
  final TunePlayer player;
  final String Function(String sha) artUrlFor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = track;
    final downloads = DownloadScope.maybeOf(context);
    final offline = ReachabilityScope.maybeOf(context)?.offline ?? false;
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final playing = t != null && player.current?.sha == t.sha;
        return Material(
          color: Tones.base,
          child: PressRow(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.lg,
                vertical: Space.sm,
              ),
              child: Row(
                children: [
                  t == null
                      ? SizedBox(
                          width: 48,
                          height: 48,
                          child: Icon(
                            Icons.help_outline_rounded,
                            color: Tones.textMuted,
                          ),
                        )
                      : Artwork(
                          url: t.artSha == null ? null : artUrlFor(t.artSha!),
                          artSha: t.artSha,
                          size: 48,
                          borderRadius: 9,
                          fallback: GeneratedArtwork.fromTrack(
                            t,
                            size: 48,
                            borderRadius: 9,
                          ),
                        ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t?.title ?? 'Not in your library',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TypeScale.title.copyWith(
                            fontSize: 15,
                            color: t == null
                                ? Tones.textMuted
                                : playing
                                ? Tones.primary
                                : Tones.text,
                          ),
                        ),
                        Text(
                          t?.artistAlbumLine ?? 'Kept in case it comes back',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TypeScale.caption,
                        ),
                      ],
                    ),
                  ),
                  if (t != null)
                    Padding(
                      padding: const EdgeInsets.only(left: Space.sm),
                      child: Text(t.durationLabel, style: TypeScale.mono),
                    ),
                  if (t != null && downloads != null)
                    DownloadButton(
                      sha: t.sha,
                      title: t.title,
                      store: downloads.store,
                      offline: offline,
                      onDownload: () =>
                          downloads.enqueue(t.sha, artSha: t.artSha),
                    ),
                  ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: EdgeInsets.only(left: Space.sm),
                      child: Icon(
                        Icons.drag_handle_rounded,
                        color: Tones.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
