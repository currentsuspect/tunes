import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/download_store.dart';
import '../../core/data/manifest_store.dart';
import '../../core/data/queue_store.dart';
import '../../core/nav/nav_controller.dart';
import '../../core/net/tunes_client.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/artwork.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/cover_tint.dart';
import '../../core/ui/initials.dart';
import '../../core/ui/shared_sleeve.dart';
import '../../domain/artist_view.dart';
import '../../domain/discography.dart';
import '../../domain/manifest.dart';
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
  });

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
  static const _songsPreview = 8;
  static const _absentPreview = 6;

  ArtistDiscography? _discography;
  bool _loading = false;
  bool _allSongs = false;
  bool _allAbsent = false;

  final _songsKey = GlobalKey();
  final _missingKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
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

  void _jump(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: 0.02,
    );
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

  ManifestRelease? _releaseFor(DiscographyGroup g) {
    final id = g.releaseId;
    if (id == null) return null;
    for (final r in widget.manifest.releases) {
      if (r.id == id) return r;
    }
    return null;
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
    final gaps = view.unfinished.length + view.absent.length;
    final songs = view.ownedSongs;
    final shownSongs = _allSongs ? songs : songs.take(_songsPreview).toList();
    final shownAbsent = _allAbsent
        ? view.absent
        : view.absent.take(_absentPreview).toList();

    return Scaffold(
      body: TintBuilder(
        artSha: photo,
        builder: (context, tint) => Stack(
          fit: StackFit.expand,
          children: [
            AmbientGlow(tint: tint, strength: 0.34),
            SafeArea(
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
                    // Not a lazy ListView: the jump chips scroll to a section by
                    // its key, and a section that has not been built yet has no
                    // position to scroll to. The body is a handful of capped
                    // sections, so building it whole is cheap.
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        Space.lg,
                        0,
                        Space.lg,
                        Space.xl,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Hero(
                            artist: artist,
                            photoSha: photo,
                            artUrlFor: widget.artUrlFor,
                            view: view,
                            tint: tint,
                            onPlay: songs.isEmpty
                                ? null
                                : () => widget.player.playQueue(songs, 0),
                            onShuffle: songs.isEmpty
                                ? null
                                : () => widget.player.shufflePlay(songs),
                          ),
                          if (songs.isNotEmpty && gaps > 0) ...[
                            const SizedBox(height: Space.lg),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: Space.sm,
                              runSpacing: Space.sm,
                              children: [
                                _JumpChip(
                                  label: 'Songs you have',
                                  count: songs.length,
                                  onTap: () => _jump(_songsKey),
                                ),
                                _JumpChip(
                                  label: 'Not in your library',
                                  count: gaps,
                                  onTap: () => _jump(_missingKey),
                                ),
                              ],
                            ),
                          ],
                          if (view.collaborators.isNotEmpty) ...[
                            const SizedBox(height: Space.xl),
                            _Heading(
                              title: 'Appears with',
                              trailing: '${view.collaborators.length}',
                            ),
                            const SizedBox(height: Space.md),
                            SizedBox(
                              height: 104,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: view.collaborators.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: Space.md),
                                itemBuilder: (context, i) {
                                  final c = view.collaborators[i];
                                  final art = widget.manifest.artistArt(c.name);
                                  return _CollaboratorChip(
                                    name: c.name,
                                    songs: c.songs,
                                    photoUrl: art == null
                                        ? null
                                        : widget.artUrlFor(art),
                                    photoSha: art,
                                    onTap: () => _openArtist(c.name),
                                  );
                                },
                              ),
                            ),
                          ],
                          // ---- Songs you have ---------------------------------
                          const SizedBox(height: Space.xl),
                          _Heading(
                            key: _songsKey,
                            title: 'Songs you have',
                            trailing: '${songs.length}',
                          ),
                          if (songs.isEmpty) ...[
                            const SizedBox(height: Space.sm),
                            Text(
                              'Nothing by $artist is in your library yet.',
                              style: TypeScale.note.copyWith(
                                fontSize: 14,
                                color: Tones.textMuted,
                              ),
                            ),
                          ] else ...[
                            if (view.ownedReleases.isNotEmpty) ...[
                              const SizedBox(height: Space.md),
                              SizedBox(
                                height: 186,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: view.ownedReleases.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(width: Space.md),
                                  itemBuilder: (context, i) => _ReleaseCard(
                                    release: view.ownedReleases[i],
                                    artUrlFor: widget.artUrlFor,
                                    onTap: () =>
                                        _openAlbum(view.ownedReleases[i]),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: Space.md),
                            for (var i = 0; i < shownSongs.length; i++) ...[
                              if (i == view.leadSongCount && i > 0)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: Space.md,
                                    bottom: Space.xs,
                                    left: Space.xs,
                                  ),
                                  child: Text(
                                    'Features',
                                    style: TypeScale.mono.copyWith(
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                              TrackRow(
                                track: shownSongs[i],
                                onTap: () => widget.player.playQueue(songs, i),
                                player: widget.player,
                                store: widget.store,
                                downloading: widget.downloading.contains(
                                  shownSongs[i].sha,
                                ),
                                onDownload: () =>
                                    widget.onDownload(shownSongs[i]),
                                offline: widget.offline,
                                artUrlFor: widget.artUrlFor,
                              ),
                            ],
                            if (songs.length > _songsPreview)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  onPressed: () =>
                                      setState(() => _allSongs = !_allSongs),
                                  child: Text(
                                    _allSongs
                                        ? 'Show fewer'
                                        : 'Show all ${songs.length} songs',
                                  ),
                                ),
                              ),
                          ],
                          // ---- Songs you don't have ---------------------------
                          const SizedBox(height: Space.xl),
                          _Heading(
                            key: _missingKey,
                            title: 'Not in your library',
                            trailing: view.hasCatalogue ? '$gaps' : null,
                          ),
                          const SizedBox(height: Space.sm),
                          if (_loading)
                            const _Note('Checking the catalogue…')
                          else if (!view.hasCatalogue)
                            _Note(
                              widget.offline
                                  ? 'Connect to the box to see what is missing.'
                                  : 'The catalogue could not be checked just now.',
                            )
                          else if (view.complete)
                            Text(
                              'You have everything we know of.',
                              style: TypeScale.note.copyWith(
                                fontSize: 14,
                                color: Tones.held,
                              ),
                            )
                          else ...[
                            if (view.unfinished.isNotEmpty) ...[
                              const _Label('Finish these'),
                              for (final g in view.unfinished)
                                _GapRow(
                                  group: g,
                                  artist: artist,
                                  artUrlFor: widget.artUrlFor,
                                  onTap: _releaseFor(g) == null
                                      ? null
                                      : () => _openAlbum(_releaseFor(g)!),
                                ),
                            ],
                            if (view.absent.isNotEmpty) ...[
                              if (view.unfinished.isNotEmpty)
                                const SizedBox(height: Space.md),
                              const _Label('Not yet yours'),
                              for (final g in shownAbsent)
                                _GapRow(
                                  group: g,
                                  artist: artist,
                                  artUrlFor: widget.artUrlFor,
                                ),
                              if (view.absent.length > _absentPreview)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton(
                                    onPressed: () => setState(
                                      () => _allAbsent = !_allAbsent,
                                    ),
                                    child: Text(
                                      _allAbsent
                                          ? 'Show fewer'
                                          : 'Show all ${view.absent.length}',
                                    ),
                                  ),
                                ),
                            ],
                          ],
                        ],
                      ),
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

/// The artist: a photo lit from behind, the name, one line of facts, and how
/// much of their catalogue is on this phone.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.artist,
    required this.photoSha,
    required this.artUrlFor,
    required this.view,
    required this.tint,
    required this.onPlay,
    required this.onShuffle,
  });

  final String artist;
  final String? photoSha;
  final String Function(String sha) artUrlFor;
  final ArtistView view;
  final Color tint;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  @override
  Widget build(BuildContext context) {
    final songs = view.ownedSongs.length;
    final albums = view.ownedReleases.length;
    final facts = [
      '$songs ${songs == 1 ? 'song' : 'songs'}',
      '$albums ${albums == 1 ? 'album' : 'albums'}',
      if (view.hasCatalogue)
        '${view.catalogueOwned} of ${view.catalogueTotal} in your library',
    ].join('  ·  ');
    final done = view.completion;
    return Column(
      children: [
        SharedSleeve(
          tag: 'artist-$artist',
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: tint.withValues(alpha: 0.55),
                  blurRadius: 52,
                  spreadRadius: -8,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: Artwork(
              url: photoSha == null ? null : artUrlFor(photoSha!),
              artSha: photoSha,
              size: 152,
              borderRadius: 76,
              shared: true,
              fallback: InitialsAvatar(name: artist, size: 152),
            ),
          ),
        ),
        const SizedBox(height: Space.lg),
        Text(
          artist,
          textAlign: TextAlign.center,
          style: TypeScale.display.copyWith(fontSize: 34),
        ),
        const SizedBox(height: Space.sm),
        Text(facts, textAlign: TextAlign.center, style: TypeScale.mono),
        if (done != null) ...[
          const SizedBox(height: Space.md),
          SizedBox(
            width: 168,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: done,
                minHeight: 3,
                backgroundColor: Tones.hairline,
                valueColor: AlwaysStoppedAnimation(tint),
              ),
            ),
          ),
        ],
        const SizedBox(height: Space.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: onPlay,
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: const Text('Play'),
              style: FilledButton.styleFrom(
                backgroundColor: Tones.text,
                foregroundColor: Tones.base,
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.lg,
                  vertical: Space.sm + 2,
                ),
              ),
            ),
            const SizedBox(width: Space.sm),
            OutlinedButton.icon(
              onPressed: onShuffle,
              icon: const Icon(Icons.shuffle_rounded, size: 18),
              label: const Text('Shuffle'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Tones.text,
                side: BorderSide(color: Tones.hairline),
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.lg,
                  vertical: Space.sm + 2,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({super.key, required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(child: Text(title, style: TypeScale.heading)),
        if (trailing != null) Text(trailing!, style: TypeScale.mono),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs, left: Space.xs),
      child: Text(
        text.toUpperCase(),
        style: TypeScale.mono.copyWith(letterSpacing: 1.2),
      ),
    );
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

class _JumpChip extends StatelessWidget {
  const _JumpChip({
    required this.label,
    required this.count,
    required this.onTap,
  });

  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: PressRow(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: Space.sm - 1,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: Tones.hairline),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TypeScale.caption.copyWith(color: Tones.text)),
              const SizedBox(width: Space.sm),
              Text('$count', style: TypeScale.mono),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollaboratorChip extends StatelessWidget {
  const _CollaboratorChip({
    required this.name,
    required this.songs,
    required this.photoUrl,
    required this.photoSha,
    required this.onTap,
  });

  final String name;
  final int songs;
  final String? photoUrl;
  final String? photoSha;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressRow(
      onTap: onTap,
      borderRadius: BorderRadius.circular(RadiusTokens.control),
      child: SizedBox(
        width: 76,
        child: Column(
          children: [
            Artwork(
              url: photoUrl,
              artSha: photoSha,
              size: 60,
              borderRadius: 30,
              fallback: InitialsAvatar(name: name, size: 60),
            ),
            const SizedBox(height: Space.xs),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TypeScale.caption.copyWith(color: Tones.text),
            ),
            Text(
              '$songs ${songs == 1 ? 'song' : 'songs'}',
              style: TypeScale.mono.copyWith(fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({
    required this.release,
    required this.artUrlFor,
    required this.onTap,
  });

  final ManifestRelease release;
  final String Function(String sha) artUrlFor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final held = release.trackShas.length;
    final total = release.totalTracks;
    return PressRow(
      onTap: onTap,
      borderRadius: BorderRadius.circular(RadiusTokens.control),
      child: SizedBox(
        width: 128,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ArtThumb(
              sha: release.artSha,
              artUrlFor: artUrlFor,
              size: 128,
              borderRadius: 14,
              title: release.title,
              artist: release.artist,
            ),
            const SizedBox(height: Space.sm),
            Text(
              release.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TypeScale.title.copyWith(fontSize: 13),
            ),
            Text(
              [
                // A year, not the full date the daemon sends: the date is
                // too long for a card and gets cut off mid-number.
                if (release.year != null) release.year!.split('-').first,
                if (total != null && held < total)
                  '$held of $total'
                else
                  '$held ${held == 1 ? 'song' : 'songs'}',
              ].join('  ·  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TypeScale.mono.copyWith(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

/// One record the library does not fully have: a part-owned one shows how many
/// songs are missing and opens the record you already hold; one with nothing
/// held is dimmed and says so.
class _GapRow extends StatelessWidget {
  const _GapRow({
    required this.group,
    required this.artist,
    required this.artUrlFor,
    this.onTap,
  });

  final DiscographyGroup group;
  final String artist;
  final String Function(String sha) artUrlFor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final partial = group.owned;
    final total = group.totalTracks;
    final left = partial && total != null ? total - group.ownedTracks : null;
    return PressRow(
      onTap: onTap,
      borderRadius: BorderRadius.circular(RadiusTokens.control),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: Space.sm,
          horizontal: Space.xs,
        ),
        child: Row(
          children: [
            Opacity(
              opacity: partial ? 1 : 0.55,
              child: ArtThumb(
                sha: null,
                artUrlFor: artUrlFor,
                size: 48,
                title: group.title,
                artist: artist,
                borderRadius: 9,
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TypeScale.title.copyWith(
                      color: partial ? Tones.text : Tones.textMuted,
                    ),
                  ),
                  Text(
                    '${group.typeLabel}  ·  ${group.year ?? '—'}',
                    style: TypeScale.mono,
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.sm),
            if (partial && total != null)
              Text(
                '${group.ownedTracks} of $total'
                '${left == null ? '' : '  ·  $left to go'}',
                style: TypeScale.mono.copyWith(color: Tones.warn),
              )
            else
              Text(
                total == null ? 'none yet' : '$total songs',
                style: TypeScale.mono,
              ),
          ],
        ),
      ),
    );
  }
}
