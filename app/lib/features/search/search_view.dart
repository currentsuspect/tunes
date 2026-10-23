import '../../core/platform/device.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/download_store.dart';
import '../../core/data/playlist_store.dart';
import '../../core/net/tunes_client.dart';
import '../../core/theme/looks.dart';
import '../../core/ui/artwork.dart';
import '../../core/ui/crayon_marks.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/empty_state.dart';
import '../../core/ui/initials.dart';
import '../../core/theme/tokens.dart';
import '../../domain/library_search.dart';
import '../../domain/manifest.dart';
import '../library/library_widgets.dart';

/// Search (design approved 23 Oct): everything on the device from one box,
/// sorted into Songs, Albums, Artists and Playlists with their counts, a top
/// result to play straight away, and chips for how the query was read --
/// "by Travis Scott", "from 2018" -- that can be tapped off. What the box
/// knows beyond the library follows underneath.
class SearchView extends StatefulWidget {
  const SearchView({
    super.key,
    required this.tracks,
    required this.releases,
    required this.client,
    required this.player,
    required this.store,
    required this.downloading,
    required this.onDownload,
    required this.offline,
    required this.artUrlFor,
    this.artists = const [],
    this.plays = const {},
    this.onAlbumTap,
    this.onArtistTap,
    this.onPlaylistTap,
    this.searchOverride,
  });

  final List<ManifestTrack> tracks;
  final List<ManifestRelease> releases;
  final List<ManifestArtist> artists;

  /// Plays per song, for "most played" and for which songs lead.
  final Map<String, int> plays;
  final TunesClient client;
  final TunePlayer player;
  final DownloadStore store;
  final Set<String> downloading;
  final void Function(ManifestTrack) onDownload;
  final bool offline;
  final String Function(String sha) artUrlFor;
  final void Function(ManifestRelease)? onAlbumTap;
  final void Function(String artist)? onArtistTap;
  final void Function(PlaylistSummary)? onPlaylistTap;
  final Future<SearchResults> Function(String query)? searchOverride;

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  SearchResults? _server;

  SearchKind _kind = SearchKind.all;
  SongSort _sort = SongSort.best;
  bool _onPhone = false;

  /// Readings tapped off for this query.
  Set<FacetKind> _off = {};

  SearchIndex? _index;
  List<ManifestTrack>? _indexedTracks;
  Map<String, int>? _indexedPlays;

