import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../core/audio/playhead_clock.dart';
import '../../core/audio/tune_player.dart';
import '../../core/data/settings_store.dart';
import '../../core/lyrics/lrc_parser.dart';
import '../../core/lyrics/sync_draft.dart';
import '../../core/lyrics/word_window.dart';
import '../../core/theme/tokens.dart';
import '../../domain/manifest.dart';

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

  /// Which word the next tap writes to. Null means "the next one without a
  /// mark", which is the run-through case; picking a chip aims at that word
  /// instead, so a single bad word can be redone without re-timing the line.
  int? _selectedWord;

  /// Subtracted from the playhead on every mark.
  ///
  /// A tap is always late: the sound reaches you, you react, and the audio
  /// you heard left the decoder earlier still. The editor's readout is
  /// honest about when the button was pressed, which is precisely why the
  /// result plays back behind the vocal. Adjustable because reaction time is
  /// personal and output latency is per-device.
  Duration _tapOffset = const Duration(milliseconds: -250);

  /// Read from settings on first build and written back on change, so the
  /// value tuned in one session is the value the next one starts from.
  SettingsStore? _settings;
  bool _saving = false;

  /// Set by any action that places or moves a mark. Timing a line and then
  /// walking back out used to discard the work with no warning, which reads
  /// exactly like the save being broken.
  bool _dirty = false;
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
          draft.wordEnds[i][w] = words[w].end;
        }
      }
    }
    return draft;
  }

  @override
  void dispose() {
    _preview?.cancel();
    // The speed belongs to the editor; the song plays on at its own.
    if (_rate != 1) widget.player.setRate(1);
    _playhead.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Duration get _now => _playhead.value;

  /// The moment being recorded.
  ///
  /// Playing, it is a tap along to the music, so the tap offset takes off the
  /// reaction time. Paused, the playhead was put there on purpose -- scrubbed
  /// to the exact start or end -- and the mark is that spot, to the
  /// millisecond. Taking the offset off a scrubbed position moved every mark
  /// a quarter of a second away from where it was found (24 Oct).
  Duration get _markAt {
    if (!widget.player.playing) return _now;
    // Slowed down, a reaction costs less of the song.
    final t = _now + _tapOffset * _rate;
    return t.isNegative ? Duration.zero : t;
  }

  /// Words are timed one at a time, in two steps: find the start, then the
  /// end (word_window.dart). Nobody can tap word after word as fast as a
  /// song sings them, so each step is a small window to scrub, paused.
  WordPhase _phase = WordPhase.start;

  /// How long a window to give a word's end. Picked by the listener, kept.
  Duration _endRange = const Duration(milliseconds: 800);

  /// Playback speed in the editor: slowed, a word can be caught by ear.
  double _rate = 1;

  /// The word being timed: the one picked, else the first without a start.
  int get _word {
    final n = _draft.wordStarts[_selectedLine].length;
    final w = _selectedWord ?? _draft.nextUntimedWord(_selectedLine) ?? n - 1;
    return w.clamp(0, n - 1);
  }

  /// Where the next line starts, the far edge of a start window.
  Duration? get _lineEnd {
    for (var i = _selectedLine + 1; i < _draft.lines.length; i++) {
      final t = _draft.lineStarts[i];
      if (t != null) return t;
    }
    return null;
  }

  ({Duration from, Duration to}) get _window => wordWindow(
    _draft,
    _selectedLine,
    _word,
    _phase,
    endRange: _endRange,
    lineEnd: _lineEnd,
  );

  /// Puts the playhead at the start of the window, paused: where the sound
  /// being looked for can first be.
  void _toWindow() {
    _preview?.cancel();
    if (widget.player.playing) widget.player.pause();
    widget.player.seek(_window.from);
  }

  /// Plays the window once and comes back to where the playhead was, so a
  /// spot found by scrubbing is not lost by listening.
  void _hearWindow() {
    final w = _window;
    final back = _now;
    _preview?.cancel();
    widget.player.seek(w.from);
    if (!widget.player.playing) widget.player.play();
    final span = w.to - w.from;
    _preview = Timer(
      Duration(milliseconds: (span.inMilliseconds / _rate).round()),
      () {
        widget.player.pause();
        widget.player.seek(back >= w.from && back <= w.to ? back : w.from);
      },
    );
  }

  /// Scrubbed within the window: paused, exactly there.
  void _seekTo(Duration t) {
    _preview?.cancel();
    if (widget.player.playing) widget.player.pause();
    widget.player.seek(t.isNegative ? Duration.zero : t);
  }

  void _setEndRange(Duration r) {
    setState(() => _endRange = r);
    unawaited(_settings?.setLyricsEndRange(r) ?? Future.value());
    if (_phase == WordPhase.end) _toWindow();
  }

  void _cycleRate() {
    const rates = [1.0, 0.75, 0.5];
    final next = rates[(rates.indexOf(_rate) + 1) % rates.length];
    setState(() => _rate = next);
    widget.player.setRate(next);
  }

  /// Moves on without an end: the word then lasts until the next one starts.
  void _skipEnd() {
    final n = _draft.wordStarts[_selectedLine].length;
    final w = _word;
    setState(() {
      _phase = WordPhase.start;
      _selectedWord = w + 1 < n ? w + 1 : null;
    });
    _toWindow();
  }

  /// Plays a moment from [at] and comes back to it, so a scrubbed spot can be
  /// heard before it is marked: is this the start of the word, or just before?
  Timer? _preview;
  void _hearFrom(Duration at) {
    _preview?.cancel();
    widget.player.seek(at);
    if (!widget.player.playing) widget.player.play();
    _preview = Timer(const Duration(milliseconds: 350), () {
      widget.player.pause();
      widget.player.seek(at);
    });
  }

  /// Moves the playhead by a fine step, paused, so the next mark is exact.
  void _step(Duration by) {
    _preview?.cancel();
    if (widget.player.playing) widget.player.pause();
    final t = _now + by;
    widget.player.seek(t.isNegative ? Duration.zero : t);
  }

  void _stamp() {
    _dirty = true;
    setState(() {
      if (_mode == SyncMode.lines) {
        final i = _draft.nextUntimedLine;
        if (i == null) return;
        _draft.lineStarts[i] = _markAt;
        _selectedLine = (i + 1).clamp(0, _draft.lines.length - 1);
      } else {
        final words = _draft.wordStarts[_selectedLine];
        if (words.isEmpty) return;
        final w = _word;
        final at = _markAt;
        if (_phase == WordPhase.start) {
          words[w] = at;
          // An end left over from a different start would be wrong now.
          final end = _draft.wordEnds[_selectedLine][w];
          if (end != null && end <= at) {
            _draft.wordEnds[_selectedLine][w] = null;
          }
          // Now its end, in a window from just after this start.
          _selectedWord = w;
          _phase = WordPhase.end;
        } else {
          final start = words[w];
          if (start == null || at <= start) return;
          _draft.wordEnds[_selectedLine][w] = at;
          // Walk on, and stop at the line's end rather than wrapping round
          // and overwriting the first word.
          _selectedWord = w + 1 < words.length ? w + 1 : null;
          _phase = WordPhase.start;
        }
      }
    });
    _scrollToCursor();
    // Paused, the next step's window is put in front of you. Playing, the
    // music carries on: a live tap-along is still possible.
    if (_mode == SyncMode.words && !widget.player.playing) _toWindow();
  }

  /// Puts the playhead just before a word so it can be heard and re-timed.
  /// Aiming at a word by eye is guesswork; this is the difference between
  /// correcting a mark and inventing one.
  ///
  /// Picking a word opens its start window; picking it again, once it has a
  /// start, opens its end window. The playhead goes to the window, paused --
  /// not back to the start of the line.
  void _auditionWord(int index) {
    final hasStart = _draft.wordStarts[_selectedLine][index] != null;
    setState(() {
      final again = _selectedWord == index;
      _selectedWord = index;
      _phase = again && hasStart && _phase == WordPhase.start
          ? WordPhase.end
          : WordPhase.start;
    });
    _toWindow();
  }

  /// Same idea for a whole line: select it and play from just before it.
  void _auditionLine(int index) {
    setState(() {
      _selectedLine = index;
      _selectedWord = null;
    });
    final at = _draft.lineStarts[index];
    if (at == null) return;
    const leadIn = Duration(milliseconds: 700);
    widget.player.seek(at > leadIn ? at - leadIn : Duration.zero);
    if (!widget.player.playing) widget.player.play();
  }

  /// The line a correction applies to: whichever is selected if it carries a
  /// mark, otherwise the last one placed.
  ///
  /// Walking back from the cursor was not enough. `nextUntimedLine` skips
  /// section headers, so the slot behind the cursor could be a header --
  /// clearing it did nothing, the cursor did not move, and undo stopped dead
  /// after one step.
  int? _targetLine() {
    final sel = _selectedLine;
    if (!_draft.isHeaderAt(sel) && _draft.lineStarts[sel] != null) return sel;
    return _lastMarkedLine();
  }

  int? _lastMarkedLine() => _draft.lastMarkedLine;

  /// The word a correction applies to. Picking a chip aims here, so undo and
  /// the nudge act on the word being listened to rather than on whichever one
  /// happened to be placed last.
  int? _targetWord() {
    final words = _draft.wordStarts[_selectedLine];
    final sel = _selectedWord;
    if (sel != null && sel < words.length && words[sel] != null) return sel;
    return _draft.lastMarkedWord(_selectedLine);
  }

  void _undo() {
    setState(() {
      if (_mode == SyncMode.lines) {
        final i = _targetLine();
        if (i == null) return;
        _dirty = true;
        _draft.lineStarts[i] = null;
        _selectedLine = i;
      } else {
        final w = _targetWord();
        if (w == null) return;
        _dirty = true;
        // An end goes first: undoing a slipped End must not lose the start
        // that was found by ear.
        if (_draft.wordEnds[_selectedLine][w] != null) {
          _draft.wordEnds[_selectedLine][w] = null;
          _selectedWord = w;
          _phase = WordPhase.end;
          return;
        }
        _draft.wordStarts[_selectedLine][w] = null;
        _phase = WordPhase.start;
        // Leave the cursor on the word just cleared, so undo then re-tap
        // fixes one word without disturbing the rest.
        _selectedWord = w;
      }
    });
  }

  /// Shifts one mark. Being a beat late on a single word is the normal
  /// failure; re-timing the line around it is not.
  void _nudge(Duration by) {
    setState(() {
      if (_mode == SyncMode.lines) {
        final i = _targetLine();
        if (i == null) return;
        _dirty = true;
        _draft.lineStarts[i] = _clampDuration(_draft.lineStarts[i]! + by);
      } else {
        final w = _targetWord();
        if (w == null) return;
        _dirty = true;
        final words = _draft.wordStarts[_selectedLine];
        words[w] = _clampDuration(words[w]! + by);
        _selectedWord = w;
      }
    });
  }

  Duration _clampDuration(Duration d) => d.isNegative ? Duration.zero : d;

  /// Moves every mark at once. Tapping along runs consistently late -- you
  /// hear the line, then you press -- so the whole take is usually a beat
  /// behind rather than any single mark being wrong.
  /// Only affects marks made from here on; existing ones are left alone so
  /// tuning the offset never silently rewrites work already done.
  void _adjustTapOffset(Duration by) {
    setState(() {
      final next = _tapOffset + by;
      // Beyond a second in either direction it is no longer latency.
      _tapOffset = next < const Duration(seconds: -1)
          ? const Duration(seconds: -1)
          : next > const Duration(seconds: 1)
          ? const Duration(seconds: 1)
          : next;
    });
    // Persisted so it survives leaving the editor; tuning it every session
    // would defeat the point of it being adjustable at all.
    unawaited(_settings?.setLyricsTapOffset(_tapOffset) ?? Future.value());
  }

  void _shiftAll(Duration by) {
    _dirty = true;
    setState(() => _draft.shiftAll(by));
  }

  /// Replays from just before the selected line, which is how you check a
  /// timing rather than guessing at it.
  void _replayLine() {
    if (_mode == SyncMode.words) return _hearWindow();
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
    _dirty = false;
    Navigator.of(context).pop();
  }

  /// Asked when leaving with marks that were never written. Three ways out,
  /// because discarding by accident is the expensive one: keep editing, throw
  /// the marks away deliberately, or save and go.
  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Tones.surfaceRaised,
        title: Text('Keep these timings?', style: TypeScale.title),
        content: Text(
          'You have timed ${_draft.timedLineCount} '
          'line${_draft.timedLineCount == 1 ? '' : 's'} that have not been '
          'saved yet.',
          style: TypeScale.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('stay'),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('discard'),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (choice == 'save') {
      await _save();
      return false;
    }
    return choice == 'discard';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = SettingsScope.maybeOf(context);
    if (settings != null && _settings == null) {
      _settings = settings;
      _tapOffset = settings.lyricsTapOffset;
      _endRange = settings.lyricsEndRange;
    }
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
          title: Text('Sync lyrics', style: TypeScale.title),
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
    final untimed = _draft.untimedLineCount;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Resolved before the await so no BuildContext is used across the
        // gap; the dialog can outlive this frame.
        final navigator = Navigator.of(context);
        if (await _confirmLeave()) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: Tones.surface,
        appBar: AppBar(
          backgroundColor: Tones.surface,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Sync lyrics', style: TypeScale.title),
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
            _Transport(
              player: widget.player,
              playhead: _playhead,
              rate: _rate,
              onRate: _cycleRate,
            ),
            _Scrubber(player: widget.player, playhead: _playhead),
            if (_mode == SyncMode.words &&
                _draft.wordStarts[_selectedLine].isNotEmpty)
              _WindowScrub(
                window: _window,
                playhead: _playhead,
                marks: [
                  for (final t in [
                    ..._draft.wordStarts[_selectedLine],
                    ..._draft.wordEnds[_selectedLine],
                  ])
                    ?t,
                ],
                onSeek: _seekTo,
                onStep: _step,
                onRelease: () => _hearFrom(_now),
              )
            else
              _FineScrub(
                playhead: _playhead,
                onStep: _step,
                onRelease: () => _hearFrom(_now),
              ),
            Divider(height: 1, thickness: 0.5, color: Tones.hairline),
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
                      onPick: _auditionLine,
                      selected: _selectedLine,
                    )
                  : _WordList(
                      draft: _draft,
                      lineIndex: _selectedLine,
                      cursor:
                          _selectedWord ??
                          _draft.nextUntimedWord(_selectedLine),
                      onPick: _auditionWord,
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
                  : _draft.wordStarts[_selectedLine].isEmpty ||
                        _selectedWord == null &&
                            _draft.nextUntimedWord(_selectedLine) == null &&
                            _phase == WordPhase.start,
              primary: _mode == SyncMode.lines
                  ? 'Tap on the line'
                  : _draft.wordStarts[_selectedLine].isEmpty
                  ? 'No words on this line'
                  : _phase == WordPhase.start
                  ? 'Mark the start of “${_draft.wordsOf(_selectedLine)[_word]}”'
                  : 'Mark the end of “${_draft.wordsOf(_selectedLine)[_word]}”',
              wordStep:
                  _mode == SyncMode.words &&
                      _draft.wordStarts[_selectedLine].isNotEmpty
                  ? _WordStep(
                      phase: _phase,
                      endRange: _endRange,
                      onHear: _hearWindow,
                      onRange: _setEndRange,
                      onSkipEnd: _skipEnd,
                    )
                  : null,
              onStamp: _stamp,
              onUndo: _undo,
              onNudge: _nudge,
              onShiftAll: _shiftAll,
              onTapOffset: _adjustTapOffset,
              tapOffset: _tapOffset,
              onReplay: _replayLine,
            ),
          ],
        ),
      ),
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({
    required this.player,
    required this.playhead,
    required this.rate,
    required this.onRate,
  });

  final TunePlayer player;
  final ValueListenable<Duration> playhead;
  final double rate;
  final VoidCallback onRate;

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    final ms = d.inMilliseconds.remainder(1000);
    return '$m:${s.toString().padLeft(2, '0')}.${ms.toString().padLeft(3, '0')}';
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
            icon: Icon(Icons.replay_5_rounded, color: Tones.text),
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
            icon: Icon(Icons.forward_5_rounded, color: Tones.text),
          ),
          const SizedBox(width: Space.sm),
          // Milliseconds, because that is the resolution being recorded and a
          // coarser readout would hide the thing being corrected.
          ValueListenableBuilder<Duration>(
            valueListenable: playhead,
            builder: (context, pos, _) => Text(
              _fmt(pos),
              style: TypeScale.body.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          // Slower, so a word can be caught. The pitch stays put.
          TextButton(
            onPressed: onRate,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(44, 36),
            ),
            child: Text(
              rate == 1
                  ? '1×'
                  : rate == 0.75
                  ? '¾×'
                  : '½×',
            ),
          ),
        ],
      ),
    );
  }
}

