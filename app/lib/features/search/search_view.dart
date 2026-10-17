import '../../core/platform/device.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audio/tune_player.dart';
import '../../core/data/download_store.dart';
import '../../core/net/tunes_client.dart';
import '../../core/ui/artwork.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/empty_state.dart';
import '../../core/ui/initials.dart';
import '../../core/theme/tokens.dart';
import '../../domain/fuzzy.dart';
import '../../domain/manifest.dart';
import '../library/library_widgets.dart';

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
    this.onAlbumTap,
    this.onArtistTap,
    this.searchOverride,
  });

  final List<ManifestTrack> tracks;
  final List<ManifestRelease> releases;
  final TunesClient client;
  final TunePlayer player;
  final DownloadStore store;
  final Set<String> downloading;
  final void Function(ManifestTrack) onDownload;
  final bool offline;
  final String Function(String sha) artUrlFor;
  final void Function(ManifestRelease)? onAlbumTap;
  final void Function(String artist)? onArtistTap;
  final Future<SearchResults> Function(String query)? searchOverride;

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  SearchResults? _server;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() => _query = v);
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
        // box unreachable — fall back to the local filter
        if (!mounted) return;
        setState(() => _server = null);
      }
    });
  }

  /// The phone's own search, forgiving of typos, accents and words run
  /// together. Fields are folded once per library, not once per keystroke.
  List<ManifestTrack> _localResults(String q) {
    if (!identical(_indexed, widget.tracks)) {
      _indexed = widget.tracks;
      _fields = {
        for (final t in widget.tracks)
          t.sha: [
            SearchField(t.title, weight: 1.2),
            SearchField(t.artist),
            SearchField(t.album, weight: 0.8),
          ],
      };
    }
    return fuzzyRank(q, widget.tracks, (t) => _fields[t.sha]!);
  }

  List<ManifestTrack>? _indexed;
  Map<String, List<SearchField>> _fields = const {};

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final fromServer = _server != null;
    final local = q.isEmpty ? const <ManifestTrack>[] : _localResults(q);
    // The box answers first when it can, and the phone's fuzzy matches
    // fill in after it: a typo the box misses still finds the song.
    final List<ManifestTrack> results;
    if (fromServer) {
      final seen = {for (final t in _server!.tracks) t.sha};
      results = [
        ..._server!.tracks,
        for (final t in local)
          if (!seen.contains(t.sha)) t,
      ];
    } else {
      results = local;
    }
    // Everything the screen could draw, from either source. The empty state
    // used to be gated on `!fromServer`, so the moment the daemon answered
    // with nothing the guard went false, the list rendered its sections --
    // every one of them conditional on having data -- and what was left was
    // a blank screen with no explanation on it at all.
    final hasResults =
        results.isNotEmpty ||
        (fromServer &&
            (_server!.releases.isNotEmpty ||
                _server!.artists.isNotEmpty ||
                _server!.externalReleases.isNotEmpty ||
                _server!.externalArtists.isNotEmpty));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
          child: TextField(
            controller: _controller,
            autofocus: false,
            onChanged: _onChanged,
            style: TypeScale.body.copyWith(color: Tones.text, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Search tracks, artists, albums',
              hintStyle: TypeScale.note.copyWith(
                fontSize: 15,
                color: Tones.textMuted,
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: Tones.textMuted,
                size: 20,
              ),
              filled: true,
              fillColor: Tones.surfaceRaised,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(RadiusTokens.control),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(RadiusTokens.control),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(RadiusTokens.control),
                borderSide: BorderSide(color: Tones.primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: Space.md),
            ),
          ),
        ),
        if (widget.offline)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
            child: Row(
              children: [
                Icon(Icons.offline_pin_rounded, size: 14, color: Tones.held),
                const SizedBox(width: Space.sm),
                Text(
                  'Searching what is on ${Device.thisOne}',
                  style: TypeScale.mono.copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
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
                  // Says how far it looked: "nothing found" from a search
                  // that only checked the device means something different
                  // from one that asked the daemon too.
                  body: widget.offline
                      ? 'Nothing downloaded to ${Device.thisOne} matches '
                            '"${_query.trim()}". Songs you have not downloaded '
                            'cannot be found without a connection.'
                      : fromServer
                      ? 'Nothing here or beyond your library matches '
                            '"${_query.trim()}".'
                      : 'Nothing in your library matches "${_query.trim()}". '
                            'Still looking further afield.',
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.lg,
                    vertical: Space.md,
                  ),
                  children: [
                    if (results.isNotEmpty) ...[
                      Text('Tracks', style: _sectionStyle()),
                      const SizedBox(height: Space.sm),
                      for (var i = 0; i < results.length; i++) ...[
                        TrackRow(
                          track: results[i],
                          onTap: () => widget.player.playQueue(results, i),
                          player: widget.player,
                          store: widget.store,
                          downloading: widget.downloading.contains(
                            results[i].sha,
                          ),
                          onDownload: () => widget.onDownload(results[i]),
                          offline: widget.offline,
                          artUrlFor: widget.artUrlFor,
                        ),
                        const Divider(),
                      ],
                    ],
                    if (fromServer && _server!.externalReleases.isNotEmpty) ...[
                      const SizedBox(height: Space.md),
                      Text('Albums on MusicBrainz', style: _sectionStyle()),
                      const SizedBox(height: Space.sm),
                      for (final r in _server!.externalReleases) ...[
                        PressRow(
                          onTap: () {
                            if (r.owned && r.releaseId != null) {
                              for (final local in widget.releases) {
                                if (local.id == r.releaseId) {
                                  widget.onAlbumTap?.call(local);
                                  return;
                                }
                              }
                            }
                            if (r.artist != null) {
                              widget.onArtistTap?.call(r.artist!);
                            }
                          },
                          borderRadius: BorderRadius.circular(
                            RadiusTokens.control,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: Space.sm,
                              horizontal: Space.xs,
                            ),
                            child: Row(
                              children: [
                                ArtThumb(
                                  sha: null,
                                  artUrlFor: widget.artUrlFor,
                                  size: 44,
                                  title: r.title,
                                  artist: r.artist ?? '',
                                ),
                                const SizedBox(width: Space.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        r.title,
                                        style: TypeScale.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        [
                                          if (r.artist != null) r.artist!,
                                          r.typeLabel,
                                          r.year ?? '—',
                                        ].join(' · '),
                                        style: TypeScale.caption,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: Space.sm),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: Space.sm,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Tones.surfaceRaised,
                                    borderRadius: BorderRadius.circular(
                                      RadiusTokens.control,
                                    ),
                                    border: Border.all(color: Tones.hairline),
                                  ),
                                  child: Text(
                                    r.owned ? 'in library' : 'not in library',
                                    style: TypeScale.caption.copyWith(
                                      color: r.owned
                                          ? Tones.primary
                                          : Tones.textMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Divider(),
                      ],
                    ],
                    if (fromServer && _server!.externalArtists.isNotEmpty) ...[
                      const SizedBox(height: Space.md),
                      Text('Artists on MusicBrainz', style: _sectionStyle()),
                      const SizedBox(height: Space.sm),
                      for (final a in _server!.externalArtists) ...[
                        PressRow(
                          onTap: widget.onArtistTap == null
                              ? null
                              : () => widget.onArtistTap!(a.name),
                          borderRadius: BorderRadius.circular(
                            RadiusTokens.control,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: Space.sm,
                              horizontal: Space.xs,
                            ),
                            child: Row(
                              children: [
                                InitialsAvatar(name: a.name, size: 44),
                                const SizedBox(width: Space.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        a.name,
                                        style: TypeScale.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        [
                                          if (a.type != null) a.type!,
                                          if (a.disambiguation != null)
                                            a.disambiguation!,
                                        ].join(' · '),
                                        style: TypeScale.caption,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.open_in_new_rounded,
                                  size: 16,
                                  color: Tones.textMuted,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Divider(),
                      ],
                    ],
                    if (fromServer) ...[
                      if (_server!.releases.isNotEmpty) ...[
                        const SizedBox(height: Space.md),
                        Text('Albums', style: _sectionStyle()),
                        const SizedBox(height: Space.sm),
                        for (final r in _server!.releases) ...[
                          PressRow(
                            onTap: widget.onAlbumTap == null
                                ? null
                                : () => widget.onAlbumTap!(r),
                            borderRadius: BorderRadius.circular(
                              RadiusTokens.control,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: Space.sm,
                                horizontal: Space.xs,
                              ),
                              child: Row(
                                children: [
                                  ArtThumb(
                                    sha: r.artSha,
                                    artUrlFor: widget.artUrlFor,
                                    size: 44,
                                    title: r.title,
                                    artist: r.artist,
                                  ),
                                  const SizedBox(width: Space.md),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          r.title,
                                          style: TypeScale.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          '${r.artist} · ${r.trackShas.length}/${r.totalTracks ?? '?'} tracks',
                                          style: TypeScale.caption,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: Tones.textMuted,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Divider(),
                        ],
                      ],
                      if (_server!.artists.isNotEmpty) ...[
                        const SizedBox(height: Space.md),
                        Text('Artists', style: _sectionStyle()),
                        const SizedBox(height: Space.sm),
                        for (final a in _server!.artists) ...[
                          PressRow(
                            onTap: widget.onArtistTap == null
                                ? null
                                : () => widget.onArtistTap!(a.name),
                            borderRadius: BorderRadius.circular(
                              RadiusTokens.control,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: Space.sm,
                                horizontal: Space.xs,
                              ),
                              child: Row(
                                children: [
                                  ArtThumb(
                                    sha: a.artSha,
                                    artUrlFor: widget.artUrlFor,
                                    size: 44,
                                    title: a.name,
                                    artist: a.name,
                                  ),
                                  const SizedBox(width: Space.md),
                                  Expanded(
                                    child: Text(
                                      a.name,
                                      style: TypeScale.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: Tones.textMuted,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Divider(),
                        ],
                      ],
                    ],
                  ],
                ),
        ),
      ],
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
