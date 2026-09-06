import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/lyrics/lrc_parser.dart';
import '../../core/theme/tokens.dart';
import '../../domain/manifest.dart';
import 'karaoke_line.dart';
import 'lyrics_sync_page.dart';

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
  bool _saving = false;
  // The lyrics as they now stand, which after a save is newer than the track
  // the parent handed us -- the parent does not re-supply it. Editing has to
  // start from this, not from `widget.track.lyrics`, or the editor opens on
  // the pre-save text and saving again quietly reverts the user's work.
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

  void _startEdit() {
    _controller.text = _lyrics;
    // Land the caret at the end rather than at 0, so typing appends to
    // existing lyrics instead of pushing text in front of the first line.
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    setState(() => _editing = true);
  }

  /// Opens the timing editor on the current lyrics. Pushed on the root
  /// navigator, so the sheet stays underneath and reappears with the new
  /// timings already applied.
  Future<void> _openSync() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LyricsSyncPage(
          track: widget.track,
          player: widget.player,
          initialLyrics: _lyrics,
          onSave: (text) async {
            await widget.onSave(text);
            if (mounted) setState(() => _lyrics = text);
          },
        ),
      ),
    );
  }

  void _cancelEdit() {
    _controller.text = _lyrics;
    FocusScope.of(context).unfocus();
    setState(() => _editing = false);
  }

  Future<void> _save() async {
    if (_saving) return;
    final text = _controller.text.trim();
    setState(() => _saving = true);
    try {
      await widget.onSave(text);
    } catch (e) {
      // Stay in the editor holding the text. Dropping back to the view on a
      // failed write would look exactly like a successful save while losing
      // everything the user just typed.
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save lyrics: $e')));
      return;
    }
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _lyrics = text;
      _editing = false;
      _saving = false;
    });
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
                  saving: _saving,
                  kind: _LyricsKind.of(_lyrics),
                  onClose: () => Navigator.of(context).pop(),
                  onSync: _lyrics.trim().isEmpty ? null : _openSync,
                  onEdit: _startEdit,
                  onCancel: _cancelEdit,
                  onSave: _save,
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
                          onAddLyrics: _startEdit,
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

/// Whether the lyrics carry timing, which decides both the badge in the header
/// and how the body is rendered.
enum _LyricsKind {
  none,
  plain,
  synced,
  wordSynced;

  static _LyricsKind of(String lyrics) {
    if (lyrics.trim().isEmpty) return none;
    final lrc = LrcParser.parse(lyrics);
    if (lrc.hasWordTiming) return wordSynced;
    if (lrc.lines.isNotEmpty) return synced;
    if (lrc.untimed.isNotEmpty) return plain;
    return none;
  }

  String? get label => switch (this) {
    none => null,
    plain => 'Plain text',
    synced => 'Synced',
    // Says why this line is lighting up a word at a time rather than all at
    // once, which otherwise looks like a rendering quirk.
    wordSynced => 'Word-synced',
  };
}

class _Header extends StatelessWidget {
  const _Header({
    required this.track,
    required this.editing,
    required this.saving,
    required this.kind,
    required this.onClose,
    required this.onSync,
    required this.onEdit,
    required this.onCancel,
    required this.onSave,
  });

  final ManifestTrack track;
  final bool editing;
  final bool saving;
  final _LyricsKind kind;
  final VoidCallback onClose;

  /// Null when there is nothing to time yet, which is the only state where
  /// the editor would open on an empty list.
  final VoidCallback? onSync;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.sm,
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
            tooltip: 'Close',
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
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        track.artistAlbumLine,
                        style: TypeScale.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Says whether tapping a line will seek. Without it the
                    // two very different bodies below look like the same
                    // screen failing to highlight anything.
                    if (!editing && kind.label != null) ...[
                      const SizedBox(width: Space.sm),
                      _Badge(kind.label!),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (editing) ...[
            TextButton(
              onPressed: saving ? null : onCancel,
              child: const Text('Cancel'),
            ),
            if (saving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: Space.md),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              TextButton(onPressed: onSave, child: const Text('Save')),
          ] else ...[
            if (onSync != null)
              IconButton(
                onPressed: onSync,
                tooltip: 'Sync to the track',
                icon: const Icon(
                  Icons.av_timer_rounded,
                  color: Tones.textMuted,
                  size: 20,
                ),
              ),
            TextButton(onPressed: onEdit, child: const Text('Edit')),
          ],
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Tones.surfaceRaised,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TypeScale.caption.copyWith(color: Tones.textMuted),
      ),
    );
  }
}

class _View extends StatefulWidget {
  const _View({
    required this.lyrics,
    required this.player,
    required this.scrollController,
    required this.onAddLyrics,
  });

