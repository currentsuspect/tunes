import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../audio/playhead_clock.dart';
import '../audio/tune_player.dart';
import '../theme/looks.dart';

/// Crayon's Now Playing cover (mood board, 9 Oct): the real cover drawn as
/// line art on paper, coloured in from the left as the song plays
/// (shaders/crayon_cover.frag). In any other room, or where the engine
/// cannot run shader filters (Skia, tests), it is the child unchanged, and
/// Crayon still gets its ink outline from Artwork.
class CrayonCover extends StatefulWidget {
  const CrayonCover({
    super.key,
    required this.player,
    required this.duration,
    required this.child,
  });

  final TunePlayer player;
  final Duration duration;
  final Widget child;

  @override
  State<CrayonCover> createState() => _CrayonCoverState();
}

class _CrayonCoverState extends State<CrayonCover>
    with SingleTickerProviderStateMixin {
  static ui.FragmentProgram? _program;
  static bool _loading = false;

  PlayheadClock? _clock;

  /// Progress, moved only in steps big enough to see, so the filter is not
  /// rebuilt every frame.
  final _progress = ValueNotifier<double>(0);

  bool get _active =>
      Looks.current.kind == LookKind.crayon &&
      ui.ImageFilter.isShaderFilterSupported;

  @override
  void initState() {
    super.initState();
    _ensureProgram();
    _wire();
  }

  void _ensureProgram() {
    if (_program != null || _loading || !_active) return;
    _loading = true;
    ui.FragmentProgram.fromAsset('shaders/crayon_cover.frag')
        .then((p) {
          _program = p;
          if (mounted) setState(() {});
        })
        .catchError((Object _) {
          // No shader: Crayon falls back to the outlined cover.
        });
  }

  void _wire() {
    if (!_active || _clock != null) return;
    final clock = PlayheadClock(player: widget.player, vsync: this);
    clock.addListener(() {
      final total = widget.duration.inMilliseconds;
      if (total <= 0) return;
      final p = (clock.value.inMilliseconds / total).clamp(0.0, 1.0);
      if ((p - _progress.value).abs() >= 0.004 || p == 0) _progress.value = p;
    });
    _clock = clock;
  }

  @override
  void dispose() {
    _clock?.dispose();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final program = _program;
    if (!_active || program == null) return widget.child;
    _wire();
    return ValueListenableBuilder<double>(
      valueListenable: _progress,
      child: widget.child,
      builder: (context, p, child) {
        final shader = program.fragmentShader()
          // 0 and 1 are the size, set by the engine.
          ..setFloat(2, p)
          ..setFloat(3, Looks.current.isDark ? 1 : 0);
        return ImageFiltered(
          imageFilter: ui.ImageFilter.shader(shader),
          child: child,
        );
      },
    );
  }
}
