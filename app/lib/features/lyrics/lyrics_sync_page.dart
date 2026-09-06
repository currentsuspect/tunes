import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/lyrics/lrc_parser.dart';
import '../../core/lyrics/sync_draft.dart';
import '../../core/theme/tokens.dart';
import '../../domain/manifest.dart';
import 'karaoke_line.dart';

/// Which pass the editor is on.
enum SyncMode {
  /// Timestamp each line as it starts.
  lines,

  /// Timestamp each word inside the selected line.
  words,
}

/// Times lyrics against the track by tapping along with it.
///
/// Two passes, because they are different jobs: get the lines roughly right
/// first, then refine a line word by word. Both record the playhead at the
/// moment of the tap, so nobody types a timestamp.
class LyricsSyncPage extends StatefulWidget {
  const LyricsSyncPage({
    super.key,
    required this.track,
    required this.player,
    required this.initialLyrics,
    required this.onSave,
  });

  final ManifestTrack track;
  final TunePlayer player;
  final String initialLyrics;
  final Future<void> Function(String lyrics) onSave;

  @override
  State<LyricsSyncPage> createState() => _LyricsSyncPageState();
}

class _LyricsSyncPageState extends State<LyricsSyncPage>
    with SingleTickerProviderStateMixin {
  late final PlayheadClock _playhead;
  late SyncDraft _draft;
  SyncMode _mode = SyncMode.lines;
  int _selectedLine = 0;
  bool _saving = false;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _playhead = PlayheadClock(player: widget.player, vsync: this);
    _draft = _draftFrom(widget.initialLyrics);
  }

  /// Seeds the draft from whatever is already stored, so re-opening the editor
  /// resumes a sync rather than starting over.
  SyncDraft _draftFrom(String lyrics) {
    final lrc = LrcParser.parse(lyrics);
    final source = <String>[...lrc.lines.map((l) => l.text), ...lrc.untimed];
    final draft = SyncDraft(source);
    for (var i = 0; i < lrc.lines.length; i++) {
      draft.lineStarts[i] = lrc.lines[i].timestamp;
      final words = lrc.lines[i].words;
      // Only restore word timings when they still line up with the text; a
      // later edit to the words would otherwise attach the wrong stamps.
      if (words.length == draft.wordStarts[i].length) {
        for (var w = 0; w < words.length; w++) {
          draft.wordStarts[i][w] = words[w].start;
        }
      }
    }
    return draft;
  }

  @override
  void dispose() {
    _playhead.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Duration get _now => _playhead.value;

  void _stamp() {
    setState(() {
      if (_mode == SyncMode.lines) {
        final i = _draft.nextUntimedLine;
        if (i == null) return;
        _draft.lineStarts[i] = _now;
        _selectedLine = (i + 1).clamp(0, _draft.lines.length - 1);
      } else {
        final w = _draft.nextUntimedWord(_selectedLine);
        if (w == null) return;
        _draft.wordStarts[_selectedLine][w] = _now;
      }
    });
    _scrollToCursor();
  }

  void _undo() {
    setState(() {
      if (_mode == SyncMode.lines) {
        final next = _draft.nextUntimedLine ?? _draft.lines.length;
        if (next == 0) return;
        _draft.lineStarts[next - 1] = null;
        _selectedLine = next - 1;
      } else {
        final w = _draft.nextUntimedWord(_selectedLine);
        final last = (w ?? _draft.wordStarts[_selectedLine].length) - 1;
        if (last < 0) return;
        _draft.wordStarts[_selectedLine][last] = null;
      }
    });
  }

  /// Shifts the most recently placed mark. Getting a tap 100 ms late is the
  /// normal failure, and re-timing the whole line to fix one word is not.
  void _nudge(Duration by) {
    setState(() {
      if (_mode == SyncMode.lines) {
        final next = _draft.nextUntimedLine ?? _draft.lines.length;
        if (next == 0) return;
        final cur = _draft.lineStarts[next - 1]!;
        _draft.lineStarts[next - 1] = _clampDuration(cur + by);
      } else {
        final w = _draft.nextUntimedWord(_selectedLine);
        final last = (w ?? _draft.wordStarts[_selectedLine].length) - 1;
        if (last < 0) return;
        final cur = _draft.wordStarts[_selectedLine][last]!;
        _draft.wordStarts[_selectedLine][last] = _clampDuration(cur + by);
      }
    });
  }

  Duration _clampDuration(Duration d) => d.isNegative ? Duration.zero : d;

  /// Replays from just before the selected line, which is how you check a
  /// timing rather than guessing at it.
  void _replayLine() {
    final start = _draft.lineStarts[_selectedLine];
    if (start == null) return;
    const leadIn = Duration(milliseconds: 600);
    widget.player.seek(start > leadIn ? start - leadIn : Duration.zero);
    if (!widget.player.playing) widget.player.play();
  }

  void _scrollToCursor() {
    if (!_scroll.hasClients) return;
    final i = _mode == SyncMode.lines
        ? (_draft.nextUntimedLine ?? _draft.lines.length - 1)
        : _selectedLine;
    final target = (i * 44.0) - 120;
    _scroll.animateTo(
      target.clamp(0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(_draft.toLrc());
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Lyrics that are non-empty but hold no actual lines -- a stray metadata
    // header, say -- would otherwise index straight off the end below.
    if (_draft.lines.isEmpty) {
      return Scaffold(
        backgroundColor: Tones.surface,
        appBar: AppBar(
          backgroundColor: Tones.surface,
          title: const Text('Sync lyrics', style: TypeScale.title),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Text(
              'There are no lyric lines to time yet. Add the words first, '
              'then come back and tap them in.',
              textAlign: TextAlign.center,
              style: TypeScale.body.copyWith(color: Tones.textMuted),
            ),
          ),
        ),
      );
    }
    final untimed = _draft.lines.length - _draft.timedLineCount;
    return Scaffold(
      backgroundColor: Tones.surface,
      appBar: AppBar(
        backgroundColor: Tones.surface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Sync lyrics', style: TypeScale.title),
            Text(
              widget.track.title,
              style: TypeScale.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: Space.lg),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _draft.anyTimed ? _save : null,
              child: const Text('Save'),
            ),
        ],
      ),
      body: Column(
        children: [
          _Transport(player: widget.player, playhead: _playhead),
          const Divider(height: 1, thickness: 0.5, color: Tones.hairline),
          _ModeBar(
            mode: _mode,
            canWordSync: _draft.lineStarts[_selectedLine] != null,
            onChanged: (m) => setState(() => _mode = m),
          ),
          Expanded(
            child: _mode == SyncMode.lines
                ? _LineList(
                    draft: _draft,
                    scroll: _scroll,
                    cursor: _draft.nextUntimedLine,
                    onPick: (i) => setState(() => _selectedLine = i),
                    selected: _selectedLine,
                  )
                : _WordList(
                    draft: _draft,
                    lineIndex: _selectedLine,
                    cursor: _draft.nextUntimedWord(_selectedLine),
                  ),
          ),
          if (untimed > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.xs),
              child: Text(
                '$untimed line${untimed == 1 ? '' : 's'} still untimed — '
                'they are kept, just not synced',
                style: TypeScale.caption,
              ),
            ),
          _Controls(
            mode: _mode,
            done: _mode == SyncMode.lines
                ? _draft.nextUntimedLine == null
                : _draft.nextUntimedWord(_selectedLine) == null,
            onStamp: _stamp,
            onUndo: _undo,
            onNudge: _nudge,
            onReplay: _replayLine,
          ),
        ],
      ),
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({required this.player, required this.playhead});

  final TunePlayer player;
  final ValueListenable<Duration> playhead;

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    final cs = (d.inMilliseconds.remainder(1000) ~/ 10);
    return '$m:${s.toString().padLeft(2, '0')}.${cs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Back 5 seconds',
            onPressed: () {
              final p = player.position - const Duration(seconds: 5);
              player.seek(p.isNegative ? Duration.zero : p);
            },
            icon: const Icon(Icons.replay_5_rounded, color: Tones.text),
          ),
          ListenableBuilder(
            listenable: player,
            builder: (context, _) => IconButton(
              iconSize: 36,
              onPressed: player.toggle,
              icon: Icon(
                player.playing
                    ? Icons.pause_circle_filled_rounded
                    : Icons.play_circle_fill_rounded,
                color: Tones.primary,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Forward 5 seconds',
            onPressed: () =>
                player.seek(player.position + const Duration(seconds: 5)),
            icon: const Icon(Icons.forward_5_rounded, color: Tones.text),
          ),
          const SizedBox(width: Space.sm),
          // Centiseconds, because that is the resolution being recorded and a
          // whole-second readout would hide the thing being corrected.
          ValueListenableBuilder<Duration>(
            valueListenable: playhead,
            builder: (context, pos, _) => Text(
              _fmt(pos),
              style: TypeScale.body.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeBar extends StatelessWidget {
  const _ModeBar({
    required this.mode,
    required this.canWordSync,
    required this.onChanged,
  });

  final SyncMode mode;
  final bool canWordSync;
  final ValueChanged<SyncMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.sm,
      ),
      child: SegmentedButton<SyncMode>(
        segments: [
          const ButtonSegment(value: SyncMode.lines, label: Text('Lines')),
          ButtonSegment(
            value: SyncMode.words,
            label: const Text('Words'),
            // A line has to have a start before its words can be placed
            // inside it.
            enabled: canWordSync,
          ),
        ],
        selected: {mode},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

class _LineList extends StatelessWidget {
  const _LineList({
    required this.draft,
    required this.scroll,
    required this.cursor,
    required this.onPick,
    required this.selected,
  });

  final SyncDraft draft;
  final ScrollController scroll;
  final int? cursor;
  final ValueChanged<int> onPick;
  final int selected;

  String _stamp(Duration? d) {
    if (d == null) return '--:--.--';
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    final cs = (d.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(
      2,
      '0',
    );
    return '$m:$s.$cs';
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scroll,
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
      itemCount: draft.lines.length,
      itemBuilder: (context, i) {
        final isCursor = i == cursor;
        final isSelected = i == selected;
        return InkWell(
          onTap: () => onPick(i),
          child: Container(
            height: 44,
            alignment: Alignment.centerLeft,
            decoration: isSelected
                ? BoxDecoration(
                    border: Border(
                      left: BorderSide(color: Tones.primary, width: 2),
                    ),
                  )
                : null,
            padding: const EdgeInsets.only(left: Space.sm),
            child: Row(
              children: [
                SizedBox(
                  width: 76,
                  child: Text(
                    _stamp(draft.lineStarts[i]),
                    style: TypeScale.caption.copyWith(
                      color: draft.lineStarts[i] == null
                          ? Tones.textMuted
                          : Tones.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    draft.lines[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TypeScale.body.copyWith(
                      color: isCursor
                          ? Tones.text
                          : Tones.text.withValues(alpha: 0.7),
                      fontWeight: isCursor ? FontWeight.w600 : FontWeight.w400,
                    ),
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

class _WordList extends StatelessWidget {
  const _WordList({
    required this.draft,
    required this.lineIndex,
    required this.cursor,
  });

  final SyncDraft draft;
  final int lineIndex;
  final int? cursor;

  @override
  Widget build(BuildContext context) {
    final words = draft.wordsOf(lineIndex);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Space.lg),
      child: Wrap(
        spacing: Space.sm,
        runSpacing: Space.sm,
        children: [
          for (var i = 0; i < words.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.sm,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: i == cursor
                    ? Tones.primary.withValues(alpha: 0.25)
                    : Tones.surfaceRaised,
                borderRadius: BorderRadius.circular(6),
                border: i == cursor
                    ? Border.all(color: Tones.primary, width: 1)
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(words[i], style: TypeScale.body),
                  Text(
                    draft.wordStarts[lineIndex][i] == null
                        ? '--'
                        : '${(draft.wordStarts[lineIndex][i]!.inMilliseconds / 1000).toStringAsFixed(2)}s',
                    style: TypeScale.caption.copyWith(
                      color: draft.wordStarts[lineIndex][i] == null
                          ? Tones.textMuted
                          : Tones.primary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.mode,
    required this.done,
    required this.onStamp,
    required this.onUndo,
    required this.onNudge,
    required this.onReplay,
  });

  final SyncMode mode;
  final bool done;
  final VoidCallback onStamp;
  final VoidCallback onUndo;
  final ValueChanged<Duration> onNudge;
  final VoidCallback onReplay;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.sm,
          Space.lg,
          Space.md,
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  onPressed: () => onNudge(const Duration(milliseconds: -100)),
                  icon: const Icon(Icons.remove_rounded, size: 16),
                  label: const Text('100ms'),
                ),
                TextButton.icon(
                  onPressed: onReplay,
                  icon: const Icon(Icons.replay_rounded, size: 16),
                  label: const Text('Replay'),
                ),
                TextButton.icon(
                  onPressed: () => onNudge(const Duration(milliseconds: 100)),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('100ms'),
                ),
                IconButton(
                  tooltip: 'Undo last mark',
                  onPressed: onUndo,
                  icon: const Icon(Icons.undo_rounded),
                ),
              ],
            ),
            const SizedBox(height: Space.xs),
            SizedBox(
              width: double.infinity,
              height: 64,
              child: FilledButton(
                onPressed: done ? null : onStamp,
                style: FilledButton.styleFrom(
                  backgroundColor: Tones.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(RadiusTokens.card),
                  ),
                ),
                child: Text(
                  done
                      ? 'All ${mode == SyncMode.lines ? 'lines' : 'words'} timed'
                      : mode == SyncMode.lines
                      ? 'Tap on the line'
                      : 'Tap on the word',
                  style: TypeScale.title,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
