import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/download_store.dart';
import '../../core/data/manifest_store.dart';
import '../../core/data/queue_store.dart';
import '../../core/nav/nav_controller.dart';
import '../../core/net/tunes_client.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/cover_tint.dart';
import '../../domain/artist_view.dart';
import '../../domain/discography.dart';
import '../../domain/manifest.dart';
import '../../core/data/play_history.dart';
import '../../domain/about.dart';
import '../song/about_nav.dart';
import '../song/about_widgets.dart';
import 'artist_sections.dart';
import '../../core/theme/looks.dart';
import '../album/album_page.dart';
import '../library/library_widgets.dart';

/// An artist, in the order you read them: who they are, what of theirs you
/// have, then what you do not.
///
/// The page used to open on the catalogue gaps and leave the songs you own at
/// the very bottom, below however many releases the artist has. The order now
/// comes from [buildArtistView], and two chips under the name jump straight to
/// either section.
class ArtistPage extends StatefulWidget {
  const ArtistPage({
    super.key,
    required this.artist,
    required this.manifest,
    this.client,
    required this.player,
    required this.store,
    required this.downloading,
    required this.onDownload,
    required this.offline,
    required this.artUrlFor,
    required this.manifestStore,
    this.queueStore,
    this.history,
  });

  /// Plays, for "Your [artist]" and where they rank among what you play.
  final PlayHistory? history;

  final String artist;
  final TunesManifest manifest;
  final TunesClient? client;
  final TunePlayer player;
  final DownloadStore store;
  final Set<String> downloading;
  final void Function(ManifestTrack) onDownload;
  final bool offline;
  final String Function(String sha) artUrlFor;
  final ManifestStore manifestStore;
  final QueueStore? queueStore;

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  ArtistDiscography? _discography;
  bool _loading = false;