  PlaylistStore? _playlistStore;
  List<PlaylistSummary> _playlists = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = PlaylistScope.maybeOf(context);
    if (!identical(store, _playlistStore)) {
      _playlistStore?.removeListener(_loadPlaylists);
      _playlistStore = store;
      store?.addListener(_loadPlaylists);
      _loadPlaylists();
    }
  }

  Future<void> _loadPlaylists() async {
    final store = _playlistStore;
    if (store == null) return;
    final all = await store.summaries();
    if (mounted) setState(() => _playlists = all);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _playlistStore?.removeListener(_loadPlaylists);
    _controller.dispose();
    super.dispose();
  }

  /// Built once per library (a third of a second for two thousand songs),
  /// not once per keystroke.
  SearchIndex get _idx {
    if (_index == null ||
        !identical(_indexedTracks, widget.tracks) ||
        !identical(_indexedPlays, widget.plays)) {
      _indexedTracks = widget.tracks;
      _indexedPlays = widget.plays;
      final index = SearchIndex(
        tracks: widget.tracks,
        releases: widget.releases,
        artists: widget.artists,
        plays: widget.plays,
      );
      _index = index;
      // Lyric search gets ready in the background; a query typed meanwhile
      // picks the lyrics up when they land.
      index.warmLyrics().then((_) {
        if (mounted && identical(_index, index) && _query.trim().isNotEmpty) {
          setState(() {});
        }
      });
    }
    return _index!;
  }

  void _onChanged(String v) {
    setState(() {
      _query = v;
      if (v.trim().isEmpty) {
        _off = {};
        _kind = SearchKind.all;
      }
    });
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      setState(() => _server = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (widget.offline) return;
      try {
        final q = v.trim();
        final future =
            widget.searchOverride?.call(q) ?? widget.client.search(q);
        final results = await future;
        if (_controller.text.trim() != q) return;
        if (!mounted) return;
        setState(() => _server = results);
      } catch (_) {
        // box unreachable: the library search below needs nothing from it
        if (!mounted) return;
        setState(() => _server = null);
      }
    });
  }

  void _clear() {
    _controller.clear();
    _onChanged('');
  }

  bool _held(ManifestTrack t) => widget.store.pathFor(t.sha) != null;

  LibrarySearchResults _results() => _idx.search(
    _query,
    off: _off,
    sort: _sort,
    // Offline, only what is here can play.
    onlyWhere: _onPhone || widget.offline ? _held : null,
    playlists: [
      for (final p in _playlists)
        SearchPlaylist(id: p.id, name: p.name, count: p.trackCount),
    ],
  );

  PlaylistSummary? _summary(int id) {
    for (final p in _playlists) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// The box's own answer can know a record or artist this phone's copy of
  /// the library has not caught up with yet: those join the results.
  LibrarySearchResults _withBox(LibrarySearchResults r, SearchResults? box) {
    if (box == null || r.query.facets.isNotEmpty) return r;
    final ids = {for (final x in r.records) x.id};
    final local = {for (final x in widget.releases) x.id};
    final names = {for (final a in r.artists) a.name};
    final records = [
      for (final x in box.releases)
        if (!ids.contains(x.id) && !local.contains(x.id)) x,
    ];
    final artists = [
      for (final a in box.artists)
        if (!names.contains(a.name) && !_idx.artistNames.contains(a.name))
          SearchArtist(
            name: a.name,
            songs: 0,
            records: 0,
            featuredOn: 0,
            artSha: a.artSha,
          ),
    ];
    if (records.isEmpty && artists.isEmpty) return r;
    return LibrarySearchResults(
      query: r.query,
      songs: r.songs,
      featuring: r.featuring,
      records: [...r.records, ...records],
      artists: [...r.artists, ...artists],
      playlists: r.playlists,
      top: r.top,
      lyrics: r.lyrics,
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim();
    final server = _server;
    final r = q.isEmpty ? null : _withBox(_results(), server);
    final external =
        server != null &&
        (server.externalReleases.isNotEmpty ||
            server.externalArtists.isNotEmpty);
    final hasResults = (r != null && !r.isEmpty) || external;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
          child: _SearchBox(
            controller: _controller,
            onChanged: _onChanged,
            onClear: _clear,
          ),
        ),
        if (widget.offline)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
            child: Row(
              children: [
                Looks.current.kind == LookKind.crayon
                    ? CrayonMarkIcon(
                        CrayonMark.tick,
                        size: 15,
                        color: Tones.held,
                      )
                    : Icon(
                        Icons.offline_pin_rounded,
                        size: 14,
                        color: Tones.held,
                      ),
                const SizedBox(width: Space.sm),
                Text(
                  'Searching what is on ${Device.thisOne}',
                  style: TypeScale.mono.copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
        if (r != null && !r.isEmpty) ...[
          const SizedBox(height: Space.md),
          _KindChips(
            kind: _kind,
            results: r,
            onKind: (k) => setState(() => _kind = k),
          ),
          if (r.query.facets.isNotEmpty ||
              _kind == SearchKind.songs ||
              _off.isNotEmpty)
            _Refine(
              results: r,
              showSongTools: _kind == SearchKind.songs,
              onPhone: _onPhone,
              offline: widget.offline,
              sort: _sort,
              off: _off,
              onOff: (k) => setState(() => _off = {..._off, k}),
              onUndoOff: () => setState(() => _off = {}),
              onPhoneChanged: (v) => setState(() => _onPhone = v),
              onSort: (s) => setState(() => _sort = s),
            ),
        ],
        const SizedBox(height: Space.sm),
        Expanded(
          child: q.isEmpty
              ? _BrowseWhenEmpty(
                  tracks: widget.tracks,
                  releases: widget.releases,
                  artUrlFor: widget.artUrlFor,
                  onArtistTap: widget.onArtistTap,
                  onAlbumTap: widget.onAlbumTap,
                )
              : !hasResults
              ? EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'Nothing found',
                  body: widget.offline
                      ? 'Nothing downloaded to ${Device.thisOne} matches '
                            '"$q". Songs you have not downloaded '
                            'show up once you are back online.'
                      : server != null
                      ? 'Nothing here or beyond your library matches '
                            '"$q".'
                      : 'Nothing in your library matches "$q". '
                            'Still looking further afield.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    Space.sm,
                    Space.lg,
                    Space.xl,
                  ),
                  children: [
                    if (r != null && !r.isEmpty)
                      ..._library(context, r)
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.sm),
                        child: Text(
                          'Not in your library yet. Found out there:',
                          style: TypeScale.note.copyWith(
                            color: Tones.textMuted,
                          ),
                        ),
                      ),
                    if (_kind == SearchKind.all && server != null)
                      ..._beyond(context, server),
                  ],
                ),
        ),
      ],
    );
  }

  // --- the library -------------------------------------------------------

  List<Widget> _library(BuildContext context, LibrarySearchResults r) {
    final artist = r.query.of(FacetKind.artist)?.value;
    switch (_kind) {
      case SearchKind.all:
        return [
          if (r.top case final top?) ...[
            _Heading('Top result'),
            _TopCard(
              top: top,
              artUrlFor: widget.artUrlFor,
              onOpen: () => _openTop(top),
              onPlay: () => _playTop(top),
            ),
            const SizedBox(height: Space.lg),
          ],
          if (r.songCount > 0) ...[
            _Heading(
              'Songs',
              more: r.songCount > 4 ? 'See all ${r.songCount}' : null,
              onMore: () => setState(() => _kind = SearchKind.songs),
            ),
            ..._songRows([...r.songs, ...r.featuring].take(4).toList()),
            const SizedBox(height: Space.lg),
          ],
          if (r.lyrics.isNotEmpty) ...[
            _Heading(
              'From the lyrics',
              more: r.lyrics.length > 3 ? 'See all ${r.lyrics.length}' : null,
              onMore: () => setState(() => _kind = SearchKind.lyrics),
            ),
            for (final h in r.lyrics.take(3)) _lyricRow(h, r.lyrics),
            const SizedBox(height: Space.lg),
          ],
          if (r.records.isNotEmpty) ...[
            _Heading(
              'Albums',
              more: r.records.length > 3 ? 'See all ${r.records.length}' : null,
              onMore: () => setState(() => _kind = SearchKind.albums),
            ),
            _RecordStrip(
              records: r.records.take(12).toList(),
              artUrlFor: widget.artUrlFor,
              onTap: widget.onAlbumTap,
            ),
            const SizedBox(height: Space.lg),
          ],
          if (r.artists.isNotEmpty) ...[
            _Heading(
              'Artists',
              more: r.artists.length > 3 ? 'See all ${r.artists.length}' : null,
              onMore: () => setState(() => _kind = SearchKind.artists),
            ),
            for (final a in r.artists.take(3)) _artistRow(a),
            const SizedBox(height: Space.lg),
          ],
          if (r.playlists.isNotEmpty) ...[
            _Heading('Playlists'),
            for (final p in r.playlists.take(3)) _playlistRow(p),
            const SizedBox(height: Space.lg),
          ],
        ];
      case SearchKind.songs:
        return [
          ..._songRows(r.songs),
          if (r.featuring.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            Text(
              artist == null ? 'Featuring' : 'Songs with $artist on them',
              style: TypeScale.caption,
            ),
            const SizedBox(height: Space.xs),
            ..._songRows(r.featuring),
          ],
        ];
      case SearchKind.lyrics:
        return [for (final h in r.lyrics) _lyricRow(h, r.lyrics)];
      case SearchKind.albums:
        return [
          for (final rec in r.records)
            _ListRow(
              leading: ArtThumb(
                sha: rec.artSha,
                artUrlFor: widget.artUrlFor,
                size: 52,
                title: rec.title,
                artist: rec.artist,
              ),
              title: rec.title,
              subtitle: [
                rec.artist,
                if (rec.year != null && rec.year!.length >= 4)
                  rec.year!.substring(0, 4),
                '${rec.trackShas.length} songs',
              ].join(' · '),
              onTap: widget.onAlbumTap == null
                  ? null
                  : () => widget.onAlbumTap!(rec),
            ),
        ];
      case SearchKind.artists:
        return [for (final a in r.artists) _artistRow(a)];
      case SearchKind.playlists:
        return [for (final p in r.playlists) _playlistRow(p)];
    }
  }

  List<Widget> _songRows(List<ManifestTrack> songs) => [
    for (var i = 0; i < songs.length; i++) ...[
      TrackRow(
        track: songs[i],
        onTap: () => widget.player.playQueue(songs, i),
        player: widget.player,
        store: widget.store,
        downloading: widget.downloading.contains(songs[i].sha),
        onDownload: () => widget.onDownload(songs[i]),
        offline: widget.offline,
        artUrlFor: widget.artUrlFor,
      ),
      const Divider(),
    ],
  ];

  /// A song found by its words: the line it was found by, quoted.
  Widget _lyricRow(LyricHit h, List<LyricHit> all) {
    final t = h.track;
    return PressRow(
      onTap: () {
        final list = [for (final x in all) x.track];
        widget.player.playQueue(list, list.indexOf(t));
      },
      borderRadius: BorderRadius.circular(RadiusTokens.control),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: Space.sm,
          horizontal: Space.xs,
        ),
        child: Row(
          children: [
            ArtThumb(
              sha: t.artSha,
              artUrlFor: widget.artUrlFor,
              size: 48,
              title: t.title,
              artist: t.artistDisplay,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '“${h.line}”',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TypeScale.note.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${t.title} · ${t.artistDisplay}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TypeScale.caption,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _artistRow(SearchArtist a) => _ListRow(
    leading: a.artSha == null
        ? InitialsAvatar(name: a.name, size: 48)
        : ClipOval(
            child: ArtThumb(
              sha: a.artSha,
              artUrlFor: widget.artUrlFor,
              size: 48,
              title: a.name,
              artist: a.name,
            ),
          ),
    title: a.name,
    subtitle: _artistFacts(a),
    onTap: widget.onArtistTap == null
        ? null
        : () => widget.onArtistTap!(a.name),
  );

  Widget _playlistRow(SearchPlaylist p) => _ListRow(
    leading: InitialsAvatar(name: p.name, size: 48),
    title: p.name,
    subtitle: 'Playlist · ${p.count} songs',
    onTap: widget.onPlaylistTap == null
        ? null
        : () {
            final s = _summary(p.id);
            if (s != null) widget.onPlaylistTap!(s);
          },
  );

  List<ManifestTrack> _tracksOf(ManifestRelease r) {
    final bySha = {for (final t in widget.tracks) t.sha: t};
    return [
      for (final s in r.trackShas)
        if (bySha[s] case final t?)
          if (!widget.offline || _held(t)) t,
    ];
  }

  /// An artist's own songs, most played first: what "play" on them means.
  List<ManifestTrack> _songsOf(String artist) =>
      [
        for (final t in widget.tracks)
          if (t.artistKey == artist && (!widget.offline || _held(t))) t,
      ]..sort(
        (a, b) =>
            (widget.plays[b.sha] ?? 0).compareTo(widget.plays[a.sha] ?? 0),
      );

  void _openTop(TopResult top) {
    switch (top) {
      case TopArtist(:final artist):
        widget.onArtistTap?.call(artist.name);
      case TopRecord(:final release):
        widget.onAlbumTap?.call(release);
      case TopSong(:final track):
        widget.player.playQueue([track], 0);
    }
  }

  void _playTop(TopResult top) {
    final list = switch (top) {
      TopArtist(:final artist) => _songsOf(artist.name),
      TopRecord(:final release) => _tracksOf(release),
      TopSong(:final track) => [track],
    };
    if (list.isNotEmpty) widget.player.playQueue(list, 0);
  }

  // --- beyond the library ------------------------------------------------

  List<Widget> _beyond(BuildContext context, SearchResults server) => [
    if (server.externalReleases.isNotEmpty) ...[
      _Heading('Albums on MusicBrainz'),
      for (final r in server.externalReleases)
        _ListRow(
          leading: ArtThumb(
            sha: null,
            artUrlFor: widget.artUrlFor,
            size: 48,
            title: r.title,
            artist: r.artist ?? '',
          ),
          title: r.title,
          subtitle: [
            if (r.artist != null) r.artist!,
            r.typeLabel,
            r.year ?? '—',
            r.owned ? 'in your library' : 'not in your library',
          ].join(' · '),
          onTap: () {
            if (r.owned && r.releaseId != null) {
              for (final local in widget.releases) {
                if (local.id == r.releaseId) {
                  widget.onAlbumTap?.call(local);
                  return;
                }
              }
            }
            if (r.artist != null) widget.onArtistTap?.call(r.artist!);
          },
        ),
      const SizedBox(height: Space.lg),
    ],
    if (server.externalArtists.isNotEmpty) ...[
      _Heading('Artists on MusicBrainz'),
      for (final a in server.externalArtists)
        _ListRow(
          leading: InitialsAvatar(name: a.name, size: 48),
          title: a.name,
          subtitle: [
            if (a.type != null) a.type!,
            if (a.disambiguation != null) a.disambiguation!,
          ].join(' · '),
          onTap: widget.onArtistTap == null
              ? null
              : () => widget.onArtistTap!(a.name),
        ),
    ],
  ];
}

String _artistFacts(SearchArtist a) => [
  'Artist',
  if (a.songs > 0) '${a.songs} ${a.songs == 1 ? 'song' : 'songs'}',
  if (a.records > 0) '${a.records} ${a.records == 1 ? 'record' : 'records'}',
  if (a.featuredOn > 0) 'featured on ${a.featuredOn}',
].join(' · ');

// --- pieces ----------------------------------------------------------------

bool get _crayon => Looks.current.kind == LookKind.crayon;

/// Crayon draws chips and cards as stickers: ink edge, hard shadow. Other
/// looks keep their hairline.
BoxBorder _edge() => Border.all(
  color: _crayon ? Tones.text : Tones.hairline,
  width: _crayon ? 2 : 1,
);

class _SearchBox extends StatelessWidget {
  const _SearchBox({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(RadiusTokens.control);
    final rest = _crayon
        ? BorderSide(color: Tones.text, width: 2)
        : BorderSide.none;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: _crayon
            ? [
                BoxShadow(
                  color: Looks.current.inkShadow,
                  offset: const Offset(2, 2),
                ),
              ]
            : null,
      ),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => TextField(
          controller: controller,
          autofocus: false,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          style: TypeScale.body.copyWith(color: Tones.text, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Songs, albums, artists, playlists',
            hintStyle: TypeScale.note.copyWith(
              fontSize: 15,
              color: Tones.textMuted,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: _crayon ? Tones.text : Tones.textMuted,
              size: 20,
            ),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    onPressed: onClear,
                    icon: Icon(
                      Icons.close_rounded,
                      color: Tones.textMuted,
                      size: 20,
                    ),
                  ),
            filled: true,
            fillColor: Tones.surfaceRaised,
            border: OutlineInputBorder(borderRadius: radius, borderSide: rest),
            enabledBorder: OutlineInputBorder(
              borderRadius: radius,
              borderSide: rest,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(
                color: _crayon ? Tones.text : Tones.primary,
                width: _crayon ? 2 : 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: Space.md),
          ),
        ),
      ),
    );
  }
}

/// All, Songs, Albums, Artists, Playlists, each with how many.
class _KindChips extends StatelessWidget {
  const _KindChips({
    required this.kind,
    required this.results,
    required this.onKind,
  });

  final SearchKind kind;
  final LibrarySearchResults results;
  final ValueChanged<SearchKind> onKind;

  @override
  Widget build(BuildContext context) {
    final r = results;
    final kinds = <(SearchKind, String, int?)>[
      (SearchKind.all, 'All', null),
      (SearchKind.songs, 'Songs', r.songCount),
      (SearchKind.lyrics, 'Lyrics', r.lyrics.length),
      (SearchKind.albums, 'Albums', r.records.length),
      (SearchKind.artists, 'Artists', r.artists.length),
      (SearchKind.playlists, 'Playlists', r.playlists.length),
    ];
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        children: [
          for (final (k, label, n) in kinds)
            if (n == null || n > 0 || k == kind)
              Padding(
                padding: const EdgeInsets.only(right: Space.sm),
                child: _Pill(
                  label: n == null ? label : '$label $n',
                  selected: k == kind,
                  onTap: () => onKind(k),
                ),
              ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
    this.trailing,
    this.dashed = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;
  final Widget? trailing;

  /// A reading of the query rather than a choice: drawn softer.
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Tones.base : Tones.text;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? Tones.text
            : dashed
            ? Tones.surface
            : Tones.surfaceRaised,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected || _crayon ? Tones.text : Tones.hairline,
            width: _crayon ? 2 : 1,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                leading == null ? 14 : 10,
                0,
                trailing == null ? 14 : 10,
                0,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 6)],
                  Text(
                    label,
                    style: TypeScale.caption.copyWith(
                      color: fg,
                      fontSize: 13,
                      letterSpacing: 0,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 6),
                    trailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The readings ("by Travis Scott", "from 2018") with an x to undo each,
/// and in Songs, "On this phone" and the order.
class _Refine extends StatelessWidget {
  const _Refine({
    required this.results,
    required this.showSongTools,
    required this.onPhone,
    required this.offline,
    required this.sort,
    required this.off,
    required this.onOff,
    required this.onUndoOff,
    required this.onPhoneChanged,
    required this.onSort,
  });

  final LibrarySearchResults results;
  final bool showSongTools;
  final bool onPhone;
  final bool offline;
  final SongSort sort;
  final Set<FacetKind> off;
  final ValueChanged<FacetKind> onOff;
  final VoidCallback onUndoOff;
  final ValueChanged<bool> onPhoneChanged;
  final ValueChanged<SongSort> onSort;

  static String sortLabel(SongSort s) => switch (s) {
    SongSort.best => 'Best match',
    SongSort.mostPlayed => 'Most played first',
    SongSort.newest => 'Newest first',
    SongSort.az => 'A to Z',
  };

  @override
  Widget build(BuildContext context) {
    final facets = results.query.facets;
    final guessed = facets.where((f) => f.inferred).toList();
    final x = Icon(Icons.close_rounded, size: 14, color: Tones.text);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final f in facets)
                _Pill(
                  label: f.label,
                  selected: false,
                  dashed: true,
                  trailing: x,
                  onTap: () => onOff(f.kind),
                ),
              if (showSongTools && !offline)
                _Pill(
                  label: 'On ${Device.thisOne}',
                  selected: onPhone,
                  leading: _crayon
                      ? CrayonMarkIcon(
                          CrayonMark.tick,
                          size: 14,
                          color: onPhone ? Tones.base : Tones.held,
                        )
                      : Icon(
                          Icons.offline_pin_rounded,
                          size: 14,
                          color: onPhone ? Tones.base : Tones.held,
                        ),
                  onTap: () => onPhoneChanged(!onPhone),
                ),
              if (showSongTools)
                PopupMenuButton<SongSort>(
                  tooltip: 'Order',
                  initialValue: sort,
                  onSelected: onSort,
                  itemBuilder: (_) => [
                    for (final s in SongSort.values)
                      PopupMenuItem(value: s, child: Text(sortLabel(s))),
                  ],
                  child: IgnorePointer(
                    child: _Pill(
                      label: sortLabel(sort),
                      selected: false,
                      trailing: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: Tones.text,
                      ),
                      onTap: () {},
                    ),
                  ),
                ),
              if (off.isNotEmpty && facets.isEmpty)
                _Pill(
                  label: 'Read it for me again',
                  selected: false,
                  onTap: onUndoOff,
                ),
            ],
          ),
          if (guessed.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            Text(
              '${guessed.map(_reading).join(', ')}. Tap a chip to undo it.',
              style: TypeScale.note.copyWith(
                fontSize: 13,
                color: Tones.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _reading(Facet f) => switch (f.kind) {
    FacetKind.year => '"${f.value}" read as a year',
    FacetKind.artist => 'read as ${f.value}',
    FacetKind.album => 'read as the album ${f.value}',
  };
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.more, this.onMore});

  final String text;
  final String? more;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(text, style: TypeScale.heading.copyWith(fontSize: 20)),
          ),
          if (more != null)
            TextButton(
              onPressed: onMore,
              style: TextButton.styleFrom(foregroundColor: Tones.text),
              child: Text(more!),
            ),
        ],
      ),
    );
  }
}

