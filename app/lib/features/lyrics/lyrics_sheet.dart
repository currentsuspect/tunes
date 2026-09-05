import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/lyrics/lrc_parser.dart';
import '../../core/theme/tokens.dart';
import '../../domain/manifest.dart';

/// Bottom sheet that shows the lyrics for a track, with a tap-to-edit
/// toggle. Reads the current lyrics blob from the track (already
/// resolved by [ManifestStore] with user edits applied). When the
/// user saves, the caller persists via [ManifestStore.setEdit] with
/// field 'lyrics' (and the source becomes 'user' on first save).
class LyricsSheet extends StatefulWidget {
  const LyricsSheet({
    super.key,
    required this.track,
    required this.player,
    required this.onSave,
  });

  final ManifestTrack track;
  final TunePlayer player;
  final Future<void> Function(String lyrics) onSave;

  static Future<void> show(
    BuildContext context, {
    required ManifestTrack track,
    required TunePlayer player,
    required Future<void> Function(String lyrics) onSave,
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
      builder: (_) => LyricsSheet(track: track, player: player, onSave: onSave),
    );
  }

  @override
  State<LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends State<LyricsSheet> {
  bool _editing = false;
  // Local copy of the lyrics text so the view reflects edits without
  // waiting for the parent to re-supply the track. onSave writes to
  // both the persistent store AND this field, so the view updates
  // immediately on save.
  late String _lyrics;
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _lyrics = widget.track.lyrics ?? '';
    _controller = TextEditingController(text: _lyrics);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              children: [
                _Header(
                  track: widget.track,
                  editing: _editing,
                  onClose: () => Navigator.of(context).pop(),
                  onToggleEdit: () => setState(() {
                    _editing = !_editing;
                    if (_editing) _controller.text = widget.track.lyrics ?? '';
                  }),
                  onSave: _editing
                      ? () async {
                          final text = _controller.text;
                          await widget.onSave(text);
                          if (!mounted) return;
                          setState(() {
                            _editing = false;
                            _lyrics = text;
                          });
                        }
                      : null,
                ),
                const Divider(height: 1, thickness: 0.5, color: Tones.hairline),
                Expanded(
                  child: _editing
                      ? _Editor(
                          controller: _controller,
                          scrollController: scrollController,
                        )
                      : _View(
                          lyrics: _lyrics,
                          player: widget.player,
                          scrollController: scrollController,
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

class _Header extends StatelessWidget {
  const _Header({
    required this.track,
    required this.editing,
    required this.onClose,
    required this.onToggleEdit,
    required this.onSave,
  });

  final ManifestTrack track;
  final bool editing;
  final VoidCallback onClose;
  final VoidCallback onToggleEdit;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.md,
        Space.md,
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  style: TypeScale.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${track.artistDisplay} — ${track.album}',
                  style: TypeScale.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (editing)
            TextButton(onPressed: onSave, child: const Text('Save'))
          else
            TextButton(onPressed: onToggleEdit, child: const Text('Edit')),
        ],
      ),
    );
  }
}

class _View extends StatefulWidget {
  const _View({
    required this.lyrics,
    required this.player,
    required this.scrollController,
  });

  final String lyrics;
  final TunePlayer player;
  final ScrollController scrollController;

  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> {
  late Lrc? _lrc;
  int? _activeIndex;

  @override
  void initState() {
    super.initState();
    _lrc = widget.lyrics.isEmpty ? null : LrcParser.parse(widget.lyrics);
    widget.player.addListener(_onPlayerChange);
  }

  @override
  void dispose() {
    widget.player.removeListener(_onPlayerChange);
    super.dispose();
  }

  void _onPlayerChange() {
    final lrc = _lrc;
    if (lrc == null) return;
    final pos = widget.player.position;
    final active = LrcParser.activeLine(lrc, pos);
    final idx = active == null ? null : lrc.lines.indexOf(active);
    if (idx != _activeIndex) {
      setState(() => _activeIndex = idx);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lrc = _lrc;
    if (lrc == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Text(
            'No lyrics yet. Paste an LRC file into the editor, or paste '
            'plain text and it will display without timing.\n\n'
            'Lyrics live in the local database and survive syncs.',
            textAlign: TextAlign.center,
            style: TypeScale.body.copyWith(color: Tones.textMuted),
          ),
        ),
      );
    }
    if (lrc.lines.isEmpty) {
      // Track has lyrics text but no timed lines — display as a single
      // static block, no active-line tracking.
      return SingleChildScrollView(
        controller: widget.scrollController,
        padding: const EdgeInsets.all(Space.lg),
        child: Text(_plainTextFromLrc(lrc), style: TypeScale.body),
      );
    }
    final activeIdx = _activeIndex ?? -1;
    return ListView.separated(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(Space.lg),
      itemCount: lrc.lines.length,
      separatorBuilder: (_, _) => const SizedBox(height: Space.md),
      itemBuilder: (context, i) {
        final line = lrc.lines[i];
        final isActive = i == activeIdx;
        final isPast = i < activeIdx;
        return GestureDetector(
          onTap: () => widget.player.seek(line.timestamp),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TypeScale.title.copyWith(
              color: isActive
                  ? Tones.text
                  : isPast
                  ? Tones.textMuted.withValues(alpha: 0.6)
                  : Tones.text.withValues(alpha: 0.85),
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              height: 1.3,
            ),
            child: Text(line.text),
          ),
        );
      },
    );
  }

  String _plainTextFromLrc(Lrc lrc) {
    return lrc.lines.map((l) => l.text).join('\n');
  }
}

class _Editor extends StatelessWidget {
  const _Editor({required this.controller, required this.scrollController});
  final TextEditingController controller;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Space.lg),
      child: TextField(
        controller: controller,
        scrollController: scrollController,
        autofocus: true,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: TypeScale.body.copyWith(height: 1.4),
        decoration: const InputDecoration(
          hintText: '[00:00.00]Paste LRC here, or just plain text\n[00:12.34]First line',
          border: InputBorder.none,
        ),
      ),
    );
  }
}
