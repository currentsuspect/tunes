import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/audio/playhead_clock.dart';
import '../../core/audio/tune_player.dart';
import '../../core/data/settings_store.dart';
import '../../core/lyrics/adlibs.dart';
import '../../core/lyrics/lrc_parser.dart';
import '../../core/lyrics/reading.dart';
import '../../core/lyrics/voices.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/tunes_menu.dart';
import '../../core/ui/track_swipe.dart';
import '../../core/ui/cover_tint.dart';
import '../../domain/manifest.dart';
import 'karaoke_line.dart';
import 'lyric_follow.dart';
import 'lyrics_sync_page.dart';

/// Bottom sheet that shows the lyrics for what is playing, with a tap-to-edit
/// toggle.
///
/// It follows the player: when the music moves on, so do the lyrics. Reading a
/// track handed over at open time was the old behaviour, and left the sheet
/// showing the previous song's words under the next song's name. The one
/// exception is while editing, when the sheet holds the track being edited so
/// a song change cannot swap the words out from under the keyboard.
///
/// When the user saves, the caller persists via the lyric-sharing path and
/// refreshes the player, which is what brings the new words back to this sheet.
class LyricsSheet extends StatefulWidget {
  const LyricsSheet({
    super.key,
    required this.track,
    required this.player,
    required this.onSave,
    this.embedded = false,
  });

  /// Set when the lyrics sit in a pane of a wide window instead of a sheet: no
  /// drag handle, no sheet, and a header that is only the menu (the player
  /// beside it already says which song this is).
  final bool embedded;

  /// What was playing when the sheet opened, used only until the player says
  /// otherwise.
  final ManifestTrack track;
  final TunePlayer player;
  final Future<void> Function(ManifestTrack track, String lyrics) onSave;

  static Future<void> show(
    BuildContext context, {
    required ManifestTrack track,
    required TunePlayer player,
    required Future<void> Function(ManifestTrack track, String lyrics) onSave,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Tones.base,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
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
  // The track on screen. Follows the player, except while editing.
  late ManifestTrack _track;
  // What this sheet has just saved, by track. A save reaches the player a beat
  // later (the store is read back and the queue refreshed), and the screen
  // should not show the old words in that gap or after a save that never
  // reaches a player at all. Dropped once the player agrees.
  final Map<String, String> _saved = {};
  late TextEditingController _controller;

  String get _lyrics => _saved[_track.sha] ?? _track.lyrics ?? '';

  @override
  void initState() {
    super.initState();
    _track = widget.player.current ?? widget.track;
    _controller = TextEditingController(text: _lyrics);
    widget.player.addListener(_onPlayer);
  }

  @override
  void dispose() {
    _embeddedScroll.dispose();
    widget.player.removeListener(_onPlayer);
    _controller.dispose();
    super.dispose();
  }

  void _onPlayer() {
    if (!mounted || _editing) return;
    final now = widget.player.current;
    if (now == null) return;
    final saved = _saved[now.sha];
    if (saved != null && (now.lyrics ?? '').trim() == saved.trim()) {
      _saved.remove(now.sha);
    }
    final moved = now.sha != _track.sha;
    final changed = (now.lyrics ?? '') != (_track.lyrics ?? '');
    if (moved || changed || now.title != _track.title) {
      setState(() => _track = now);
    }
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
    final track = _track;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LyricsSyncPage(
          track: track,
          player: widget.player,
          initialLyrics: _lyrics,
          onSave: (text) async {
            await widget.onSave(track, text);
            if (mounted) setState(() => _saved[track.sha] = text);
          },
        ),
      ),
    );
  }

  void _cancelEdit() {
    FocusScope.of(context).unfocus();
    setState(() => _editing = false);
    // The music may have moved on while typing.
    _onPlayer();
  }

