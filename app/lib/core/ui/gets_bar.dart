import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/manifest.dart';
import '../../domain/soulseek.dart';
import '../data/gets.dart';
import '../theme/looks.dart';
import '../theme/tokens.dart';
import 'get_status.dart';

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
    final waiting =
        active.where((j) => j.state == GetState.queued).length -
        (lead.state == GetState.queued ? 1 : 0);
    final text = [
      lead.state == GetState.queued
          ? '${lead.title} is in line'
          : 'Getting ${lead.title}',
      if (waiting > 0) '$waiting waiting',
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

/// A get's state in a few words, short enough for the bar.
String stateLabel(GetJob j) => switch (j.state) {
  GetState.queued => j.position == null ? 'waiting' : ordinal(j.position!),
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
    final crayon = Looks.current.kind == LookKind.crayon;
    final today = DateTime.now().subtract(const Duration(hours: 24));
    final going = [
      for (final j in jobs ?? const <GetJob>[])
        if (!j.finished && j.state != GetState.queued) j,
    ];
    final waiting = [
      for (final j in jobs ?? const <GetJob>[])
        if (j.state == GetState.queued) j,
    ]..sort((a, b) => (a.position ?? 99).compareTo(b.position ?? 99));
    final landed = [
      for (final j in jobs ?? const <GetJob>[])
        if (j.state == GetState.done && (j.at == null || j.at!.isAfter(today)))
          j,
    ];
    final failed = [
      for (final j in jobs ?? const <GetJob>[])
        if ((j.state == GetState.failed || j.state == GetState.notFound) &&
            (j.at == null || j.at!.isAfter(today)))
          j,
    ];
    final mine = {for (final j in widget.gets.following) j.id};
    Widget heading(String text, {Color? color}) => Padding(
      padding: const EdgeInsets.only(top: Space.lg, bottom: Space.xs),
      child: Text(
        text.toUpperCase(),
        style: TypeScale.caption.copyWith(
          letterSpacing: 1.4,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          color: color ?? Tones.textMuted,
        ),
      ),
    );
    final empty =
        jobs != null &&
        going.isEmpty &&
        waiting.isEmpty &&
        landed.isEmpty &&
        failed.isEmpty;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.lg,
            Space.lg,
            Space.lg,
          ),
          children: [
            Text('The line', style: TypeScale.heading.copyWith(fontSize: 24)),
            const SizedBox(height: 2),
            Text(
              _unreachable
                  ? "The box isn't answering right now."
                  : "Everyone's gets, one at a time. A FLAC takes a minute "
                        'or a few.',
              style: TypeScale.caption.copyWith(
                fontStyle: crayon ? FontStyle.italic : null,
              ),
            ),
            if (jobs == null)
              const Padding(
                padding: EdgeInsets.all(Space.lg),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (empty)
              Padding(
                padding: const EdgeInsets.only(top: Space.lg),
                child: Text(
                  'Nothing today. Search for a song that is not in the '
                  'library and tap Get.',
                  style: TypeScale.body,
                ),
              ),
            for (final j in going) ...[
              const SizedBox(height: Space.md),
              _NowCard(job: j),
            ],
            if (waiting.isNotEmpty) heading('Up next'),
            for (final j in waiting)
              _WaitingRow(
                job: j,
                onCancel: mine.contains(j.id)
                    ? () async {
                        await widget.gets.cancel(j);
                        _load();
                      }
                    : null,
              ),
            if (landed.isNotEmpty) heading('Landed today'),
            for (final j in landed)
              _JobRow(
                job: j,
                track: j.sha == null ? null : widget.trackFor(j.sha!),
                onPlay: widget.onPlay,
                onRetry: null,
              ),
            if (failed.isNotEmpty) heading("Couldn't get", color: Tones.warn),
            for (final j in failed)
              _JobRow(
                job: j,
                track: null,
                onPlay: widget.onPlay,
                onRetry: () => widget.gets.get(
                  null,
                  title: j.title,
                  artist: j.artist,
                  album: j.album,
                  release: j.release,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Who asked and when, for a row's second line.
String _whoWhen(GetJob j) {
  final at = j.at?.toLocal();
  final when = at == null
      ? null
      : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  return [j.artist, ?j.by, ?when].join(' · ');
}

/// The song coming down now: big, with how far.
class _NowCard extends StatelessWidget {
  const _NowCard({required this.job});

  final GetJob job;

  @override
  Widget build(BuildContext context) {
    final j = job;
    final crayon = Looks.current.kind == LookKind.crayon;
    final p = j.state == GetState.downloading ? j.progress : null;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: Tones.surfaceRaised,
        borderRadius: BorderRadius.circular(RadiusTokens.card),
        border: Border.all(
          color: crayon ? Tones.text : Tones.hairline,
          width: crayon ? 2 : 1,
        ),
        boxShadow: crayon
            ? [
                BoxShadow(
                  color: Looks.current.inkShadow,
                  offset: const Offset(4, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Tones.held,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'GETTING NOW',
                style: TypeScale.caption.copyWith(
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: Tones.held,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      j.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TypeScale.title.copyWith(fontSize: 17),
                    ),
                    Text(
                      j.by == null
                          ? j.artist
                          : '${j.artist} · asked by ${j.by}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TypeScale.caption,
                    ),
                  ],
                ),
              ),
              Text(
                p == null ? stateLabel(j) : '${(p * 100).round()}%',
                style: TypeScale.title.copyWith(fontSize: 18),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: p,
              minHeight: crayon ? 8 : 4,
              color: Tones.held,
              backgroundColor: Tones.hairline,
            ),
          ),
        ],
      ),
    );
  }
}

/// A song waiting: its place, and × for the ones this phone asked for.
class _WaitingRow extends StatelessWidget {
  const _WaitingRow({required this.job, required this.onCancel});

  final GetJob job;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final j = job;
    final crayon = Looks.current.kind == LookKind.crayon;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: crayon ? Tones.text : Tones.hairline,
                width: crayon ? 1.5 : 1,
              ),
            ),
            child: Text(
              '${j.position ?? '·'}',
              style: TypeScale.caption.copyWith(
                color: Tones.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: Space.md),
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
                  j.by == null ? j.artist : '${j.artist} · asked by ${j.by}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TypeScale.caption,
                ),
              ],
            ),
          ),
          if (onCancel != null)
            IconButton(
              tooltip: 'Take ${j.title} out of the line',
              onPressed: onCancel,
              icon: Icon(Icons.close_rounded, color: Tones.textMuted),
            ),
        ],
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
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final j = job;
    final t = track;
    final bad = j.state == GetState.failed || j.state == GetState.notFound;
    final Widget action;
    if (t != null) {
      action = GetAction(
        title: j.title,
        job: j,
        onGet: null,
        playable: t,
        onPlay: onPlay,
      );
    } else if (bad && onRetry != null) {
      action = GetButton(label: 'Try again', onTap: onRetry!);
    } else {
      action = const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
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
                  bad ? (getNote(j) ?? '') : _whoWhen(j),
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