/// A scrubber for the editor.
///
/// Auditioning a word drops the playhead wherever that word is, and without
/// this the only ways back were five seconds at a time or another word to
/// aim at. Timing by ear needs to be able to go anywhere in the track.
class _Scrubber extends StatelessWidget {
  const _Scrubber({required this.player, required this.playhead});

  final TunePlayer player;
  final ValueListenable<Duration> playhead;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final total = player.duration.inMilliseconds;
        if (total <= 0) return const SizedBox(height: Space.sm);
        return ValueListenableBuilder<Duration>(
          valueListenable: playhead,
          builder: (context, pos, _) {
            final max = total.toDouble();
            return SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                activeTrackColor: Tones.primary,
                inactiveTrackColor: Tones.surfaceRaised,
                thumbColor: Tones.primary,
                overlayColor: Tones.primary.withValues(alpha: 0.15),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                // The projected playhead can read a few ms past the end
                // between position reports, and Slider asserts rather than
                // clamping.
                value: pos.inMilliseconds.clamp(0, total).toDouble(),
                max: max,
                onChanged: (v) =>
                    player.seek(Duration(milliseconds: v.round())),
              ),
            );
          },
        );
      },
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
        // Headers are never tapped, so they show no timestamp slot at all.
        // Leaving an empty one made them look like work still to do, which is
        // how they ended up being timed in the first place.
        if (draft.isHeaderAt(i)) {
          return Container(
            height: 44,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: Space.sm),
            child: Text(
              draft.lines[i],
              style: TypeScale.caption.copyWith(
                color: Tones.textMuted,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          );
        }
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
    required this.onPick,
  });

  final SyncDraft draft;
  final int lineIndex;
  final int? cursor;
  final ValueChanged<int> onPick;

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
            // Tapping a word plays from just before it. Re-timing one word by
            // eye is guesswork; hearing it first is the whole point.
            InkWell(
              onTap: () => onPick(i),
              borderRadius: BorderRadius.circular(6),
              child: Container(
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
                      _span(
                        draft.wordStarts[lineIndex][i],
                        draft.wordEnds[lineIndex][i],
                      ),
                      style: TypeScale.caption.copyWith(
                        color: draft.wordStarts[lineIndex][i] == null
                            ? Tones.textMuted
                            : Tones.primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "12.345" or "12.345–12.610": a word's start, and its end once marked.
String _span(Duration? start, Duration? end) {
  String s(Duration d) => (d.inMilliseconds / 1000).toStringAsFixed(3);
  if (start == null) return '--';
  return end == null ? s(start) : '${s(start)}–${s(end)}';
}

/// Fine scrubbing: drag along the strip and the playhead moves 5 ms per
/// pixel, paused, so the exact first sound of a word can be found by ear. Let
/// go and a moment plays from there and comes back, which is how you hear
/// whether you are on the word or just before it. The arrows step 10 ms.
///
/// The track scrubber above is half a second per pixel on a phone: fine for
/// getting near a line, useless for the start of a syllable.
class _FineScrub extends StatefulWidget {
  const _FineScrub({
    required this.playhead,
    required this.onStep,
    required this.onRelease,
  });

  final ValueListenable<Duration> playhead;
  final ValueChanged<Duration> onStep;
  final VoidCallback onRelease;

  @override
  State<_FineScrub> createState() => _FineScrubState();
}

class _FineScrubState extends State<_FineScrub> {
  static const _msPerPixel = 5.0;
  double _carry = 0;
  double _offset = 0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.md),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back 10 ms',
            visualDensity: VisualDensity.compact,
            onPressed: () => widget.onStep(const Duration(milliseconds: -10)),
            icon: Icon(Icons.chevron_left_rounded, color: Tones.text),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) {
                _carry += d.delta.dx * _msPerPixel;
                final whole = _carry.truncate();
                if (whole != 0) {
                  _carry -= whole;
                  widget.onStep(Duration(milliseconds: whole));
                }
                setState(() => _offset += d.delta.dx);
              },
              onHorizontalDragEnd: (_) {
                _carry = 0;
                widget.onRelease();
              },
              child: SizedBox(
                height: 36,
                child: CustomPaint(
                  painter: _TicksPainter(
                    offset: _offset,
                    color: Tones.textMuted,
                    accent: Tones.primary,
                  ),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      'drag to fine-tune',
                      style: TypeScale.caption.copyWith(
                        color: Tones.textMuted.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Forward 10 ms',
            visualDensity: VisualDensity.compact,
            onPressed: () => widget.onStep(const Duration(milliseconds: 10)),
            icon: Icon(Icons.chevron_right_rounded, color: Tones.text),
          ),
        ],
      ),
    );
  }
}

