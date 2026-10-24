import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/gets.dart';
import '../../core/nav/nav_controller.dart';
import '../../core/theme/looks.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/artwork.dart';
import '../../core/ui/generated_artwork.dart';
import '../../domain/about.dart';
import '../../domain/manifest.dart';
import 'about_widgets.dart';

/// A person, the way Roon shows one: a producer, a writer or a featured
/// artist, and everything they made that the library holds, grouped by the
/// artists you play (the Roon pass, approved 24 Oct). Reached by tapping a
/// name in a song's or an artist's credits.
class PersonPage extends StatefulWidget {
  const PersonPage({
    super.key,
    required this.name,
    required this.manifest,
    required this.player,
    required this.artUrlFor,
    required this.onOpenSong,
    required this.onOpenArtist,
  });

  final String name;
  final TunesManifest manifest;
  final TunePlayer player;
  final String Function(String sha) artUrlFor;
  final void Function(ManifestTrack track) onOpenSong;
  final void Function(String artist) onOpenArtist;

  @override
  State<PersonPage> createState() => _PersonPageState();
}

class _PersonPageState extends State<PersonPage> {
  List<Work>? _work;
  bool _asked = false;
  bool _failed = false;
  String _role = 'all';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked) return;
    _asked = true;
    final client = GetsScope.maybeOf(context)?.client;
    if (client == null) {
      _failed = true;
      return;
    }
    unawaited(
      client.aboutPerson(widget.name).then((w) {
        if (!mounted) return;
        setState(() {
          _work = w;
          _failed = w == null;
        });
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final crayon = Looks.current.kind == LookKind.crayon;
    final bySha = {for (final t in widget.manifest.tracks) t.sha: t};
    final work = [
      for (final w in _work ?? const <Work>[])
        if (bySha[w.sha] != null) (track: bySha[w.sha]!, roles: w.roles),
    ];
    int count(String role) => work.where((w) => w.roles.contains(role)).length;
    final shown = _role == 'all'
        ? work
        : work.where((w) => w.roles.contains(_role)).toList();
    // By the artist whose song it is, most songs first.
    final byArtist = <String, List<ManifestTrack>>{};
    for (final w in shown) {
      final a = w.track.primaryArtist ?? w.track.artist;
      byArtist.putIfAbsent(a, () => []).add(w.track);
    }
    final artists = byArtist.entries.toList()
      ..sort((a, b) => b.value.length - a.value.length);
    // They have music of their own in the library.
    final ownName = widget.name.toLowerCase();
    final hasOwn = widget.manifest.tracks.any(
      (t) => (t.primaryArtist ?? t.artist).toLowerCase() == ownName,
    );

    return Scaffold(
      backgroundColor: Tones.base,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Back',
                onPressed: () => NavScope.of(context).back(),
                icon: Icon(Icons.arrow_back_rounded, color: Tones.textMuted),
              ),
            ),
            Text(
              [
                if (count('produced') > 0) 'PRODUCER',
                if (count('written') > 0) 'WRITER',
                if (count('featured') > 0 || hasOwn) 'ARTIST',
              ].join(' · '),
              style: TypeScale.mono,
            ),
            const SizedBox(height: 4),
            Text(widget.name, style: TypeScale.display.copyWith(fontSize: 36)),
            const SizedBox(height: 4),
            Text(
              _work == null && !_failed
                  ? 'Looking through your library…'
                  : '${work.length} ${work.length == 1 ? 'song' : 'songs'} in your library',
              style: TypeScale.caption,
            ),
            const SizedBox(height: Space.md),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                FilledButton.icon(
                  onPressed: shown.isEmpty
                      ? null
                      : () => widget.player.playQueue([
                          for (final w in shown) w.track,
                        ], 0),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play their work'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Tones.text,
                    foregroundColor: Tones.base,
                  ),
                ),
                if (hasOwn)
                  OutlinedButton(
                    onPressed: () => widget.onOpenArtist(widget.name),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Tones.text,
                      side: BorderSide(
                        color: Tones.text,
                        width: crayon ? 2 : 1,
                      ),
                    ),
                    child: const Text('Their own music'),
                  ),
              ],
            ),
            if (work.isNotEmpty) ...[
              const SizedBox(height: Space.md),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (role, label) in [
                    ('all', 'All'),
                    ('produced', 'Produced'),
                    ('featured', 'Featured'),
                    ('written', 'Written'),
                  ])
                    if (role == 'all' || count(role) > 0)
                      ChoiceChip(
                        label: Text(
                          '$label · ${role == 'all' ? work.length : count(role)}',
                        ),
                        selected: _role == role,
                        showCheckmark: false,
                        selectedColor: Tones.text,
                        labelStyle: TypeScale.caption.copyWith(
                          color: _role == role ? Tones.base : Tones.text,
                          fontWeight: FontWeight.w700,
                        ),
                        onSelected: (_) => setState(() => _role = role),
                      ),
                ],
              ),
            ],

            if (artists.length > 1) ...[
              const AboutHeading('For the artists you play'),
              for (final e in artists.take(6))
                _ArtistShare(
                  artist: e.key,
                  songs: e.value.length,
                  share: e.value.length / shown.length,
                  onTap: () => widget.onOpenArtist(e.key),
                ),
            ],

            if (shown.isNotEmpty) ...[
              const AboutHeading('Songs they worked on'),
              for (final w in shown)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () => widget.onOpenSong(w.track),
                  leading: Artwork(
                    url: w.track.artSha == null
                        ? null
                        : widget.artUrlFor(w.track.artSha!),
                    artSha: w.track.artSha,
                    size: 44,
                    borderRadius: 8,
                    fallback: GeneratedArtwork(
                      title: w.track.title,
                      artist: w.track.artistDisplay,
                      size: 44,
                      borderRadius: 8,
                    ),
                  ),
                  title: Text(
                    w.track.title,
                    style: TypeScale.title.copyWith(fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${w.track.primaryArtist ?? w.track.artist} · ${w.roles.join(', ')}',
                    style: TypeScale.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(w.track.year ?? '', style: TypeScale.caption),
                ),
            ],

            if (_failed)
              Padding(
                padding: const EdgeInsets.only(top: Space.xl),
                child: Text(
                  "Couldn't reach the box to look. Their songs show here once it answers.",
                  style: TypeScale.caption,
                ),
              )
            else if (_work != null && work.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Space.xl),
                child: Text(
                  'Nothing of theirs found yet. Credits fill in as the box '
                  'reads about your songs, a few every minute.',
                  style: TypeScale.caption,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One artist they worked for, and how much of their work it is.
class _ArtistShare extends StatelessWidget {
  const _ArtistShare({
    required this.artist,
    required this.songs,
    required this.share,
    required this.onTap,
  });

  final String artist;
  final int songs;
  final double share;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(artist, style: TypeScale.title.copyWith(fontSize: 15)),
                Text(
                  '$songs ${songs == 1 ? 'song' : 'songs'}',
                  style: TypeScale.caption,
                ),
              ],
            ),
          ),
          SizedBox(
            width: 90,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: share.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: Tones.surface,
                valueColor: AlwaysStoppedAnimation(Tones.primary),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
