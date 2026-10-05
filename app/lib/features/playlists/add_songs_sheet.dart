import 'package:flutter/material.dart';

import '../../core/data/playlist_store.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/artwork.dart';
import '../../core/ui/generated_artwork.dart';
import '../../domain/manifest.dart';

/// The tracks that match what was typed.
///
/// Every word has to appear somewhere in the title, artist or album, in any
/// order, so "swapa nugget" finds Nugget by Swapa. Pure, so it can be tested
/// without a screen.
List<ManifestTrack> matchTracks(
  List<ManifestTrack> tracks,
  String query, {
  int limit = 60,
}) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return const [];
  final out = <ManifestTrack>[];
  for (final t in tracks) {
    final hay = '${t.title} ${t.artistKey} ${t.album}'.toLowerCase();
    if (words.every(hay.contains)) {
      out.add(t);
      if (out.length >= limit) break;
    }
  }
  return out;
}

/// Search the library and put tracks straight into a playlist.
///
/// A playlist used to be fillable only from a track's own menu, one track at a
/// time, from somewhere else in the app. This is the other direction: you are
/// looking at the playlist, and you go and get things for it.
class AddSongsSheet extends StatefulWidget {
  const AddSongsSheet({
    super.key,
    required this.playlistId,
    required this.store,
    required this.tracks,
    required this.alreadyIn,
    required this.artUrlFor,
  });

  final int playlistId;
  final PlaylistStore store;
  final List<ManifestTrack> tracks;

  /// Shas already in the playlist, shown as added rather than offered again.
  final Set<String> alreadyIn;
  final String Function(String sha) artUrlFor;

  static Future<void> show(
    BuildContext context, {
    required int playlistId,
    required PlaylistStore store,
    required List<ManifestTrack> tracks,
    required Set<String> alreadyIn,
    required String Function(String sha) artUrlFor,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Tones.base,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(RadiusTokens.card),
        ),
      ),
      builder: (_) => AddSongsSheet(
        playlistId: playlistId,
        store: store,
        tracks: tracks,
        alreadyIn: alreadyIn,
        artUrlFor: artUrlFor,
      ),
    );
  }

  @override
  State<AddSongsSheet> createState() => _AddSongsSheetState();
}

class _AddSongsSheetState extends State<AddSongsSheet> {
  final _controller = TextEditingController();
  late final Set<String> _added = {...widget.alreadyIn};
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add(ManifestTrack t) async {
    if (_added.contains(t.sha)) return;
    // Marked first: the tap should feel instant, and a second tap in the time
    // the write takes must not add the track twice.
    setState(() => _added.add(t.sha));
    await widget.store.add(widget.playlistId, t.sha);
  }

  @override
  Widget build(BuildContext context) {
    final results = matchTracks(widget.tracks, _query);
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scroll) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.lg,
                  Space.lg,
                  Space.lg,
                  Space.sm,
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Add songs', style: TypeScale.heading),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  style: TypeScale.body.copyWith(color: Tones.text),
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Song, artist or album',
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Tones.textMuted,
                    ),
                    filled: true,
                    fillColor: Tones.surfaceRaised,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(RadiusTokens.control),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Space.sm),
              Expanded(
                child: _query.trim().isEmpty
                    ? Center(
                        child: Text(
                          'Search your library to add songs.',
                          style: TypeScale.note.copyWith(
                            fontSize: 14,
                            color: Tones.textMuted,
                          ),
                        ),
                      )
                    : results.isEmpty
                    ? Center(
                        child: Text(
                          'Nothing in your library matches that.',
                          style: TypeScale.note.copyWith(
                            fontSize: 14,
                            color: Tones.textMuted,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: scroll,
                        itemCount: results.length,
                        itemBuilder: (context, i) {
                          final t = results[i];
                          final done = _added.contains(t.sha);
                          return ListTile(
                            onTap: () => _add(t),
                            leading: Artwork(
                              url: t.artSha == null
                                  ? null
                                  : widget.artUrlFor(t.artSha!),
                              artSha: t.artSha,
                              size: 44,
                              borderRadius: 9,
                              fallback: GeneratedArtwork.fromTrack(
                                t,
                                size: 44,
                                borderRadius: 9,
                              ),
                            ),
                            title: Text(
                              t.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TypeScale.title.copyWith(fontSize: 15),
                            ),
                            subtitle: Text(
                              t.artistAlbumLine,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TypeScale.caption,
                            ),
                            trailing: Icon(
                              done
                                  ? Icons.check_circle_rounded
                                  : Icons.add_circle_outline_rounded,
                              color: done ? Tones.held : Tones.textMuted,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
