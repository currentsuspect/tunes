import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/manifest.dart';
import '../../domain/soulseek.dart';
import '../data/gets.dart';
import '../theme/looks.dart';
import '../theme/tokens.dart';

/// Getting from Soulseek, shown from anywhere (owner, 23 Oct: "added
/// Desperado using slsk, where do I see prog").
///
/// The downloads bar's twin: above the mini bar while a get is going, with
/// the song and how far, and one tap to the list of the day's gets. It
/// leaves when nothing is going.
class GetsBar extends StatelessWidget {
  const GetsBar({super.key, required this.gets, required this.onTap});

  final GetsController gets;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return ListenableBuilder(
      listenable: gets,
      builder: (context, _) {
        final active = gets.active;
        final show = active.isNotEmpty;
        return SizedBox(
          width: double.infinity,
          child: ClipRect(
            child: AnimatedAlign(
              duration: still
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomCenter,
              heightFactor: show ? 1 : 0,
              child: show
                  ? _Body(active: active, onTap: onTap)
                  : const SizedBox(width: double.infinity),
            ),
          ),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.active, required this.onTap});

  final List<GetJob> active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The one moving, else the next in line.
    final lead = active.firstWhere(
      (j) => j.state != GetState.queued,
      orElse: () => active.last,
    );
    final more = active.length - 1;
    final text = [
      'Getting ${lead.title}',
      if (more > 0) '+$more more',
    ].join(' · ');
    final p = lead.progress;
    final crayon = Looks.current.kind == LookKind.crayon;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.sm + 2,
        Space.sm,
        Space.sm + 2,
        0,
      ),
      child: Material(
        color: Tones.surfaceRaised,
        borderRadius: BorderRadius.circular(RadiusTokens.control),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: crayon ? Tones.text : Tones.hairline,
                width: crayon ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(RadiusTokens.control),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.md,
                    vertical: Space.sm,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.travel_explore_rounded,
                        size: 18,
                        color: crayon ? Tones.text : Tones.primary,
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Text(
                          text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TypeScale.caption.copyWith(color: Tones.text),
                        ),
                      ),
                      Text(
                        stateLabel(lead),
                        style: TypeScale.mono.copyWith(color: Tones.text),
                      ),
                      const SizedBox(width: Space.xs),
                      Icon(
                        Icons.keyboard_arrow_up_rounded,
                        size: 18,
                        color: Tones.textMuted,
                      ),
                    ],
                  ),
                ),
                LinearProgressIndicator(
                  value: lead.state == GetState.downloading ? p : null,
                  minHeight: 2,
                  color: Tones.held,
                  backgroundColor: Tones.hairline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A get's state in a few words.
String stateLabel(GetJob j) => switch (j.state) {
  GetState.queued => 'waiting',
  GetState.searching => 'looking',
  GetState.downloading =>
    j.progress == null ? 'getting' : '${(j.progress! * 100).round()}%',
  GetState.checking => 'checking',
  GetState.done => 'in your library',
  GetState.failed => "didn't work",
  GetState.notFound => 'nobody has it',
};

/// The day's gets on the box, everyone's, newest first, kept fresh while
/// open: what is coming, what came, and what could not be found.
class GetsSheet extends StatefulWidget {
  const GetsSheet({
    super.key,
    required this.gets,
    required this.trackFor,
    required this.onPlay,
  });

  final GetsController gets;
  final ManifestTrack? Function(String sha) trackFor;
  final void Function(ManifestTrack) onPlay;

  static Future<void> show(
    BuildContext context, {
    required GetsController gets,
    required ManifestTrack? Function(String sha) trackFor,
    required void Function(ManifestTrack) onPlay,
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
      builder: (_) => GetsSheet(gets: gets, trackFor: trackFor, onPlay: onPlay),
    );
  }

  @override
  State<GetsSheet> createState() => _GetsSheetState();
}

class _GetsSheetState extends State<GetsSheet> {
  List<GetJob>? _jobs;
  bool _unreachable = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 2), (_) => _load());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final jobs = await widget.gets.everyone();
    if (!mounted) return;
    setState(() {
      _unreachable = jobs == null;
      if (jobs != null) _jobs = jobs;
    });
  }

  @override
  Widget build(BuildContext context) {
    final jobs = _jobs;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.lg,
                Space.lg,
                Space.xs,
              ),
              child: Text(
                'Getting from Soulseek',
                style: TypeScale.heading.copyWith(fontSize: 20),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Text(
                _unreachable
                    ? "The box isn't answering right now."
                    : 'Today, for everyone. One song at a time; a FLAC '
                          'takes from a minute to a few.',
                style: TypeScale.caption,
              ),
            ),
            const SizedBox(height: Space.sm),
            if (jobs == null)
              const Padding(
                padding: EdgeInsets.all(Space.lg),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (jobs.isEmpty)
              Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: Text(
                  'Nothing got today. Search for a song that is not in the '
                  'library and tap Get.',
                  style: TypeScale.body,
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    0,
                    Space.lg,
                    Space.lg,
                  ),
                  itemCount: jobs.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _JobRow(
                    job: jobs[i],
                    track: jobs[i].sha == null
                        ? null
                        : widget.trackFor(jobs[i].sha!),
                    onPlay: widget.onPlay,
                    onRetry: () => widget.gets.get(
                      null,
                      title: jobs[i].title,
                      artist: jobs[i].artist,
                      album: jobs[i].album,
                      release: jobs[i].release,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _JobRow extends StatelessWidget {
  const _JobRow({
    required this.job,
    required this.track,
    required this.onPlay,
    required this.onRetry,
  });

  final GetJob job;
  final ManifestTrack? track;
  final void Function(ManifestTrack) onPlay;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final j = job;
    final t = track;
    final Widget action;
    if (t != null) {
      action = IconButton(
        tooltip: 'Play ${j.title}',
        onPressed: () => onPlay(t),
        icon: Icon(Icons.play_arrow_rounded, color: Tones.text),
      );
    } else if (j.state == GetState.failed || j.state == GetState.notFound) {
      action = TextButton(
        onPressed: onRetry,
        style: TextButton.styleFrom(foregroundColor: Tones.text),
        child: const Text('Try again'),
      );
    } else if (!j.finished) {
      action = SizedBox.square(
        dimension: 22,
        child: CircularProgressIndicator(
          value: j.state == GetState.downloading ? j.progress : null,
          strokeWidth: 2.4,
          color: Tones.held,
          backgroundColor: Tones.hairline,
        ),
      );
    } else {
      action = const SizedBox.shrink();
    }
    final bad = j.state == GetState.failed || j.state == GetState.notFound;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  j.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TypeScale.title.copyWith(fontSize: 15),
                ),
                Text(
                  '${j.artist} · ${stateLabel(j)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TypeScale.caption.copyWith(
                    color: bad ? Tones.warn : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          action,
        ],
      ),
    );
  }
}
