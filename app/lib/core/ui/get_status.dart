import 'package:flutter/material.dart';

import '../../domain/manifest.dart';
import '../../domain/soulseek.dart';
import '../theme/looks.dart';
import '../theme/tokens.dart';
import 'crayon_marks.dart';

/// "1st", "2nd", "3rd", "11th".
String ordinal(int n) {
  final teen = n % 100 >= 11 && n % 100 <= 13;
  final suffix = teen
      ? 'th'
      : switch (n % 10) {
          1 => 'st',
          2 => 'nd',
          3 => 'rd',
          _ => 'th',
        };
  return '$n$suffix';
}

/// Where a get is, in a few words, the same on every screen that shows one
/// (search, an album's missing songs, the line). Null before it is asked for.
///
/// The words used to differ by screen ("waiting its turn", "waiting…",
/// "waiting") and none said how long the wait was: a song asked for behind
/// four others looked stuck (owner, 24 Oct).
String? getNote(GetJob? j) {
  if (j == null) return null;
  return switch (j.state) {
    GetState.queued =>
      j.position == null
          ? 'waiting in line'
          : '${ordinal(j.position!)} in line',
    GetState.searching => 'looking for a copy',
    GetState.downloading =>
      j.progress == null
          ? 'getting it'
          : 'getting it · ${(j.progress! * 100).round()}%',
    GetState.checking => 'checking it',
    GetState.done => 'in your library',
    GetState.failed => "that copy didn't work",
    GetState.notFound => 'nobody has it right now',
    GetState.cancelled => 'taken out of the line',
  };
}

/// The one control for a song that can be got: Get, then its place in line,
/// then how far, then Play once it is in the library. Try again after a
/// failure.
class GetAction extends StatelessWidget {
  const GetAction({
    super.key,
    required this.title,
    required this.job,
    required this.onGet,
    this.playable,
    this.onPlay,
  });

  final String title;
  final GetJob? job;

  /// Null where a Get is not offered (Soulseek is not set up).
  final VoidCallback? onGet;

  /// The song in the library, once it is there.
  final ManifestTrack? playable;
  final void Function(ManifestTrack)? onPlay;

  bool get _crayon => Looks.current.kind == LookKind.crayon;

  @override
  Widget build(BuildContext context) {
    final j = job;
    final t = playable;
    if (t != null && onPlay != null) {
      return _Round(tooltip: 'Play $title', onTap: () => onPlay!(t));
    }
    if (j != null && j.state == GetState.queued) {
      return _LinePill(position: j.position);
    }
    if (j != null && !j.finished) {
      return SizedBox.square(
        dimension: 44,
        child: Center(
          child: _crayon
              ? CrayonDownloadFace(
                  state: CrayonDownloadState.running,
                  progress: j.state == GetState.downloading ? j.progress : null,
                  size: 32,
                )
              : SizedBox.square(
                  dimension: 26,
                  child: CircularProgressIndicator(
                    value: j.state == GetState.downloading ? j.progress : null,
                    strokeWidth: 2.6,
                    color: Tones.held,
                    backgroundColor: Tones.hairline,
                  ),
                ),
        ),
      );
    }
    if (j != null && j.state == GetState.done) {
      // Landed, but the library on this phone has not caught up yet.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.sm),
        child: Text('adding…', style: TypeScale.caption),
      );
    }
    final get = onGet;
    if (get == null) return const SizedBox.shrink();
    return GetButton(
      label: j == null ? 'Get' : 'Try again',
      onTap: get,
      tooltip: 'Get $title',
    );
  }
}

/// Get, drawn once for every screen.
class GetButton extends StatelessWidget {
  const GetButton({
    super.key,
    required this.onTap,
    this.label = 'Get',
    this.tooltip,
  });

  final VoidCallback onTap;
  final String label;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final crayon = Looks.current.kind == LookKind.crayon;
    // Crayon: ink filled, paper words, a crayon edge underneath. The others:
    // the look's own accent.
    final fill = crayon ? Tones.text : Tones.primary;
    final ink = crayon ? Tones.base : Tones.onPrimary;
    final radius = crayon ? 12.0 : RadiusTokens.control;
    final button = Container(
      decoration: crayon
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              boxShadow: [
                BoxShadow(
                  color: Looks.current.crayons[0],
                  offset: const Offset(2, 2),
                ),
              ],
            )
          : null,
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: crayon
              ? BorderSide(color: Tones.text, width: 2)
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40, minWidth: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: TypeScale.title.copyWith(fontSize: 14, color: ink),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class _LinePill extends StatelessWidget {
  const _LinePill({required this.position});

  final int? position;

  @override
  Widget build(BuildContext context) {
    final crayon = Looks.current.kind == LookKind.crayon;
    final p = position;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: crayon ? Tones.surface : Tones.surfaceRaised,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: crayon ? Tones.text : Tones.hairline,
          width: crayon ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_rounded, size: 14, color: Tones.text),
          const SizedBox(width: 5),
          Text(
            p == null ? 'in line' : '${ordinal(p)} in line',
            style: TypeScale.caption.copyWith(
              fontSize: 12.5,
              color: Tones.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({required this.tooltip, required this.onTap});

  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Tones.text,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: 44,
            child: Icon(Icons.play_arrow_rounded, color: Tones.base),
          ),
        ),
      ),
    );
  }
}