  final String lyrics;
  final TunePlayer player;
  final ScrollController scrollController;
  final VoidCallback onAddLyrics;

  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> with SingleTickerProviderStateMixin {
  Lrc? _lrc;
  int? _activeIndex;
  // Drives the within-word sweep. Only the active line listens to it, so the
  // rest of the list is untouched at frame rate.
  late final PlayheadClock _playhead;

  @override
  void initState() {
    super.initState();
    _parse();
    _playhead = PlayheadClock(player: widget.player, vsync: this);
    // The line follows the same projected clock as the word sweep. It used to
    // read player.position, which is up to 250ms stale and only refreshes
    // when the player notifies -- so words glided on time while the line
    // changed late, which is the part you notice.
    _playhead.addListener(_onPlayerChange);
    widget.player.addListener(_onPlayerChange);
  }

  @override
  void didUpdateWidget(_View oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Flutter reuses this State across a rebuild, so without this a save
    // never reached the screen: parsing happened once in initState, and
    // pasting lyrics into a track that had none left the empty state up.
    if (oldWidget.lyrics != widget.lyrics) {
      setState(() {
        _parse();
        _activeIndex = null;
      });
    }
  }

  void _parse() {
    _lrc = widget.lyrics.trim().isEmpty ? null : LrcParser.parse(widget.lyrics);
  }

  @override
  void dispose() {
    widget.player.removeListener(_onPlayerChange);
    _playhead.removeListener(_onPlayerChange);
    _playhead.dispose();
    super.dispose();
  }

  void _onPlayerChange() {
    final lrc = _lrc;
    if (lrc == null || lrc.lines.isEmpty) return;
    final active = LrcParser.activeLine(lrc, _playhead.value);
    final idx = active == null ? null : lrc.lines.indexOf(active);
    if (idx != _activeIndex && mounted) {
      setState(() => _activeIndex = idx);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lrc = _lrc;
    if (lrc == null || (lrc.lines.isEmpty && lrc.untimed.isEmpty)) {
      return _Empty(onAddLyrics: widget.onAddLyrics);
    }
    if (lrc.lines.isEmpty) {
      // Plain text: no timing to follow, so it is one readable block. This
      // read `lrc.lines` before -- the timed list, which is empty in exactly
      // this case -- so pasting plain lyrics rendered a blank sheet.
      return SingleChildScrollView(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, 64),
        child: Text(
          lrc.untimed.join('\n'),
          style: TypeScale.body.copyWith(height: 1.6),
        ),
      );
    }
    final activeIdx = _activeIndex ?? -1;
    // Timed lines first, then anything still untimed. Rendering only the timed
    // ones meant that syncing a single line of a forty-line lyric hid the
    // other thirty-nine: the words were still stored, but the screen looked
    // like the save had eaten them.
    final untimedOffset = lrc.lines.length;
    return ListView.separated(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, 64),
      itemCount: untimedOffset + lrc.untimed.length,
      separatorBuilder: (_, _) => const SizedBox(height: Space.md),
      itemBuilder: (context, i) {
        if (i >= untimedOffset) {
          // Not timed yet, so there is nothing to seek to and nothing to
          // highlight. Shown at the same size, dimmed, so it reads as "this
          // part is not synced" rather than as a different kind of content.
          return Text(
            lrc.untimed[i - untimedOffset],
            style: TypeScale.title.copyWith(
              color: Tones.text.withValues(alpha: 0.55),
              height: 1.3,
            ),
          );
        }
        final line = lrc.lines[i];
        final isActive = i == activeIdx;
        final isPast = i < activeIdx;
        return GestureDetector(
          onTap: () => widget.player.seek(line.timestamp),
          child: line.hasWordTiming
              // Word-synced: sweep the highlight across the word being sung.
              ? KaraokeLine(
                  lrc: lrc,
                  lineIndex: i,
                  playhead: _playhead,
                  trackEnd: widget.player.duration,
                  isActive: isActive,
                  isPast: isPast,
                )
              : AnimatedDefaultTextStyle(
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
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAddLyrics});
  final VoidCallback onAddLyrics;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lyrics_outlined, size: 40, color: Tones.textMuted),
            const SizedBox(height: Space.md),
            Text(
              'No lyrics yet',
              style: TypeScale.title,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.xs),
            Text(
              'Paste an LRC file to follow along with the track, or paste '
              'plain text to just read it.\n\n'
              'Lyrics live in the local database and survive syncs.',
              textAlign: TextAlign.center,
              style: TypeScale.body.copyWith(color: Tones.textMuted),
            ),
            const SizedBox(height: Space.lg),
            // The Edit control is a small word in the corner. On the one
            // screen whose whole purpose is "there is nothing here yet",
            // the way forward should be the obvious thing to press.
            FilledButton.icon(
              onPressed: onAddLyrics,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add lyrics'),
            ),
          ],
        ),
      ),
    );
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
        decoration: InputDecoration(
          hintText:
              '[00:00.00]Paste LRC here, or just plain text\n'
              '[00:12.34]First line',
          hintStyle: TypeScale.body.copyWith(
            color: Tones.textMuted.withValues(alpha: 0.5),
            height: 1.4,
          ),
          border: InputBorder.none,
        ),
      ),
    );
  }
}