/// A ruler that slides under the finger: ticks every 10 px, a taller one
/// every 50, and a fixed centre line marking the playhead.
class _TicksPainter extends CustomPainter {
  _TicksPainter({
    required this.offset,
    required this.color,
    required this.accent,
  });

  final double offset;
  final Color color;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final tick = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    final shift = offset % 50;
    for (var x = shift - 50; x < size.width + 50; x += 10) {
      final major = ((x - shift) / 10).round() % 5 == 0;
      final h = major ? size.height * 0.5 : size.height * 0.25;
      canvas.drawLine(Offset(x, size.height - h), Offset(x, size.height), tick);
    }
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      Paint()
        ..color = accent
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_TicksPainter old) => old.offset != offset;
}

/// The step being timed, and what helps with it: hear the window, choose how
/// long an end window is (kept for next time), or move on without an end.
class _WordStep extends StatelessWidget {
  const _WordStep({
    required this.phase,
    required this.endRange,
    required this.onHear,
    required this.onRange,
    required this.onSkipEnd,
  });

  final WordPhase phase;
  final Duration endRange;
  final VoidCallback onHear;
  final ValueChanged<Duration> onRange;
  final VoidCallback onSkipEnd;

  @override
  Widget build(BuildContext context) {
    String label(Duration d) =>
        '${(d.inMilliseconds / 1000).toStringAsFixed(d.inMilliseconds % 1000 == 0 ? 0 : 1)}s';
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Column(
        children: [
          Row(
            children: [
              TextButton.icon(
                style: _compact,
                onPressed: onHear,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Hear this bit'),
              ),
              const Spacer(),
              if (phase == WordPhase.end)
                TextButton(
                  style: _compact,
                  onPressed: onSkipEnd,
                  child: const Text('No end, next word'),
                ),
            ],
          ),
          if (phase == WordPhase.end)
            Row(
              children: [
                Text('End window', style: TypeScale.caption),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    children: [
                      for (final r in kEndRanges)
                        ChoiceChip(
                          label: Text(label(r)),
                          selected: r == endRange,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => onRange(r),
                        ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// The scrubber for one step of a word: the whole strip is the window (from
/// the last mark to the end of the line for a start; a picked length after
/// the start for an end), so a drag across it is fine-grained however long
/// the song. Drag or tap anywhere to go there, paused; let go and a moment
/// plays. Other marks on the line show as ticks.
class _WindowScrub extends StatelessWidget {
  const _WindowScrub({
    required this.window,
    required this.playhead,
    required this.marks,
    required this.onSeek,
    required this.onStep,
    required this.onRelease,
  });

  final ({Duration from, Duration to}) window;
  final ValueListenable<Duration> playhead;
  final List<Duration> marks;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<Duration> onStep;
  final VoidCallback onRelease;

  String _s(Duration d) => (d.inMilliseconds / 1000).toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final span = (window.to - window.from).inMilliseconds;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.md),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back 10 ms',
            visualDensity: VisualDensity.compact,
            onPressed: () => onStep(const Duration(milliseconds: -10)),
            icon: Icon(Icons.chevron_left_rounded, color: Tones.text),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                Duration at(double x) =>
                    window.from +
                    Duration(
                      milliseconds: (span * (x / box.maxWidth).clamp(0.0, 1.0))
                          .round(),
                    );
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => onSeek(at(d.localPosition.dx)),
                  onTapUp: (_) => onRelease(),
                  onHorizontalDragUpdate: (d) => onSeek(at(d.localPosition.dx)),
                  onHorizontalDragEnd: (_) => onRelease(),
                  child: ValueListenableBuilder<Duration>(
                    valueListenable: playhead,
                    builder: (context, pos, _) => SizedBox(
                      height: 44,
                      child: CustomPaint(
                        painter: _WindowPainter(
                          from: window.from,
                          to: window.to,
                          playhead: pos,
                          marks: marks,
                          color: Tones.textMuted,
                          accent: Tones.primary,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_s(window.from), style: TypeScale.caption),
                              const Spacer(),
                              Text(_s(window.to), style: TypeScale.caption),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            tooltip: 'Forward 10 ms',
            visualDensity: VisualDensity.compact,
            onPressed: () => onStep(const Duration(milliseconds: 10)),
            icon: Icon(Icons.chevron_right_rounded, color: Tones.text),
          ),
        ],
      ),
    );
  }
}

class _WindowPainter extends CustomPainter {
  _WindowPainter({
    required this.from,
    required this.to,
    required this.playhead,
    required this.marks,
    required this.color,
    required this.accent,
  });

  final Duration from;
  final Duration to;
  final Duration playhead;
  final List<Duration> marks;
  final Color color;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final span = (to - from).inMilliseconds;
    if (span <= 0) return;
    double x(Duration t) => (t - from).inMilliseconds / span * size.width;
    final base = size.height - 2;
    final tick = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    // A tick every 50 ms, taller every 250: the ruler says how much a drag is.
    final firstTick = (from.inMilliseconds ~/ 50 + 1) * 50;
    for (var t = firstTick; t < to.inMilliseconds; t += 50) {
      final major = t % 250 == 0;
      final px = x(Duration(milliseconds: t));
      canvas.drawLine(
        Offset(px, base - (major ? 12 : 6)),
        Offset(px, base),
        tick,
      );
    }
    canvas.drawLine(
      Offset(0, base),
      Offset(size.width, base),
      tick..strokeWidth = 1.5,
    );
    final mark = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 2;
    for (final m in marks) {
      if (m < from || m > to) continue;
      canvas.drawLine(Offset(x(m), base - 18), Offset(x(m), base), mark);
    }
    if (playhead >= from && playhead <= to) {
      final px = x(playhead);
      canvas.drawLine(
        Offset(px, 14),
        Offset(px, size.height),
        Paint()
          ..color = accent
          ..strokeWidth = 2.5,
      );
      canvas.drawCircle(Offset(px, 14), 5, Paint()..color = accent);
    }
  }

  @override
  bool shouldRepaint(_WindowPainter old) =>
      old.playhead != playhead ||
      old.from != from ||
      old.to != to ||
      old.marks.length != marks.length;
}

/// Buttons for the nudge row: four have to sit side by side on a phone.
final ButtonStyle _compact = TextButton.styleFrom(
  visualDensity: VisualDensity.compact,
  padding: const EdgeInsets.symmetric(horizontal: 8),
  minimumSize: const Size(0, 36),
);

class _Controls extends StatelessWidget {
  const _Controls({
    required this.mode,
    required this.done,
    required this.primary,
    required this.wordStep,
    required this.onStamp,
    required this.onUndo,
    required this.onNudge,
    required this.onShiftAll,
    required this.onTapOffset,
    required this.tapOffset,
    required this.onReplay,
  });

  final SyncMode mode;
  final bool done;
  final String primary;
  final Widget? wordStep;
  final VoidCallback onStamp;
  final VoidCallback onUndo;
  final ValueChanged<Duration> onNudge;
  final ValueChanged<Duration> onShiftAll;
  final ValueChanged<Duration> onTapOffset;
  final Duration tapOffset;
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
                // How early each new mark is placed. A tap is always late:
                // the sound arrives, you react, and what you heard left the
                // decoder earlier still. Shown as a number because it is the
                // one setting worth tuning once and then trusting.
                _Stepper(
                  // Only taps made while playing; a paused mark is exact.
                  label: 'Tap delay',
                  value:
                      '${(tapOffset.inMilliseconds / 1000).toStringAsFixed(2)}s',
                  onLess: () => onTapOffset(const Duration(milliseconds: -50)),
                  onMore: () => onTapOffset(const Duration(milliseconds: 50)),
                ),
                // Everything at once, not just the last mark. Fixing forty
                // lines one at a time is not a workflow.
                _Stepper(
                  label: 'Shift all',
                  value: null,
                  onLess: () => onShiftAll(const Duration(milliseconds: -100)),
                  onMore: () => onShiftAll(const Duration(milliseconds: 100)),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // The selected mark, 10 ms at a time: marks are exact now, so
                // a correction is a hair, not a tenth of a second. Text only,
                // which also keeps the row inside a 412-wide phone.
                TextButton(
                  style: _compact,
                  onPressed: () => onNudge(const Duration(milliseconds: -10)),
                  child: const Text('−10 ms'),
                ),
                TextButton(
                  style: _compact,
                  onPressed: onReplay,
                  child: const Text('Replay'),
                ),
                TextButton(
                  style: _compact,
                  onPressed: () => onNudge(const Duration(milliseconds: 10)),
                  child: const Text('+10 ms'),
                ),
                IconButton(
                  tooltip: 'Undo last mark',
                  onPressed: onUndo,
                  icon: const Icon(Icons.undo_rounded),
                ),
              ],
            ),
            const SizedBox(height: Space.xs),
            ?wordStep,
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
                      : primary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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

/// Label, optional readout, and a minus/plus pair. Used for the two settings
/// that need adjusting mid-flow without leaving the editor.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.onLess,
    required this.onMore,
  });

  final String label;
  final String? value;
  final VoidCallback onLess;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TypeScale.caption),
        if (value != null) ...[
          const SizedBox(width: 4),
          Text(
            value!,
            style: TypeScale.caption.copyWith(
              color: Tones.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
        IconButton(
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          onPressed: onLess,
          icon: const Icon(Icons.remove_rounded, size: 18),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          onPressed: onMore,
          icon: const Icon(Icons.add_rounded, size: 18),
        ),
      ],
    );
  }
}
