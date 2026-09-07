import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/playlist_store.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/artwork.dart';
import '../../core/ui/empty_state.dart';
import '../../core/ui/generated_artwork.dart';
import '../../domain/manifest.dart';

/// One playlist, in the order it was made.
///
/// Reorder by dragging, remove by swiping. Both are the gestures people
/// already expect from a list they own, and neither hides behind a menu.
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

class _PlaylistPageState extends State<PlaylistPage> {
  late String _name = widget.summary.name;
  List<String> _shas = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final shas = await widget.store.itemsOf(widget.summary.id);
    if (!mounted) return;
    setState(() {
      _shas = shas;
      _loaded = true;
    });
  }

  /// The playable subset, in playlist order.
  ///
  /// A playlist entry whose file has left the library is kept in the table --
  /// it is a record of a decision, and the file may come back -- but it
  /// cannot be played, so it is not put in the queue.
  List<ManifestTrack> get _playable {
    final bySha = {for (final t in widget.tracks) t.sha: t};
    return [
      for (final sha in _shas)
        if (bySha[sha] case final ManifestTrack t) t,
    ];
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: _name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Tones.surfaceRaised,
        title: const Text('Rename playlist', style: TypeScale.title),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TypeScale.body,
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
    if (name == null) return;
    await widget.store.rename(widget.summary.id, name);
    if (mounted) setState(() => _name = name.trim());
  }

  Future<void> _delete() async {
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Tones.surfaceRaised,
        title: const Text('Delete this playlist?', style: TypeScale.title),
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
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final playable = _playable;
    final missing = _shas.length - playable.length;
    return Scaffold(
      backgroundColor: Tones.surface,
      appBar: AppBar(
        backgroundColor: Tones.surface,
        title: Text(_name, style: TypeScale.heading),
        actions: [
          IconButton(
            onPressed: _rename,
            icon: const Icon(Icons.edit_rounded, color: Tones.textMuted),
            tooltip: 'Rename',
          ),
          IconButton(
            onPressed: _delete,
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: Tones.textMuted,
            ),
            tooltip: 'Delete playlist',
          ),
        ],
      ),
      body: !_loaded
          ? const SizedBox.shrink()
          : _shas.isEmpty
          ? const EmptyState(
              icon: Icons.queue_music_rounded,
              title: 'Nothing in here yet',
              body: 'Add tracks from the menu on any track, album or artist.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    Space.sm,
                    Space.lg,
                    Space.sm,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          [
                            '${_shas.length} '
                                '${_shas.length == 1 ? 'track' : 'tracks'}',
                            // Named, not hidden: a playlist that quietly
                            // plays fewer tracks than it lists is one you
                            // stop trusting.
                            if (missing > 0) '$missing not in your library',
                          ].join(' · '),
                          style: TypeScale.caption,
                        ),
                      ),
                      if (playable.isNotEmpty)
                        TextButton.icon(
                          onPressed: () => widget.player.playQueue(playable, 0),
                          icon: const Icon(Icons.play_arrow_rounded, size: 20),
                          label: const Text('Play'),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: Space.xl),
                    itemCount: _shas.length,
                    // onReorderItem rather than onReorder: it reports the
                    // destination already adjusted for the row having been
                    // lifted out, which is the off-by-one every hand-written
                    // reorder gets wrong once.
                    onReorderItem: (from, to) async {
                      setState(() {
                        final moved = _shas.removeAt(from);
                        _shas.insert(to, moved);
                      });
                      await widget.store.move(widget.summary.id, from, to);
                    },
                    itemBuilder: (context, i) {
                      final sha = _shas[i];
                      final track = widget.tracks
                          .where((t) => t.sha == sha)
                          .firstOrNull;
                      return Dismissible(
                        key: ValueKey('$sha-$i'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: Space.lg),
                          color: Tones.surfaceRaised,
                          child: const Icon(
                            Icons.remove_circle_outline_rounded,
                            color: Tones.textMuted,
                          ),
                        ),
                        onDismissed: (_) async {
                          setState(() => _shas.removeAt(i));
                          await widget.store.removeAt(widget.summary.id, i);
                        },
                        child: _Row(
                          index: i,
                          track: track,
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
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.index,
    required this.track,
    required this.artUrlFor,
    required this.onTap,
  });

  final int index;
  final ManifestTrack? track;
  final String Function(String sha) artUrlFor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = track;
    return ListTile(
      onTap: onTap,
      tileColor: Tones.surface,
      leading: t == null
          ? const SizedBox(
              width: 44,
              height: 44,
              child: Icon(Icons.help_outline_rounded, color: Tones.textMuted),
            )
          : Artwork(
              url: t.artSha == null ? null : artUrlFor(t.artSha!),
              size: 44,
              borderRadius: 8,
              fallback: GeneratedArtwork.fromTrack(
                t,
                size: 44,
                borderRadius: 8,
              ),
            ),
      title: Text(
        t?.title ?? 'Not in your library',
        style: TypeScale.title.copyWith(
          color: t == null ? Tones.textMuted : Tones.text,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        t?.artistDisplay ?? 'Kept in case it comes back',
        style: TypeScale.caption,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: ReorderableDragStartListener(
        index: index,
        child: const Icon(Icons.drag_handle_rounded, color: Tones.textMuted),
      ),
    );
  }
}
