import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/queue_store.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/generated_artwork.dart';
import '../../domain/manifest.dart';

/// Bottom sheet that shows the persistent play queue, lets the user
/// drag-reorder tracks, and "play now" or remove individual entries.
///
/// Backed by [QueueStore] so changes survive restarts. The
/// [TunePlayer] queue is a *projection* of this list; calling
/// [TunePlayer.playQueue] starts playing the chosen entry.
class QueueSheet extends StatefulWidget {
  const QueueSheet({super.key, required this.queueStore, required this.player});

  final QueueStore queueStore;
  final TunePlayer player;

  static Future<void> show(
    BuildContext context, {
    required QueueStore queueStore,
    required TunePlayer player,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Tones.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(RadiusTokens.card),
        ),
      ),
      builder: (_) => QueueSheet(queueStore: queueStore, player: player),
    );
  }

  @override
  State<QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends State<QueueSheet> {
  late final Stream<List<ManifestTrack>> _stream;
  List<ManifestTrack> _tracks = const [];
  String? _activeSha;
  bool _dragInProgress = false;

  @override
  void initState() {
    super.initState();
    _stream = widget.queueStore.watch();
    _stream.listen((t) {
      if (!_dragInProgress) {
        setState(() => _tracks = t);
      }
    });
    widget.player.addListener(_onPlayerChange);
    _refreshActive();
  }

  @override
  void dispose() {
    widget.player.removeListener(_onPlayerChange);
    super.dispose();
  }

  void _onPlayerChange() {
    _refreshActive();
  }

  void _refreshActive() {
    final active = widget.player.current?.sha;
    if (active != _activeSha) {
      setState(() => _activeSha = active);
    }
  }

  Future<void> _reorder(List<ManifestTrack> next) async {
    final shas = next.map((t) => t.sha).toList();
    setState(() {
      _dragInProgress = true;
      _tracks = next;
    });
    try {
      await widget.queueStore.reorder(shas);
    } finally {
      if (mounted) setState(() => _dragInProgress = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return SafeArea(
          child: Column(
            children: [
              _Header(
                onClose: () => Navigator.of(context).pop(),
                onClear: _tracks.isEmpty
                    ? null
                    : () async {
                        await widget.queueStore.clear();
                        if (!mounted) return;
                        setState(() => _tracks = const []);
                      },
              ),
              const Divider(height: 1, thickness: 0.5, color: Tones.hairline),
              if (_tracks.isEmpty)
                const Expanded(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(Space.xl),
                      child: Text(
                        'Queue is empty.\nTap a track in your library and '
                        'choose "Add to queue" or "Play next".',
                        textAlign: TextAlign.center,
                        style: TypeScale.body,
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ReorderableListView.builder(
                    scrollController: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: Space.sm),
                    buildDefaultDragHandles: false,
                    itemCount: _tracks.length,
                    onReorderItem: (oldIndex, newIndex) {
                      final next = [..._tracks];
                      final moved = next.removeAt(oldIndex);
                      next.insert(newIndex, moved);
                      _reorder(next);
                    },
                    itemBuilder: (context, i) {
                      final t = _tracks[i];
                      return _QueueRow(
                        key: ValueKey(t.sha),
                        index: i,
                        track: t,
                        isActive: t.sha == _activeSha,
                        onPlay: () {
                          widget.player.playQueue(_tracks.sublist(i), 0);
                          Navigator.of(context).pop();
                        },
                        onRemove: () async {
                          await widget.queueStore.remove(t.sha);
                          if (!mounted) return;
                          setState(
                            () => _tracks = [
                              for (final x in _tracks)
                                if (x.sha != t.sha) x,
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose, required this.onClear});
  final VoidCallback onClose;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.sm,
        Space.sm,
        Space.lg,
        Space.sm,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Tones.textMuted,
            ),
          ),
          const SizedBox(width: Space.sm),
          const Expanded(child: Text('Queue', style: TypeScale.title)),
          if (onClear != null)
            TextButton(onPressed: onClear, child: const Text('Clear')),
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    super.key,
    required this.index,
    required this.track,
    required this.isActive,
    required this.onPlay,
    required this.onRemove,
  });

  final int index;
  final ManifestTrack track;
  final bool isActive;
  final VoidCallback onPlay;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isActive
          ? Tones.primary.withValues(alpha: 0.08)
          : Colors.transparent,
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.all(Space.md),
              child: Icon(Icons.drag_handle_rounded, color: Tones.textMuted),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: onPlay,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.md),
                child: Row(
                  children: [
                    GeneratedArtwork(
                      title: track.title,
                      artist: track.artist,
                      size: 44,
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            style: TypeScale.body.copyWith(
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isActive ? Tones.primary : Tones.text,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            track.artist,
                            style: TypeScale.caption,
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
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(
              Icons.close_rounded,
              color: Tones.textMuted,
              size: 20,
            ),
            tooltip: 'Remove from queue',
          ),
          const SizedBox(width: Space.sm),
        ],
      ),
    );
  }
}
