import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/lyrics/lrc_parser.dart';
import '../../core/theme/tokens.dart';
import '../lyrics/lyric_follow.dart';

/// Live lyric viewport for the Now Playing page: a compact, non-scrollable
/// window (previous / active / next line) that follows the lyric playhead.
///
/// This is deliberately NOT a miniature full-lyrics page: there is no
/// scrolling, so the active line is visible by construction and nothing
/// ever fights the user. The full interactive surface is the lyrics sheet;
/// tapping anywhere here opens it via [onOpen].
///
/// The active line re-resolves every player tick, so within-line (word)
/// progression highlights live whenever the parser exposes word timing;
/// the surrounding window only changes when the active *line* changes.
/// Room for the active line to wrap to two lines before anything shrinks.
/// Named because three places have to agree: the box, the empty-state
/// placeholder that stands in for it, and the viewport that holds both.
const double _kActiveLineHeight = 44;

/// prev (20) + gap (4) + active (44) + gap (4) + next (20), plus a little
/// breathing room so the window is not flush against the transport above it.
const double _kPreviewHeight = 104;

class LyricPreview extends StatefulWidget {
  const LyricPreview({
    super.key,
    required this.lyrics,
    required this.player,
    required this.onOpen,
  });

  /// Raw lyrics blob of the current track (already resolved with user
  /// edits applied). Null/empty means no lyrics yet.
  final String? lyrics;

  final TunePlayer player;
  final VoidCallback onOpen;

  @override
  State<LyricPreview> createState() => _LyricPreviewState();
}

class _LyricPreviewState extends State<LyricPreview> {
  late Lrc? _lrc;
  late LyricFollowController _follow;

  @override
  void initState() {
    super.initState();
    _lrc = _parse(widget.lyrics);
    _follow = LyricFollowController(player: widget.player, lrc: _lrc);
    _follow.addListener(_onFollow);
  }

  @override
  void didUpdateWidget(LyricPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lyrics != widget.lyrics ||
        oldWidget.player != widget.player) {
      _follow.removeListener(_onFollow);
      _follow.dispose();
      _lrc = _parse(widget.lyrics);
      _follow = LyricFollowController(player: widget.player, lrc: _lrc);
      _follow.addListener(_onFollow);
    }
  }

  @override
  void dispose() {
    _follow.removeListener(_onFollow);
    _follow.dispose();
    super.dispose();
  }

  void _onFollow() {
    if (mounted) setState(() {});
  }

  static Lrc? _parse(String? lyrics) {
    if (lyrics == null || lyrics.isEmpty) return null;
    return LrcParser.parse(lyrics);
  }

  @override
  Widget build(BuildContext context) {
    final lrc = _lrc;
    Widget content;
    if (lrc == null || (!lrc.hasTimedLines && lrc.untimed.isEmpty)) {
      content = Text(
        'No lyrics yet. Tap to add them.',
        style: TypeScale.note.copyWith(
          fontSize: 14,
          color: Tones.textMuted.withValues(alpha: 0.7),
        ),
        textAlign: TextAlign.start,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    } else if (!lrc.hasTimedLines) {
      content = _staticExcerpt(lrc);
    } else {
      content = _liveWindow(lrc);
    }
    return Semantics(
      button: true,
      label: 'Open lyrics',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onOpen,
        // Just the words. An accent bar and an indent used to frame them as a
        // quotation; they now sit on the page like the title above them.
        child: SizedBox(
          height: _kPreviewHeight,
          child: Align(alignment: Alignment.centerLeft, child: content),
        ),
      ),
    );
  }

  /// Untimed lyrics: a static two-line excerpt, no playhead to follow.
  Widget _staticExcerpt(Lrc lrc) {
    final excerpt = lrc.untimed.take(2).join('\n');
    return Text(
      excerpt,
      style: TypeScale.note.copyWith(fontSize: 14, color: Tones.textMuted),
      textAlign: TextAlign.start,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// Timed lyrics: previous / active / next window around the playhead.
  /// Only rebuilds (and animates) when the active line changes; the
  /// active line's own text additionally refreshes per tick for word
  /// progression.
  Widget _liveWindow(Lrc lrc) {
    final active = _follow.activeIndex;
    final lines = lrc.lines;
    final prev = active == null ? null : active - 1;
    final next = active == null ? 0 : active + 1;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.25),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: Column(
        key: ValueKey<int?>(active),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dimLine(prev != null && prev >= 0 ? lines[prev].text : ''),
          const SizedBox(height: 4),
          _activeLine(lrc, active),
          const SizedBox(height: 4),
          _dimLine(next < lines.length ? lines[next].text : ''),
        ],
      ),
    );
  }

  Widget _dimLine(String text) {
    if (text.isEmpty) return const SizedBox(height: 20);
    return SizedBox(
      height: 20,
      // Shrink rather than ellipsise. A neighbouring line is context -- it says
      // what just went and what comes next -- and "Number two (Hahahaha), only
      // speak in…" answers neither question. Real lyric lines are routinely
      // wider than a phone, so clipping them was the common case, not the edge.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TypeScale.note.copyWith(fontSize: 13, color: Tones.textMuted),
          textAlign: TextAlign.start,
          maxLines: 1,
        ),
      ),
    );
  }

  /// The active line, refreshed on every position tick so word emphasis
  /// tracks the playhead when word timing is available. Falls back to the
  /// plain active style on line-synced lyrics.
  Widget _activeLine(Lrc lrc, int? active) {
    if (active == null || active < 0 || active >= lrc.lines.length) {
      return const SizedBox(height: _kActiveLineHeight);
    }
    // Two lines, and shrink-to-fit beyond that. This is the line being sung, so
    // it is the one that must never be truncated: an ellipsis here removes the
    // words the listener is looking at. Most lyric lines fit one line at this
    // size; the long ones wrap, and only a genuinely enormous line scales down.
    return SizedBox(
      height: _kActiveLineHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: ListenableBuilder(
          listenable: widget.player,
          builder: (context, _) {
            final position = widget.player.position;
            final parts = lyricWordParts(lrc, active);
            final wordIndex = lyricActiveWordIndex(lrc, active, position);
            final style = TypeScale.display.copyWith(
              fontSize: 19,
              height: 1.15,
            );
            final Widget line = (parts == null || wordIndex == null)
                ? Text(
                    lrc.lines[active].text,
                    style: style,
                    textAlign: TextAlign.start,
                    maxLines: 2,
                  )
                : Text.rich(
                    TextSpan(
                      children: _wordSpans(parts, wordIndex),
                      style: style,
                    ),
                    textAlign: TextAlign.start,
                    maxLines: 2,
                  );
            return FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: line,
            );
          },
        ),
      ),
    );
  }

  List<InlineSpan> _wordSpans(List<LyricWordPart> parts, int wordIndex) {
    final joiner = parts.any((p) => p.text.endsWith(' ')) ? '' : ' ';
    final spans = <InlineSpan>[];
    for (var i = 0; i < parts.length; i++) {
      if (i > 0 && joiner.isNotEmpty) spans.add(TextSpan(text: joiner));
      spans.add(
        TextSpan(
          text: parts[i].text,
          style: TextStyle(
            color: i <= wordIndex ? Tones.text : Tones.textMuted,
          ),
        ),
      );
    }
    return spans;
  }
}
