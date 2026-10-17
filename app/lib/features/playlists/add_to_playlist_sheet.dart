import 'package:flutter/material.dart';

import '../../core/data/playlist_store.dart';
import '../../core/theme/tokens.dart';

/// Where a track goes when you decide it belongs somewhere.
///
/// Opens on the list of playlists with "New playlist" at the top, because the
/// first time anyone opens this there are no playlists and the only useful
/// thing on screen is the way to make one.
class AddToPlaylistSheet extends StatefulWidget {
  const AddToPlaylistSheet({
    super.key,
    required this.store,
    required this.shas,
  });

  final PlaylistStore store;

  /// One track, or a whole album. The sheet does not care which, so adding an
  /// album is the same gesture as adding a song.
  final List<String> shas;

  static Future<void> show(
    BuildContext context, {
    required PlaylistStore store,
    required List<String> shas,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Tones.surface,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(RadiusTokens.card),
        ),
      ),
      builder: (_) => AddToPlaylistSheet(store: store, shas: shas),
    );
  }

  @override
  State<AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends State<AddToPlaylistSheet> {
  List<PlaylistSummary> _lists = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final lists = await widget.store.summaries();
    if (!mounted) return;
    setState(() {
      _lists = lists;
      _loaded = true;
    });
  }

  Future<void> _addTo(int id, String name) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final n = await widget.store.addAll(id, widget.shas);
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text('${n == 1 ? '1 track' : '$n tracks'} added to "$name"'),
      ),
    );
  }

  Future<void> _createAndAdd() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Tones.surfaceRaised,
        title: Text('New playlist', style: TypeScale.title),
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
    final id = await widget.store.create(name);
    if (!mounted) return;
    await _addTo(id, name.trim().isEmpty ? 'Untitled playlist' : name.trim());
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.shas.length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.md,
                Space.lg,
                Space.md,
              ),
              child: Text(
                count == 1 ? 'Add to playlist' : 'Add $count tracks to',
                style: TypeScale.title,
              ),
            ),
            Divider(height: 1, thickness: 0.5, color: Tones.hairline),
            ListTile(
              leading: Icon(Icons.add_rounded, color: Tones.primary),
              title: Text('New playlist', style: TypeScale.body),
              onTap: _createAndAdd,
            ),
            if (_loaded && _lists.isEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  Space.lg,
                  Space.sm,
                  Space.lg,
                  Space.lg,
                ),
                child: Text(
                  'You have no playlists yet.',
                  style: TypeScale.caption,
                ),
              ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _lists.length,
                itemBuilder: (context, i) {
                  final p = _lists[i];
                  return ListTile(
                    leading: Icon(
                      Icons.queue_music_rounded,
                      color: Tones.textMuted,
                    ),
                    title: Text(p.name, style: TypeScale.body),
                    subtitle: Text(
                      '${p.trackCount} '
                      '${p.trackCount == 1 ? 'track' : 'tracks'}',
                      style: TypeScale.caption,
                    ),
                    onTap: () => _addTo(p.id, p.name),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