class _TopCard extends StatelessWidget {
  const _TopCard({
    required this.top,
    required this.artUrlFor,
    required this.onOpen,
    required this.onPlay,
  });

  final TopResult top;
  final String Function(String sha) artUrlFor;
  final VoidCallback onOpen;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final (title, facts, art, round) = switch (top) {
      TopArtist(:final artist) => (
        artist.name,
        _artistFacts(artist),
        artist.artSha,
        true,
      ),
      TopRecord(:final release) => (
        release.title,
        [
          release.typeLabel,
          release.artist,
          if (release.year != null && release.year!.length >= 4)
            release.year!.substring(0, 4),
        ].join(' · '),
        release.artSha,
        false,
      ),
      TopSong(:final track) => (
        track.title,
        'Song · ${track.artistAlbumLine}',
        track.artSha,
        false,
      ),
    };
    final thumb = ArtThumb(
      sha: art,
      artUrlFor: artUrlFor,
      size: 72,
      title: title,
      artist: title,
      borderRadius: round ? 36 : 10,
    );
    final radius = BorderRadius.circular(RadiusTokens.card);
    return Container(
      decoration: BoxDecoration(
        color: Tones.surfaceRaised,
        borderRadius: radius,
        border: _edge(),
        boxShadow: _crayon
            ? [
                BoxShadow(
                  color: Looks.current.inkShadow,
                  offset: const Offset(4, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Row(
              children: [
                round && art == null
                    ? InitialsAvatar(name: title, size: 72)
                    : thumb,
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TypeScale.display.copyWith(fontSize: 22),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        facts,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TypeScale.caption,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.sm),
                Tooltip(
                  message: 'Play $title',
                  child: Material(
                    color: Tones.primary,
                    shape: CircleBorder(
                      side: _crayon
                          ? BorderSide(color: Tones.text, width: 2)
                          : BorderSide.none,
                    ),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onPlay,
                      child: SizedBox.square(
                        dimension: 48,
                        child: Icon(
                          Icons.play_arrow_rounded,
                          color: _crayon ? Tones.text : Tones.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordStrip extends StatelessWidget {
  const _RecordStrip({
    required this.records,
    required this.artUrlFor,
    required this.onTap,
  });

  final List<ManifestRelease> records;
  final String Function(String sha) artUrlFor;
  final void Function(ManifestRelease)? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 172,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: records.length,
        separatorBuilder: (_, _) => const SizedBox(width: Space.md),
        itemBuilder: (context, i) {
          final r = records[i];
          final year = r.year != null && r.year!.length >= 4
              ? r.year!.substring(0, 4)
              : null;
          return PressRow(
            onTap: onTap == null ? null : () => onTap!(r),
            child: SizedBox(
              width: 116,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ArtThumb(
                    sha: r.artSha,
                    artUrlFor: artUrlFor,
                    size: 116,
                    title: r.title,
                    artist: r.artist,
                    borderRadius: 12,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    r.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TypeScale.title.copyWith(fontSize: 13.5),
                  ),
                  Text(
                    [?year, '${r.trackShas.length} songs'].join(' · '),
                    maxLines: 1,
                    style: TypeScale.caption,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
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
            leading,
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TypeScale.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: TypeScale.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Tones.textMuted),
          ],
        ),
      ),
    );
  }
}

/// What Search shows before you type.
///
/// It used to be one line of grey text in the middle of an otherwise empty
/// screen. The library is already on the device, so there is no reason not to
/// offer a way into it.
class _BrowseWhenEmpty extends StatelessWidget {
  const _BrowseWhenEmpty({
    required this.tracks,
    required this.releases,
    required this.artUrlFor,
    this.onArtistTap,
    this.onAlbumTap,
  });

  final List<ManifestTrack> tracks;
  final List<ManifestRelease> releases;
  final String Function(String sha) artUrlFor;
  final void Function(String artist)? onArtistTap;
  final void Function(ManifestRelease)? onAlbumTap;

  @override
  Widget build(BuildContext context) {
    // Weight by how much of the library each act actually accounts for, and
    // borrow a cover from one of their tracks so the row is not a wall of
    // initials.
    final counts = <String, int>{};
    final artFor = <String, String>{};
    for (final t in tracks) {
      final name = t.artistKey;
      if (name.isEmpty || name == 'unknown artist') continue;
      counts[name] = (counts[name] ?? 0) + 1;
      final art = t.artSha;
      if (art != null && !artFor.containsKey(name)) artFor[name] = art;
    }
    final top = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        if (byCount != 0) return byCount;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    final artists = top.take(12).toList();
    final albums = releases.take(12).toList();

    if (artists.isEmpty && albums.isEmpty) {
      return Center(
        child: Text(
          'Search your library. Results appear as you type.',
          style: TypeScale.note,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(top: Space.md, bottom: Space.lg),
      children: [
        if (artists.isNotEmpty) ...[
          const _BrowseHeader('Your artists'),
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              itemCount: artists.length,
              separatorBuilder: (_, _) => const SizedBox(width: Space.md),
              itemBuilder: (context, i) {
                final name = artists[i];
                final art = artFor[name];
                return SizedBox(
                  width: 84,
                  child: PressRow(
                    onTap: onArtistTap == null
                        ? null
                        : () => onArtistTap!(name),
                    borderRadius: BorderRadius.circular(42),
                    child: Column(
                      children: [
                        Artwork(
                          url: art == null ? null : artUrlFor(art),
                          artSha: art,
                          size: 72,
                          borderRadius: 36,
                          fallback: InitialsAvatar(name: name, size: 72),
                        ),
                        const SizedBox(height: Space.sm),
                        Text(
                          name,
                          style: TypeScale.caption.copyWith(color: Tones.text),
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        if (albums.isNotEmpty) ...[
          const SizedBox(height: Space.lg),
          const _BrowseHeader('Albums'),
          SizedBox(
            height: 172,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              itemCount: albums.length,
              separatorBuilder: (_, _) => const SizedBox(width: Space.md),
              itemBuilder: (context, i) {
                final r = albums[i];
                final art = r.artSha;
                return SizedBox(
                  width: 124,
                  child: PressRow(
                    onTap: onAlbumTap == null ? null : () => onAlbumTap!(r),
                    borderRadius: BorderRadius.circular(RadiusTokens.control),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Artwork(
                          url: art == null ? null : artUrlFor(art),
                          artSha: art,
                          size: 124,
                          borderRadius: RadiusTokens.control,
                          fallback: ArtworkPlaceholder(
                            borderRadius: RadiusTokens.control,
                          ),
                        ),
                        const SizedBox(height: Space.sm),
                        Text(
                          r.title,
                          style: TypeScale.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// Result and browse section names in the serif, one size, so a screen of
/// results reads as headings and rows rather than a column of equals.
TextStyle _sectionStyle() => TypeScale.heading.copyWith(fontSize: 21);

class _BrowseHeader extends StatelessWidget {
  const _BrowseHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
      child: Text(label, style: _sectionStyle()),
    );
  }
}
