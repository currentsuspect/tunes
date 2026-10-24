import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/play_history.dart';
import '../../core/lyrics/drops.dart';
import '../../core/lyrics/lrc_parser.dart';
import '../../core/nav/nav_controller.dart';
import '../../core/theme/looks.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/artwork.dart';
import '../../core/ui/generated_artwork.dart';
import '../../domain/about.dart';
import '../../domain/manifest.dart';
import '../../core/data/gets.dart';
import 'about_widgets.dart';

/// One song, the way Roon shows a track (the Roon pass, approved 24 Oct):
/// what it is about, who made it, what it samples and what sampled it, the
/// moments where the 808 drops out, your history with it, and the copies you
/// hold. Every name opens its own page.
///
/// What Genius says comes from the box (/about/song); offline, or for a song
/// Genius does not know, those sections are simply not there.
class SongPage extends StatefulWidget {
  const SongPage({
    super.key,
    required this.track,
    required this.manifest,
    required this.player,
    required this.artUrlFor,
    required this.onOpenArtist,
    required this.onOpenAlbum,
    required this.onOpenPerson,
    required this.onOpenLyrics,
    this.history,
  });

  final ManifestTrack track;
  final TunesManifest manifest;
  final TunePlayer player;
  final String Function(String sha) artUrlFor;
  final void Function(String artist) onOpenArtist;
  final void Function(ManifestRelease release) onOpenAlbum;
  final void Function(String person) onOpenPerson;
  final VoidCallback onOpenLyrics;
  final PlayHistory? history;

  @override
  State<SongPage> createState() => _SongPageState();
}

