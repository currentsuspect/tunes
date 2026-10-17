import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/playlist_store.dart';
import '../../core/nav/nav_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/artwork.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/cover_tint.dart';
import '../../core/ui/generated_artwork.dart';
import '../../core/ui/playing_bars.dart';
import '../../domain/manifest.dart';
import '../../domain/mixes.dart';

/// A mix the app made: what it is, why, and the songs, to play or to keep.
///
/// Read-only on purpose. A mix is rebuilt from how you listen, so editing one
/// would be editing something that is about to change. Saving it is the way to
/// get a list that stays: it copies the songs into a playlist, which is yours to
/// reorder and change from then on.
class MixPage extends StatefulWidget {
  const MixPage({
    super.key,
    required this.mix,
    required this.player,
    required this.artUrlFor,
    this.playlists,
  });

  final Mix mix;
  final TunePlayer player;
  final String Function(String sha) artUrlFor;

  /// Where Save as playlist puts it. Without one the button is not shown.
  final PlaylistStore? playlists;

  @override
  State<MixPage> createState() => _MixPageState();
}

class _MixPageState extends State<MixPage> {
  bool _saved = false;
  bool _saving = false;

  Future<void> _save() async {
    final store = widget.playlists;
    if (store == null || _saving || _saved) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final id = await store.create(widget.mix.title);
    await store.addAll(id, [for (final t in widget.mix.tracks) t.sha]);
    if (!mounted) return;
    setState(() {
      _saved = true;
      _saving = false;
    });
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Saved "${widget.mix.title}" to your playlists. It is yours to '
            'change now.',
          ),
        ),
      );
  }

  static String _span(int ms) {
    final minutes = (ms / 60000).round();
    if (minutes < 60) return '$minutes min';
    return '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')} min';
  }

  @override
  Widget build(BuildContext context) {
    final mix = widget.mix;
    final tracks = mix.tracks;
    final totalMs = tracks.fold<int>(0, (a, t) => a + (t.durationMs ?? 0));
    final covers = <String>[];
    for (final t in tracks) {
      final a = t.artSha;
      if (a != null && !covers.contains(a)) covers.add(a);
      if (covers.length == 4) break;
    }
    return Scaffold(
      backgroundColor: Tones.base,
      body: TintBuilder(
        artSha: covers.isEmpty ? null : covers.first,
        builder: (context, tint) => Stack(
          fit: StackFit.expand,
          children: [
            AmbientGlow(tint: tint, strength: 0.34),
            SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.xs,
                        Space.sm,
                        Space.sm,
                        0,
                      ),
                      child: IconButton(
                        onPressed: () => NavScope.of(context).back(),
                        tooltip: 'Back',
                        icon: Icon(
                          Icons.arrow_back_rounded,
                          color: Tones.textMuted,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: Space.xl),
                      itemCount: tracks.length + 1,
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return _Header(
                            mix: mix,
                            covers: covers,
                            tint: tint,
                            artUrlFor: widget.artUrlFor,
                            facts:
                                '${tracks.length} songs  ·  ${_span(totalMs)}',
                            saved: _saved,
                            saving: _saving,
                            onPlay: () => widget.player.playQueue(tracks, 0),
                            onShuffle: () => widget.player.shufflePlay(tracks),
                            onSave: widget.playlists == null ? null : _save,
                          );
                        }
                        final t = tracks[i - 1];
                        return _SongRow(
                          track: t,
                          player: widget.player,
                          artUrlFor: widget.artUrlFor,
                          onTap: () => widget.player.playQueue(tracks, i - 1),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.mix,
    required this.covers,
    required this.tint,
    required this.artUrlFor,
    required this.facts,
    required this.saved,
    required this.saving,
    required this.onPlay,
    required this.onShuffle,
    required this.onSave,
  });

  final Mix mix;
  final List<String> covers;
  final Color tint;
  final String Function(String sha) artUrlFor;
  final String facts;
  final bool saved;
  final bool saving;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.sm,
        Space.lg,
        Space.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MixMosaic(
                name: mix.title,
                covers: covers,
                tint: tint,
                artUrlFor: artUrlFor,
                side: 124,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MADE FOR YOU',
                      style: TypeScale.mono.copyWith(letterSpacing: 1.2),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      mix.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TypeScale.display.copyWith(fontSize: 26),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Text(
            mix.note,
            style: TypeScale.note.copyWith(
              fontSize: 15,
              color: Tones.textMuted,
            ),
          ),
          const SizedBox(height: Space.sm),
          Text(facts, style: TypeScale.mono),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              FilledButton.icon(
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('Play'),
                style: FilledButton.styleFrom(
                  backgroundColor: Tones.text,
                  foregroundColor: Tones.base,
                ),
              ),
              OutlinedButton.icon(
                onPressed: onShuffle,
                icon: const Icon(Icons.shuffle_rounded, size: 18),
                label: const Text('Shuffle'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Tones.text,
                  side: BorderSide(color: Tones.hairline),
                ),
              ),
              if (onSave != null)
                OutlinedButton.icon(
                  onPressed: saved || saving ? null : onSave,
                  icon: Icon(
                    saved ? Icons.check_rounded : Icons.playlist_add_rounded,
                    size: 18,
                    color: saved ? Tones.held : null,
                  ),
                  label: Text(saved ? 'Saved' : 'Save as playlist'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Tones.text,
                    side: BorderSide(
                      color: saved ? Tones.held : Tones.hairline,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A mix's cover: the first four sleeves in it, two by two, lit by the first. A
/// mix with fewer than four covers fills the rest from its own name, so it is
/// never a grey square.
class MixMosaic extends StatelessWidget {
  const MixMosaic({
    super.key,
    required this.name,
    required this.covers,
    required this.tint,
    required this.artUrlFor,
    this.side = 124,
  });

  final String name;
  final List<String> covers;
  final Color tint;
  final String Function(String sha) artUrlFor;
  final double side;

  @override
  Widget build(BuildContext context) {
    final cell = side / 2;
    Widget tile(int i) {
      final fallback = GeneratedArtwork(
        title: '$name $i',
        artist: '',
        size: cell,
        borderRadius: 0,
      );
      if (i >= covers.length) return fallback;
      return Artwork(
        url: artUrlFor(covers[i]),
        artSha: covers[i],
        size: cell,
        borderRadius: 0,
        fallback: fallback,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: tint.withValues(alpha: 0.5),
            blurRadius: 40,
            spreadRadius: -8,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: side,
          height: side,
          child: Column(
            children: [
              Row(children: [tile(0), tile(1)]),
              Row(children: [tile(2), tile(3)]),
            ],
          ),
        ),
      ),
    );
  }
}

class _SongRow extends StatelessWidget {
  const _SongRow({
    required this.track,
    required this.player,
    required this.artUrlFor,
    required this.onTap,
  });

  final ManifestTrack track;
  final TunePlayer player;
  final String Function(String sha) artUrlFor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final active = player.current?.sha == track.sha;
        return PressRow(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.lg,
              vertical: Space.sm,
            ),
            child: Row(
              children: [
                Artwork(
                  url: track.artSha == null ? null : artUrlFor(track.artSha!),
                  artSha: track.artSha,
                  size: 48,
                  borderRadius: 9,
                  fallback: GeneratedArtwork.fromTrack(
                    track,
                    size: 48,
                    borderRadius: 9,
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TypeScale.title.copyWith(
                          fontSize: 15,
                          color: active ? Tones.primary : Tones.text,
                        ),
                      ),
                      Text(
                        track.artistAlbumLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TypeScale.caption,
                      ),
                    ],
                  ),
                ),
                if (active)
                  Padding(
                    padding: const EdgeInsets.only(left: Space.sm),
                    child: PlayingBars(playing: player.playing),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(left: Space.sm),
                    child: Text(track.durationLabel, style: TypeScale.mono),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