  /// What Genius says (the Roon pass): the bio and the people around them.
  ArtistAbout? _about;
  List<Collaborator> _people = const [];
  Map<String, int> _plays = const {};
  bool _allSongs = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadAbout();
  }

  Future<void> _loadAbout() async {
    final client = widget.client;
    final history = widget.history;
    if (history != null) {
      final plays = await history.playCounts();
      if (mounted) setState(() => _plays = plays);
    }
    if (widget.offline || client == null) return;
    final r = await client.aboutArtist(widget.artist);
    if (!mounted || r == null) return;
    setState(() {
      _about = r.artist;
      _people = r.people;
    });
  }

  /// Where this artist ranks among those you play, by plays; null when you
  /// have not played them.
  int? _rank() {
    final byArtist = <String, int>{};
    for (final t in widget.manifest.tracks) {
      final n = _plays[t.sha];
      if (n == null || n == 0) continue;
      final a = (t.primaryArtist ?? t.artist).toLowerCase();
      byArtist[a] = (byArtist[a] ?? 0) + n;
    }
    final mine = byArtist[widget.artist.toLowerCase()];
    if (mine == null) return null;
    return 1 + byArtist.values.where((v) => v > mine).length;
  }

  Future<void> _load() async {
    if (widget.offline) return;
    final client = widget.client;
    if (client == null) return;
    setState(() => _loading = true);
    try {
      final d = await client.discography(widget.artist);
      if (!mounted) return;
      setState(() => _discography = d);
    } catch (_) {
      // Box unreachable: the songs you own still render, and the missing
      // section says it could not check rather than saying nothing.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openAlbum(ManifestRelease r) {
    NavScope.of(context).openPanel(
      TunesPanels.album(r.id),
      () => AlbumPage(
        release: r,
        manifest: widget.manifest,
        player: widget.player,
        store: widget.store,
        downloading: widget.downloading,
        onDownload: widget.onDownload,
        offline: widget.offline,
        artUrlFor: widget.artUrlFor,
        manifestStore: widget.manifestStore,
        queueStore: widget.queueStore,
      ),
    );
  }

  void _openArtist(String name) {
    NavScope.of(context).openPanel(
      TunesPanels.artist(name),
      () => ArtistPage(
        artist: name,
        history: widget.history,
        manifest: widget.manifest,
        client: widget.client,
        player: widget.player,
        store: widget.store,
        downloading: widget.downloading,
        onDownload: widget.onDownload,
        offline: widget.offline,
        artUrlFor: widget.artUrlFor,
        manifestStore: widget.manifestStore,
        queueStore: widget.queueStore,
      ),
    );
  }

  /// Your most played of theirs, up to five; none until you have played any.
  List<ManifestTrack> _mostPlayed(List<ManifestTrack> songs) {
    final played = [
      for (final t in songs)
        if ((_plays[t.sha] ?? 0) > 0) t,
    ]..sort((a, b) => (_plays[b.sha] ?? 0) - (_plays[a.sha] ?? 0));
    return played.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    final artist = widget.artist;
    final view = buildArtistView(
      artist: artist,
      manifest: widget.manifest,
      discography: _discography,
    );
    final photo = widget.manifest.artistArt(artist);
    final songs = view.ownedSongs;
    final lead = songs.take(view.leadSongCount).toList();
    final features = songs.skip(view.leadSongCount).toList();
    final top = _topSongs(songs);
    final rank = _rank();
    final facts = [
      '${songs.length} ${songs.length == 1 ? 'song' : 'songs'}',
      if (view.hasCatalogue)
        '${view.catalogueOwned} of ${view.catalogueTotal} records'
      else if (view.ownedReleases.isNotEmpty)
        '${view.ownedReleases.length} records',
      if (rank != null) 'your #$rank',
    ].join(' · ');
    final producers = [
      for (final p in _people)
        if (p.roles.contains('produced')) p,
    ];
    final aboutNav = AboutNav.maybeOf(context);

    return Scaffold(
      backgroundColor: Tones.base,
      body: TintBuilder(
        artSha: photo,
        builder: (context, tint) => SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ArtistBand(
                artist: artist,
                photoUrl: photo == null ? null : widget.artUrlFor(photo),
                photoSha: photo,
                tint: tint,
                facts: facts,
                onBack: () => NavScope.of(context).back(),
                onPlay: songs.isEmpty
                    ? null
                    : () => widget.player.playQueue(songs, 0),
                onShuffle: songs.isEmpty
                    ? null
                    : () => widget.player.shufflePlay(songs),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ---- Top songs --------------------------------------
                    if (top.isNotEmpty) ...[
                      AboutHeading('Top songs'),
                      Text(
                        _plays.isEmpty
                            ? 'The newest of theirs you have.'
                            : 'Your most played first, then the newest.',
                        style: TypeScale.caption,
                      ),
                      for (final (i, t) in top.indexed)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          onTap: () => widget.player.playQueue(top, i),
                          leading: SizedBox(
                            width: 76,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 24,
                                  child: Text(
                                    '${i + 1}',
                                    style: TypeScale.title.copyWith(
                                      color:
                                          Looks.current.crayons[i %
                                              Looks.current.crayons.length],
                                    ),
                                  ),
                                ),
                                ArtThumb(
                                  sha: t.artSha,
                                  artUrlFor: widget.artUrlFor,
                                  title: t.title,
                                  artist: t.artistDisplay,
                                ),
                              ],
                            ),
                          ),
                          title: Text(
                            t.title,
                            style: TypeScale.title.copyWith(fontSize: 15),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            t.album,
                            style: TypeScale.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: (_plays[t.sha] ?? 0) > 0
                              ? Text(
                                  '${_plays[t.sha]} plays',
                                  style: TypeScale.caption,
                                )
                              : null,
                        ),
                      if (lead.length > top.length)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () =>
                                setState(() => _allSongs = !_allSongs),
                            child: Text(
                              _allSongs
                                  ? 'Show fewer'
                                  : 'All ${lead.length} songs',
                            ),
                          ),
                        ),
                      if (_allSongs)
                        for (final (i, t) in lead.indexed)
                          TrackRow(
                            track: t,
                            onTap: () => widget.player.playQueue(lead, i),
                            player: widget.player,
                            store: widget.store,
                            downloading: widget.downloading.contains(t.sha),
                            onDownload: () => widget.onDownload(t),
                            offline: widget.offline,
                            artUrlFor: widget.artUrlFor,
                          ),
                    ],

                    // ---- Discography ------------------------------------
                    const AboutHeading('Discography'),
                    if (_loading && !view.hasCatalogue)
                      const _Note('Checking the catalogue…')
                    else
                      Discography(
                        artist: artist,
                        items: discoItems(view.ownedReleases, [
                          ...view.unfinished,
                          ...view.absent,
                        ]),
                        artUrlFor: widget.artUrlFor,
                        onOpen: _openAlbum,
                      ),
                    if (!view.hasCatalogue && !_loading)
                      _Note(
                        widget.offline
                            ? 'Connect to the box to see the rest of their records.'
                            : 'Only the records you have: the catalogue could not be checked just now.',
                      ),

                    // ---- Collabs ----------------------------------------
                    if (view.collaborators.isNotEmpty ||
                        producers.isNotEmpty ||
                        features.isNotEmpty) ...[
                      const AboutHeading('Collabs'),
                      if (view.collaborators.isNotEmpty) ...[
                        const SectionLabel(
                          'Artists · songs together in your library',
                        ),
                        LayoutBuilder(
                          builder: (context, box) {
                            final columns = (box.maxWidth / 220).floor().clamp(
                              2,
                              4,
                            );
                            const gap = 10.0;
                            final w =
                                (box.maxWidth - gap * (columns - 1)) / columns;
                            return Wrap(
                              spacing: gap,
                              runSpacing: gap,
                              children: [
                                for (final c in view.collaborators.take(8))
                                  SizedBox(
                                    width: w,
                                    child: CollabCard(
                                      name: c.name,
                                      songs: c.songs,
                                      photoSha: widget.manifest.artistArt(
                                        c.name,
                                      ),
                                      photoUrl:
                                          widget.manifest.artistArt(c.name) ==
                                              null
                                          ? null
                                          : widget.artUrlFor(
                                              widget.manifest.artistArt(
                                                c.name,
                                              )!,
                                            ),
                                      onTap: () => _openArtist(c.name),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                      if (producers.isNotEmpty && aboutNav != null) ...[
                        const SectionLabel(
                          "Producers · from your songs' credits",
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final p in producers.take(10))
                              ActionChip(
                                label: Text('${p.name}  ${p.songs}'),
                                onPressed: () => aboutNav.openPerson(p.name),
                              ),
                          ],
                        ),
                      ],
                      if (features.isNotEmpty) ...[
                        SectionLabel(
                          "On other artists' songs · ${features.length}",
                        ),
                        for (final (i, t) in features.take(6).indexed)
                          TrackRow(
                            track: t,
                            onTap: () => widget.player.playQueue(features, i),
                            player: widget.player,
                            store: widget.store,
                            downloading: widget.downloading.contains(t.sha),
                            onDownload: () => widget.onDownload(t),
                            offline: widget.offline,
                            artUrlFor: widget.artUrlFor,
                          ),
                      ],
                    ],

                    // ---- About, at the very bottom ----------------------
                    if (_about?.description case final bio?) ...[
                      const SizedBox(height: Space.xl),
                      Container(
                        padding: const EdgeInsets.all(Space.md),
                        decoration: BoxDecoration(
                          color: Tones.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Looks.current.kind == LookKind.crayon
                                ? Tones.text
                                : Tones.hairline,
                            width: Looks.current.kind == LookKind.crayon
                                ? 2
                                : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'About $artist',
                              style: TypeScale.display.copyWith(fontSize: 22),
                            ),
                            const SizedBox(height: Space.sm),
                            ReadMore(text: bio, url: _about!.url),
                            if (_about!.alternateNames.isNotEmpty)
                              Text(
                                'Also known as ${_about!.alternateNames.take(4).join(', ')}',
                                style: TypeScale.caption,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Your most played of theirs, then their newest, five in all.
  List<ManifestTrack> _topSongs(List<ManifestTrack> songs) {
    final played = _mostPlayed(songs);
    final rest = [
      for (final t in songs)
        if (!played.contains(t)) t,
    ];
    return [...played, ...rest].take(5).toList();
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TypeScale.note.copyWith(fontSize: 14, color: Tones.textMuted),
    );
  }
}