  Future<void> _save() async {
    if (_saving) return;
    final text = _controller.text.trim();
    final track = _track;
    setState(() => _saving = true);
    try {
      await widget.onSave(track, text);
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
      _saved[track.sha] = text;
      _editing = false;
      _saving = false;
    });
    _onPlayer();
  }

  /// Puts one line on the left or right by writing a `v1:` / `v2:` label into
  /// it (see [LyricVoices]). Shared like any other edit, and any other LRC
  /// reader just sees a line that starts with a label.
  Future<void> _setLineVoice(Lrc lrc, int index, int? voice) async {
    final track = _track;
    final next = LyricVoices.relabel(
      _lyrics,
      lrc,
      index,
      voice,
      artists: _artistsOf(track),
    );
    if (next == null || next == _lyrics) return;
    try {
      await widget.onSave(track, next);
      if (mounted) setState(() => _saved[track.sha] = next);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save lyrics: $e')));
    }
  }

  static List<String> _artistsOf(ManifestTrack t) => [
    t.artistDisplay,
    t.primaryArtist,
    ...t.featured,
  ].whereType<String>().where((a) => a.trim().isNotEmpty).toList();

  final ScrollController _embeddedScroll = ScrollController();

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _content(context, _embeddedScroll);
    return DraggableScrollableSheet(
      initialChildSize: 0.93,
      minChildSize: 0.4,
      maxChildSize: 0.97,
      expand: false,
      builder: _content,
    );
  }

  Widget _content(BuildContext context, ScrollController scrollController) {
    // The sheet is a route of its own, outside the player's tint, so it
    // lights itself: the record's colour pouring in from the top, as on
    // Now Playing.
    return TintBuilder(
      artSha: _track.artSha,
      builder: (context, tint) => Stack(
        fit: StackFit.expand,
        children: [
          AmbientGlow(tint: tint, strength: 0.32),
          SafeArea(
            // The sheet sits below the status bar already.
            top: false,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                children: [
                  // A handle drawn on the glow, rather than the sheet's own
                  // on a solid band that cut the colour off at the top.
                  if (!widget.embedded)
                    Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.symmetric(
                        vertical: Space.sm + 2,
                      ),
                      decoration: BoxDecoration(
                        color: Tones.textMuted.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  _Header(
                    player: widget.player,
                    compact: widget.embedded,
                    track: _track,
                    editing: _editing,
                    saving: _saving,
                    kind: _LyricsKind.of(_lyrics),
                    onClose: () => Navigator.of(context).pop(),
                    onSync: _lyrics.trim().isEmpty ? null : _openSync,
                    onEdit: _startEdit,
                    onCancel: _cancelEdit,
                    onSave: _save,
                  ),
                  Expanded(
                    child: _editing
                        ? _Editor(
                            controller: _controller,
                            scrollController: scrollController,
                          )
                        : _View(
                            // A different song is a different list: new
                            // keys, new follow state, back to the top.
                            key: ValueKey(_track.sha),
                            lyrics: _lyrics,
                            artists: _artistsOf(_track),
                            player: widget.player,
                            scrollController: scrollController,
                            onAddLyrics: _startEdit,
                            onLineVoice: _setLineVoice,
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
    required this.player,
    required this.compact,
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

  final TunePlayer player;

  /// Only the menu: in a pane beside the player, the title is already there.
  final bool compact;
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

  /// One quiet line of identity: the title, and what is under it.
  Widget _identity(ManifestTrack t, String second) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        t.title,
        style: TypeScale.display.copyWith(fontSize: 20, height: 1.15),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      const SizedBox(height: 2),
      Text(
        second,
        style: TypeScale.caption,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.maybeOf(context);
    // One quiet line of identity and one menu. Everything that used to sit in
    // a row here -- cover, size, timing, edit, the sync badge -- is either the
    // same information the screen is already tinted by, or something you reach
    // for once a song, so it lives behind the menu.
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.sm, Space.sm),
      child: Row(
        children: [
          Expanded(
            child: compact && !editing
                ? const SizedBox.shrink()
                : editing
                ? _identity(track, 'Editing lyrics')
                // The same swipe as the mini bar: the song moves aside and
                // the next one slides in, and the words below follow it.
                : TrackSwipe(
                    player: player,
                    track: track,
                    builder: (context, t, _) => _identity(t, t.artistDisplay),
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
          ] else
            PopupMenuButton<String>(
              tooltip: 'Lyrics options',
              icon: Icon(Icons.more_horiz_rounded, color: Tones.textMuted),
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    onEdit();
                  case 'sync':
                    onSync?.call();
                  case 'size':
                    if (settings != null) {
                      settings.setLyricSize((settings.lyricSize + 1) % 3);
                    }
                  case 'close':
                    onClose();
                }
              },
              itemBuilder: (_) => [
                if (kind.label != null)
                  PopupMenuItem<String>(
                    enabled: false,
                    height: 32,
                    child: Text(
                      kind.label!.toUpperCase(),
                      style: TypeScale.mono.copyWith(
                        fontSize: 10,
                        color: Tones.textMuted,
                      ),
                    ),
                  ),
                tunesMenuItem(
                  'edit',
                  Icons.edit_outlined,
                  kind == _LyricsKind.none ? 'Add lyrics' : 'Edit lyrics',
                ),
                if (onSync != null)
                  tunesMenuItem(
                    'sync',
                    Icons.timer_outlined,
                    'Sync to the track',
                  ),
                if (settings != null && kind != _LyricsKind.none)
                  tunesMenuItem(
                    'size',
                    Icons.format_size_rounded,
                    'Text size · ${const ['Small', 'Medium', 'Large'][settings.lyricSize.clamp(0, 2)]}',
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _View extends StatefulWidget {
  const _View({
    super.key,
    required this.lyrics,
    required this.artists,
    required this.player,
    required this.scrollController,
    required this.onAddLyrics,
    required this.onLineVoice,
  });

  final String lyrics;

  /// The track's own artists: the only names a line label may use.
  final List<String> artists;

  /// Puts line [index] on the left (1), the right (2), or back to unlabelled.
  final Future<void> Function(Lrc lrc, int index, int? voice) onLineVoice;
  final TunePlayer player;
  final ScrollController scrollController;
  final VoidCallback onAddLyrics;

  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> with SingleTickerProviderStateMixin {
  /// The lines as shown: long ones split in two (see reading.dart).
  Lrc? _lrc;

  /// The lines as stored, and which of them each shown line came from. A
  /// voice label is written to the stored line, never to half of one.
  Lrc? _source;
  List<int> _origin = const [];
  // Who is singing each timed line, which decides the side it sits on.
  List<LyricVoice> _voices = const [];
  // Drives the within-word sweep. Only the active line listens to it, so the
  // rest of the list is untouched at frame rate.
  late final PlayheadClock _playhead;
  // Owns the active line and the follow/browse state. Fed from _playhead
  // rather than the player so the line changes on the same timebase the word
  // sweep uses -- reading player.position here would put the line back up to
  // 250ms behind the words, which is the part you notice.
  late LyricFollowController _follow;
  late List<GlobalKey> _lineKeys;

  int? get _activeIndex => _follow.activeIndex;

  /// A line played on repeat: from its first word to the end of its last,
  /// for learning a verse or hearing a word again. [origin] is the stored
  /// line, so a long line split in two loops whole.
  ({Duration from, Duration to, int origin})? _loop;

  /// Set once the loop has jumped back, until the playhead is inside it again:
  /// the clock reports the old position for a frame or two after a seek.
  bool _looped = false;

  void _checkLoop() {
    final loop = _loop;
    if (loop == null) return;
    final pos = _playhead.value;
    if (_looped) {
      if (pos < loop.to) _looped = false;
      return;
    }
    if (pos >= loop.to || pos < loop.from - const Duration(seconds: 2)) {
      _looped = true;
      widget.player.seek(loop.from);
    }
  }

  void _toggleLoop(int i) {
    final lrc = _lrc;
    if (lrc == null) return;
    final origin = _origin[i];
    if (_loop?.origin == origin) {
      setState(() => _loop = null);
      return;
    }
    final shown = [
      for (var k = 0; k < lrc.lines.length; k++)
        if (_origin[k] == origin) k,
    ];
    final first = lrc.lines[shown.first];
    final lastIndex = shown.last;
    final last = lrc.lines[lastIndex];
    final from = first.words.isEmpty
        ? first.timestamp
        : first.words.map((w) => w.start).reduce((a, b) => a < b ? a : b);
    final Duration to;
    if (last.words.isNotEmpty) {
      // A breath after the last word, so the loop does not clip it.
      to =
          lrc.wordEndOf(
            lastIndex,
            last.words.length - 1,
            trackEnd: widget.player.duration,
          ) +
          const Duration(milliseconds: 250);
    } else if (lastIndex + 1 < lrc.lines.length) {
      to = lrc.lines[lastIndex + 1].timestamp;
    } else {
      to = last.timestamp + const Duration(seconds: 5);
    }
    // A little before the line, so its first word is heard whole.
    final lead = from - const Duration(milliseconds: 150);
    setState(() {
      _loop = (
        from: lead.isNegative ? Duration.zero : lead,
        to: to,
        origin: origin,
      );
      _looped = false;
    });
    widget.player.seek(_loop!.from);
    if (!widget.player.playing) widget.player.play();
  }

  @override
  void initState() {
    super.initState();
    _parse();
    _playhead = PlayheadClock(player: widget.player, vsync: this);
    _follow = LyricFollowController(
      player: widget.player,
      lrc: _lrc,
      clock: _playhead,
    );
    _follow.addListener(_onFollowUpdate);
    _playhead.addListener(_checkLoop);
    _lineKeys = List.generate(_lrc?.lines.length ?? 0, (_) => GlobalKey());
    // Nothing else subscribes to the clock here: KaraokeLine takes it and
    // rebuilds itself through a ValueListenableBuilder, so the word sweep
    // repaints at frame rate without this State rebuilding the whole list.
    // Opening transfers into the current lyric position: settle onto the
    // active line on the first frame rather than starting at the top.
    if (_follow.activeIndex != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToActive(animated: true),
      );
    }
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
        // The controller owns the active line now, so re-anchoring goes
        // through it. The keys are per-line, so they have to be rebuilt for
        // the new line count or ensureVisible would target a stale context.
        _follow.updateLyrics(_lrc);
        _lineKeys = List.generate(_lrc?.lines.length ?? 0, (_) => GlobalKey());
      });
    }
  }

  void _parse() {
    _source = widget.lyrics.trim().isEmpty
        ? null
        : LrcParser.parse(widget.lyrics);
    final reading = _source == null
        ? null
        : splitForReading(_source!, adlibsApart: true);
    _lrc = reading?.lrc;
    _origin = reading?.origin ?? const [];
    _voices = LyricVoices.resolve([
      for (final l in _lrc?.lines ?? const <LrcLine>[]) l.text,
    ], artists: widget.artists);
  }

  @override
  void dispose() {
    _follow.removeListener(_onFollowUpdate);
    // The controller listens to the clock, so it has to let go before the
    // clock is torn down.
    _follow.dispose();
    _playhead.removeListener(_checkLoop);
    _playhead.dispose();
    super.dispose();
  }

  /// Shared follow state changed: refresh the highlight / recenter pill,
  /// and glide to the new line when following. The controller only
  /// notifies on active-index (or follow-state) change, never on every
  /// position tick, so this never stutters mid-line.
  void _onFollowUpdate() {
    if (!mounted) return;
    setState(() {});
    if (_follow.following && _follow.activeIndex != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToActive(animated: true),
      );
    }
  }

  void _scrollToActive({required bool animated, bool retry = true}) {
    if (!mounted) return;
    final idx = _follow.activeIndex;
    if (idx == null || idx < 0 || idx >= _lineKeys.length) return;
    final ctx = _lineKeys[idx].currentContext;
    if (ctx == null) {
      // The list is lazy, so a line far from the screen has not been built and
      // has nowhere to scroll to. Jump to where it ought to be by proportion,
      // which builds it, then settle exactly on the next frame. Without this,
      // opening the lyrics late in a song left them at the top while the music
      // was many lines ahead, and following never caught up.
      final c = widget.scrollController;
      if (!retry || !c.hasClients || _lineKeys.isEmpty) return;
      final pos = c.position;
      final total = pos.maxScrollExtent + pos.viewportDimension;
      final guess = total * (idx / _lineKeys.length);
      c.jumpTo(guess.clamp(0.0, pos.maxScrollExtent));
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToActive(animated: animated, retry: false),
      );
      return;
    }
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.35,
      duration: animated ? const Duration(milliseconds: 350) : Duration.zero,
      curve: Curves.easeInOut,
    );
  }

  /// A manual drag pauses following so browsing is never yanked away.
  /// When the scroll settles back on the active line, following resumes.
  /// (Programmatic glides carry no drag details, so they never pause.)
  bool _onScrollNotification(ScrollNotification n) {
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _follow.userScrolled();
    } else if (n is ScrollEndNotification) {
      // Geometry is stale until the next frame lays out the settled
      // offset, so defer the visibility check past layout.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _resumeIfActiveVisible(),
      );
    }
    return false;
  }

  void _resumeIfActiveVisible() {
    if (!mounted) return;
    if (_follow.following) return;
    final idx = _follow.activeIndex;
    if (idx == null || idx < 0 || idx >= _lineKeys.length) return;
    final ctx = _lineKeys[idx].currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject();
    final scrollable = Scrollable.of(ctx);
    final viewport = scrollable.context.findRenderObject();
    if (box is! RenderBox || viewport is! RenderBox) return;
    final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
    final extent = scrollable.position.viewportDimension;
    if (top >= -box.size.height && top + box.size.height <= extent) {
      _follow.resumeFollowing();
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
          style: TypeScale.display.copyWith(
            fontSize: _restingSize(context),
            height: 1.55,
            fontWeight: FontWeight.w400,
          ),
        ),
      );
    }
    // The no-timed-lines case is already handled above, against lrc.untimed
    // rather than a re-derived plain-text blob.
    final list = NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: _timedList(lrc),
    );
    // Paused by a manual scroll: offer an explicit way back. The pill
    // hides itself as soon as following resumes (new line, scroll-back,
    // or tap). The Stack stays mounted unconditionally: swapping the
    // list between a bare return and a Stack child would remount the
    // ListView and silently reset its scroll offset to zero.
    return Stack(
      children: [
        list,
        if (_loop != null)
          Positioned(
            left: 0,
            right: 0,
            top: Space.sm,
            child: Center(
              child: TextButton.icon(
                onPressed: () => setState(() => _loop = null),
                icon: const Icon(Icons.repeat_one_rounded, size: 16),
                label: const Text('Looping this line · Stop'),
                style: TextButton.styleFrom(
                  foregroundColor: AccentScope.of(context),
                  backgroundColor: Tones.surfaceRaised,
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.md,
                    vertical: Space.sm,
                  ),
                  shape: const StadiumBorder(),
                ),
              ),
            ),
          ),
        if (!_follow.following && _follow.activeIndex != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: Space.md,
            child: Center(
              child: TextButton.icon(
                onPressed: () {
                  _follow.resumeFollowing();
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _scrollToActive(animated: true),
                  );
                },
                icon: const Icon(Icons.my_location_rounded, size: 16),
                label: const Text('Back to current line'),
                style: TextButton.styleFrom(
                  foregroundColor: AccentScope.of(context),
                  backgroundColor: Tones.surfaceRaised,
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.md,
                    vertical: Space.sm,
                  ),
                  shape: const StadiumBorder(),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// A line-timed line with its ad-libs on a smaller row beneath (see
  /// adlibs.dart), on the side away from the lead.
  static Widget _withAdlibs(String text, TextAlign align, double size) {
    final split = splitAdlibText(text);
    if (split == null) return Text(text, textAlign: align);
    final end = align == TextAlign.end;
    // Stretched, so the ad-lib row spans the line and can sit at its far side.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(split.main, textAlign: align),
        Text(
          split.adlibs,
          textAlign: end ? TextAlign.start : TextAlign.end,
          style: TextStyle(fontSize: size * 0.72, fontStyle: FontStyle.italic),
        ),
      ],
    );
  }

  /// The size lyrics rest at: small, medium or large, from Settings.
  static double _restingSize(BuildContext context) {
    final step = SettingsScope.maybeOf(context)?.lyricSize ?? 1;
    return const [20.0, 24.0, 30.0][step];
  }

  /// How bright a line is by where it sits relative to the one being sung.
  /// Lines already sung drop away; the next few stay readable so the eye can
  /// run ahead; the rest recede.
  static double _opacityFor(int distance) {
    if (distance < 0) return 0.3;
    return switch (distance) {
      0 => 1.0,
      1 => 0.62,
      2 => 0.44,
      _ => 0.3,
    };
  }

  Widget _timedList(Lrc lrc) {
    final activeIdx = _activeIndex ?? -1;
    final rest = _restingSize(context);
    // Timed lines first, then anything still untimed. Rendering only the timed
    // ones meant that syncing a single line of a forty-line lyric hid the
    // other thirty-nine: the words were still stored, but the screen looked
    // like the save had eaten them.
    final untimedOffset = lrc.lines.length;
    return ListView.separated(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, 120),
      itemCount: untimedOffset + lrc.untimed.length,
      separatorBuilder: (_, _) => const SizedBox(height: Space.lg),
      itemBuilder: (context, i) {
        if (i >= untimedOffset) {
          // Not timed yet, so there is nothing to seek to and nothing to
          // highlight. Shown at the same size, dimmed, so it reads as "this
          // part is not synced" rather than as a different kind of content.
          return Text(
            lrc.untimed[i - untimedOffset],
            style: TypeScale.display.copyWith(
              fontSize: rest,
              color: Tones.text.withValues(alpha: 0.4),
              height: 1.25,
              fontWeight: FontWeight.w400,
            ),
          );
        }
        final line = lrc.lines[i];
        final voice = i < _voices.length
            ? _voices[i]
            : LyricVoice(LyricSide.left, line.text);
        final isActive = i == activeIdx;
        final isPast = i < activeIdx;
        final opacity = activeIdx < 0 ? 0.62 : _opacityFor(i - activeIdx);
        // The line being sung is set larger than the rest, so it is the thing
        // you read and the others are the context around it. A backing vocal
        // is always set a step down so it never competes with the lead.
        final size =
            (isActive ? rest * 1.22 : rest) * (voice.backing ? 0.82 : 1);
        final align = switch (voice.side) {
          LyricSide.left => TextAlign.start,
          LyricSide.right => TextAlign.end,
          LyricSide.center => TextAlign.center,
        };
        final alignment = switch (voice.side) {
          LyricSide.left => Alignment.centerLeft,
          LyricSide.right => Alignment.centerRight,
          LyricSide.center => Alignment.center,
        };
        final wrap = switch (voice.side) {
          LyricSide.left => WrapAlignment.start,
          LyricSide.right => WrapAlignment.end,
          LyricSide.center => WrapAlignment.center,
        };
        // The key is what _scrollToActive and _resumeIfActiveVisible resolve
        // through, so it wraps the whole row rather than the text inside it.
        return KeyedSubtree(
          key: _lineKeys[i],
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.player.seek(line.timestamp),
            // Hold a line for what you can do with it: send it to someone, or
            // say which side it is sung from.
            onLongPress: () {
              HapticFeedback.selectionClick();
              _lineMenu(lrc, i, voice);
            },
            child: Align(
              alignment: alignment,
              child: ConstrainedBox(
                // A line hugging one edge reads as a reply only if it does not
                // run all the way across to the other.
                constraints: BoxConstraints(
                  maxWidth: voice.side == LyricSide.center
                      ? double.infinity
                      : MediaQuery.of(context).size.width * 0.82,
                ),
                child: line.hasWordTiming
                    // Word-synced: sweep the highlight across the word being sung.
                    ? KaraokeLine(
                        lrc: lrc,
                        lineIndex: i,
                        playhead: _playhead,
                        onWordTap: widget.player.seek,
                        trackEnd: widget.player.duration,
                        isActive: isActive,
                        isPast: isPast,
                        restOpacity: opacity,
                        textAlign: align,
                        wrapAlignment: wrap,
                        style: TypeScale.display.copyWith(fontSize: size),
                      )
                    : AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
                        style: TypeScale.display.copyWith(
                          fontSize: size,
                          color: Tones.text.withValues(
                            alpha: opacity * (voice.backing ? 0.8 : 1),
                          ),
                          height: 1.25,
                        ),
                        textAlign: align,
                        child: _withAdlibs(voice.text, align, size),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _lineMenu(Lrc lrc, int i, LyricVoice voice) {
    final line = lrc.lines[i];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Tones.surfaceRaised,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_rounded, size: 20),
              title: const Text('Copy line'),
              onTap: () {
                Navigator.of(sheet).pop();
                Clipboard.setData(ClipboardData(text: voice.text));
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  const SnackBar(
                    content: Text('Line copied'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(
                _loop?.origin == _origin[i]
                    ? Icons.stop_rounded
                    : Icons.repeat_one_rounded,
                size: 20,
              ),
              title: Text(
                _loop?.origin == _origin[i] ? 'Stop looping' : 'Loop this line',
              ),
              onTap: () {
                Navigator.of(sheet).pop();
                _toggleLoop(i);
              },
            ),
            // A label inside a word-timed line would be swept as a word, so
            // those lines keep the side they were given.
            if (!line.hasWordTiming && !voice.backing) ...[
              if (voice.side != LyricSide.left)
                ListTile(
                  leading: const Icon(
                    Icons.format_align_left_rounded,
                    size: 20,
                  ),
                  title: const Text('Sing from the left'),
                  onTap: () {
                    Navigator.of(sheet).pop();
                    widget.onLineVoice(_source!, _origin[i], 1);
                  },
                ),
              if (voice.side != LyricSide.right)
                ListTile(
                  leading: const Icon(
                    Icons.format_align_right_rounded,
                    size: 20,
                  ),
                  title: const Text('Sing from the right'),
                  onTap: () {
                    Navigator.of(sheet).pop();
                    widget.onLineVoice(_source!, _origin[i], 2);
                  },
                ),
            ],
          ],
        ),
      ),
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
            Text(
              'No lyrics yet',
              style: TypeScale.display.copyWith(fontSize: 28),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.md),
            Text(
              'Paste an LRC file to follow along with the track, or paste '
              'plain text to just read it. Whatever you add is shared with '
              'everyone who listens.',
              textAlign: TextAlign.center,
              style: TypeScale.note.copyWith(
                fontSize: 15,
                color: Tones.textMuted,
              ),
            ),
            const SizedBox(height: Space.lg),
            // The Edit control is a small word in the corner. On the one
            // screen whose whole purpose is "there is nothing here yet",
            // the way forward should be the obvious thing to press.
            FilledButton.icon(
              onPressed: onAddLyrics,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add lyrics'),
              style: FilledButton.styleFrom(
                backgroundColor: Tones.text,
                foregroundColor: Tones.base,
              ),
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
        style: TypeScale.mono.copyWith(
          fontSize: 14,
          height: 1.5,
          color: Tones.text,
        ),
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