class _SongPageState extends State<SongPage> {
  SongAbout? _song;
  AlbumAbout? _album;
  bool _asked = false;
  ({int plays, int skips, DateTime? first, DateTime? last})? _stats;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked) return;
    _asked = true;
    final client = GetsScope.maybeOf(context)?.client;
    if (client != null) {
      unawaited(
        client.aboutSong(widget.track.sha).then((r) {
          if (!mounted || r == null) return;
          setState(() {
            _song = r.song;
            _album = r.album;
          });
        }),
      );
    }
    final h = widget.history;
    if (h != null) {
      unawaited(
        h.songStats(widget.track.sha).then((s) {
          if (mounted) setState(() => _stats = s);
        }),
      );
    }
  }

  ManifestRelease? get _release {
    final id = widget.track.releaseId;
    if (id == null) return null;
    for (final r in widget.manifest.releases) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Where the 808 drops out and the ad-lib takes over (drops.dart).
  List<DropMoment> get _moments {
    final lyrics = widget.track.lyrics;
    if (lyrics == null || lyrics.trim().isEmpty) return const [];
    final lrc = LrcParser.parse(lyrics);
    return resolveMoments(
      lrc.lines,
      BeatMap.parse(lrc.metadata[BeatMap.key]),
    ).where((m) => m.kind == DropKind.grow).toList();
  }

  void _playAt(Duration at) {
    final p = widget.player;
    if (p.current?.sha == widget.track.sha) {
      p.seek(at);
      p.play();
      return;
    }
    p.playQueue([widget.track], 0);
    // The source opens first; a seek before it has is lost.
    Future<void>.delayed(const Duration(milliseconds: 600), () => p.seek(at));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final crayon = Looks.current.kind == LookKind.crayon;
    final release = _release;
    final song = _song;
    final moments = _moments;
    final duration = Duration(milliseconds: t.durationMs ?? 0);
    final makers = song == null
        ? const <(String, List<String>)>[]
        : [
            if (song.producers.isNotEmpty) ('Produced by', song.producers),
            if (song.writers.isNotEmpty) ('Written by', song.writers),
            if (song.featured.isNotEmpty) ('Featuring', song.featured),
            for (final c in song.credits)
              if (c.role != 'Label' &&
                  !c.role.startsWith('Phonographic') &&
                  !c.role.startsWith('Copyright') &&
                  c.role != 'Distributor')
                (c.role, c.names),
          ];
    final labels = [
      for (final c in song?.credits ?? const <Credit>[])
        if (c.role == 'Label') ...c.names,
    ];
    // The same song held elsewhere: on another edition, a single, a clean
    // copy (same title and artist, any album).
    final versions = [
      t,
      for (final x in widget.manifest.tracks)
        if (x.sha != t.sha &&
            _key(x.title) == _key(t.title) &&
            _key(x.artistDisplay) == _key(t.artistDisplay))
          x,
    ];

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
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Artwork(
                  url: t.artSha == null ? null : widget.artUrlFor(t.artSha!),
                  artSha: t.artSha,
                  size: 96,
                  borderRadius: 12,
                  fallback: GeneratedArtwork(
                    title: t.title,
                    artist: t.artistDisplay,
                    size: 96,
                    borderRadius: 12,
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          'SONG',
                          if (t.trackNumber != null && release != null)
                            'TRACK ${t.trackNumber} OF ${release.title.toUpperCase()}',
                        ].join(' · '),
                        style: TypeScale.mono,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t.title,
                        style: TypeScale.display.copyWith(fontSize: 34),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final (i, a) in [
                  t.primaryArtist ?? t.artist,
                  ...t.featured,
                ].indexed) ...[
                  if (i == 1) Text(' with ', style: TypeScale.body),
                  if (i > 1) Text(', ', style: TypeScale.body),
                  NameLink(name: a, onTap: () => widget.onOpenArtist(a)),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  [
                    t.durationLabel,
                    ?(t.year ?? song?.releaseDate?.substring(0, 4)),
                  ].join(' · '),
                  style: TypeScale.caption,
                ),
                if (release != null) ...[
                  Text(' · ', style: TypeScale.caption),
                  InkWell(
                    onTap: () => widget.onOpenAlbum(release),
                    child: Text(
                      release.title,
                      style: TypeScale.caption.copyWith(
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: Space.md),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                FilledButton.icon(
                  onPressed: () => widget.player.playQueue([t], 0),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Tones.text,
                    foregroundColor: Tones.base,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: widget.onOpenLyrics,
                  icon: const Icon(Icons.lyrics_outlined, size: 18),
                  label: const Text('Lyrics'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Tones.text,
                    side: BorderSide(color: Tones.text, width: crayon ? 2 : 1),
                  ),
                ),
              ],
            ),

            if (song?.description case final d?) ...[
              const AboutHeading('About this song'),
              ReadMore(text: d, url: song!.url),
            ],

            if (makers.isNotEmpty) ...[
              const AboutHeading('Who made it'),
              CreditsCard(
                rows: [
                  for (final (role, names) in makers)
                    CreditRow(
                      role: role,
                      names: [for (final n in names) personName(n)],
                      onName: widget.onOpenPerson,
                    ),
                ],
              ),
            ],

            if (song != null && song.connections.isNotEmpty) ...[
              const AboutHeading('Connections'),
              Text(
                'Samples, interpolations and covers, from Genius.',
                style: TypeScale.caption,
              ),
              const SizedBox(height: Space.sm),
              for (final c in song.connections)
                for (final s in c.songs.take(4))
                  ConnectionTile(
                    label: c.label,
                    title: s.title,
                    artist: s.artist,
                    held: _held(s.title, s.artist),
                    onOpen: () {
                      final h = _held(s.title, s.artist);
                      if (h != null) widget.player.playQueue([h], 0);
                    },
                  ),
            ],

            if (moments.isNotEmpty && duration > Duration.zero) ...[
              const AboutHeading('The moments'),
              Text(
                'Where the 808 drops out and the ad-lib takes over.',
                style: TypeScale.caption,
              ),
              const SizedBox(height: Space.sm),
              MomentStrip(
                duration: duration,
                at: [for (final m in moments) m.from],
              ),
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final m in moments)
                    ActionChip(
                      label: Text('${clock(m.from)}  “${m.text}”'),
                      onPressed: () => _playAt(m.from),
                    ),
                ],
              ),
            ],

            if (_stats case final s?) ...[
              const AboutHeading('You and this song'),
              Row(
                children: [
                  StatTile(value: '${s.plays}', label: 'plays'),
                  const SizedBox(width: Space.sm),
                  StatTile(
                    value: s.first == null ? '—' : shortDate(s.first!),
                    label: 'first played',
                  ),
                  const SizedBox(width: Space.sm),
                  StatTile(
                    value: s.plays + s.skips == 0
                        ? '—'
                        : '${(100 * s.plays / (s.plays + s.skips)).round()}%',
                    label: 'played through',
                  ),
                ],
              ),
            ],

            const AboutHeading('Versions you have'),
            for (final v in versions)
              VersionTile(
                title: [
                  v.album,
                  if (v.trackNumber != null) 'track ${v.trackNumber}',
                ].join(' · '),
                detail: [
                  ?v.codec?.toUpperCase(),
                  if ((v.sampleRate ?? 0) > 0)
                    '${(v.sampleRate! / 1000).toStringAsFixed(1)} kHz',
                  if (identical(v, t)) 'the one that plays',
                ].join(' · '),
              ),

            if (_album?.description case final d?) ...[
              const AboutHeading('About the album'),
              ReadMore(text: d, url: _album!.url),
            ],
            if (labels.isNotEmpty) ...[
              const SizedBox(height: Space.md),
              Text('Label: ${labels.join(', ')}', style: TypeScale.caption),
            ],
          ],
        ),
      ),
    );
  }

  static String _key(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  /// A song from a connection, when the library holds it.
  ManifestTrack? _held(String title, String artist) {
    const k = _key;
    final kt = k(title);
    final ka = k(artist);
    for (final x in widget.manifest.tracks) {
      if (k(x.title) == kt &&
          (ka.isEmpty ||
              k(x.artistDisplay).contains(ka) ||
              ka.contains(k(x.artistDisplay)))) {
        return x;
      }
    }
    return null;
  }
}
