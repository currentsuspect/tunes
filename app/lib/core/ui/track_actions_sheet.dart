import '../../features/song/about_nav.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/manifest.dart';
import '../../features/playlists/add_to_playlist_sheet.dart';
import '../data/likes_store.dart';
import '../data/playlist_store.dart';
import '../theme/tokens.dart';
import 'manual_find_sheet.dart';

/// Long-press menu for a track row. Houses every per-track action
/// the app supports today:
///
/// - Play next (inserts at index 0 in the persistent queue)
/// - Add to queue (appends to the persistent queue)
/// - Edit info (writes to track_edits; local-wins across syncs)
/// - Find manually (existing search-URL sheet for unenriched tracks)
/// - Copy sha (so the user can patch enrich.json by hand)
///
/// The sheet is a bottom modal that returns nothing; the caller wires
/// the actual side effects. The actions are passed in as callbacks
/// so this widget stays testable and decoupled from store plumbing.
class TrackActionsSheet extends StatelessWidget {
  const TrackActionsSheet({
    super.key,
    required this.track,
    required this.onPlayNext,
    required this.onAddToQueue,
    required this.onEdit,
    this.onAbout,
  });

  /// Opens the song's own page (the Roon pass); null leaves the row out.
  final VoidCallback? onAbout;

  final ManifestTrack track;
  final Future<void> Function() onPlayNext;
  final Future<void> Function() onAddToQueue;
  final Future<void> Function() onEdit;

  static Future<void> show(
    BuildContext context, {
    required ManifestTrack track,
    required Future<void> Function() onPlayNext,
    required Future<void> Function() onAddToQueue,
    required Future<void> Function() onEdit,
  }) {
    // Read here, under the shell: the sheet's own route sits above it.
    final about = AboutNav.maybeOf(context);
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Tones.surface,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(RadiusTokens.card),
        ),
      ),
      builder: (_) => TrackActionsSheet(
        track: track,
        onPlayNext: onPlayNext,
        onAddToQueue: onAddToQueue,
        onEdit: onEdit,
        onAbout: about == null ? null : () => about.openSong(track),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Header(track: track),
            Divider(height: 1, thickness: 0.5, color: Tones.hairline),
            if (onAbout case final open?)
              _ActionRow(
                icon: Icons.info_outline_rounded,
                label: 'About this song',
                subtitle: 'Its story, who made it, your history with it',
                onTap: () {
                  Navigator.of(context).pop();
                  open();
                },
              ),
            // First, because it is the one action here that says something
            // about the track rather than about the queue.
            if (LikesScope.maybeOf(context) case final likes?)
              _ActionRow(
                icon: likes.isLiked(track.sha)
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                label: likes.isLiked(track.sha) ? 'Liked' : 'Like',
                subtitle: likes.isLiked(track.sha)
                    ? 'Tap to remove from your liked songs'
                    : 'Keep it in your liked songs',
                onTap: () async {
                  Navigator.of(context).pop();
                  await likes.toggle(track.sha);
                },
              ),
            _ActionRow(
              icon: Icons.play_arrow_rounded,
              label: 'Play next',
              subtitle: 'Insert at the top of the queue',
              onTap: () async {
                Navigator.of(context).pop();
                await onPlayNext();
              },
            ),
            if (PlaylistScope.maybeOf(context) case final playlists?)
              _ActionRow(
                icon: Icons.playlist_add_rounded,
                label: 'Add to playlist',
                subtitle: 'Keep it in a list you made',
                onTap: () {
                  Navigator.of(context).pop();
                  AddToPlaylistSheet.show(
                    context,
                    store: playlists,
                    shas: [track.sha],
                  );
                },
              ),
            _ActionRow(
              icon: Icons.queue_music_rounded,
              label: 'Add to queue',
              subtitle: 'Append after the current queue',
              onTap: () async {
                Navigator.of(context).pop();
                await onAddToQueue();
              },
            ),
            _ActionRow(
              icon: Icons.edit_rounded,
              label: 'Edit info',
              subtitle: 'Fix the title, artist, album, or year',
              onTap: () async {
                Navigator.of(context).pop();
                await onEdit();
              },
            ),
            _ActionRow(
              icon: Icons.search_rounded,
              label: 'Find manually',
              subtitle: 'Search MusicBrainz, Spotify, Discogs',
              onTap: () {
                Navigator.of(context).pop();
                ManualFindSheet.show(context, track);
              },
            ),
            _ActionRow(
              icon: Icons.copy_rounded,
              label: 'Copy sha',
              subtitle: track.sha,
              monospace: true,
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: track.sha));
                if (!context.mounted) return;
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('sha copied')));
              },
            ),
            const SizedBox(height: Space.sm),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.track});
  final ManifestTrack track;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.md,
        Space.lg,
        Space.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            track.title,
            style: TypeScale.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            track.artistAlbumLine,
            style: TypeScale.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.monospace = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final bool monospace;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        child: Row(
          children: [
            Icon(icon, color: Tones.text),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TypeScale.title),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: monospace
                          ? TypeScale.caption.copyWith(
                              fontFamily: 'monospace',
                              color: Tones.textMuted,
                            )
                          : TypeScale.caption.copyWith(color: Tones.textMuted),
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

/// Inline editor for the editable identity fields (title, artist,
/// album, year). Saves each field on text-commit via the supplied
/// onSave callback; no auto-debounce.
class EditInfoSheet extends StatefulWidget {
  const EditInfoSheet({super.key, required this.track, required this.onSave});

  final ManifestTrack track;
  final Future<void> Function({
    String? title,
    String? artist,
    String? album,
    String? year,
  })
  onSave;

  static Future<void> show(
    BuildContext context, {
    required ManifestTrack track,
    required Future<void> Function({
      String? title,
      String? artist,
      String? album,
      String? year,
    })
    onSave,
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
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: EditInfoSheet(track: track, onSave: onSave),
      ),
    );
  }

  @override
  State<EditInfoSheet> createState() => _EditInfoSheetState();
}

class _EditInfoSheetState extends State<EditInfoSheet> {
  late final TextEditingController _title;
  late final TextEditingController _artist;
  late final TextEditingController _album;
  late final TextEditingController _year;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.track.title);
    _artist = TextEditingController(text: widget.track.artist);
    _album = TextEditingController(text: widget.track.album);
    _year = TextEditingController(text: widget.track.year ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    _year.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.lg,
          Space.lg,
          Space.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit info', style: TypeScale.title),
            const SizedBox(height: Space.xs),
            Text(
              'Saved values win over future syncs. Empty a field to clear its override and fall back to the file tag or daemon.',
              style: TypeScale.caption.copyWith(color: Tones.textMuted),
            ),
            const SizedBox(height: Space.lg),
            _Field(controller: _title, label: 'Title', hint: 'Track title'),
            const SizedBox(height: Space.md),
            _Field(controller: _artist, label: 'Artist'),
            const SizedBox(height: Space.md),
            _Field(controller: _album, label: 'Album'),
            const SizedBox(height: Space.md),
            _Field(
              controller: _year,
              label: 'Year',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: Space.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: Space.sm),
                FilledButton(
                  onPressed: () async {
                    final s = (
                      title: _title.text.trim(),
                      artist: _artist.text.trim(),
                      album: _album.text.trim(),
                      year: _year.text.trim(),
                    );
                    Navigator.of(context).pop();
                    // Pass all four fields, with empty values as null.
                    // onSave is the only place that can clear an existing
                    // override; if we skipped when all empty, the user
                    // would have no way to "reset to the daemon value".
                    await widget.onSave(
                      title: s.title.isEmpty ? null : s.title,
                      artist: s.artist.isEmpty ? null : s.artist,
                      album: s.album.isEmpty ? null : s.album,
                      year: s.year.isEmpty ? null : s.year,
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType,
  });
  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: TypeScale.body,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Tones.surfaceRaised,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(RadiusTokens.control),
          borderSide: BorderSide(color: Tones.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(RadiusTokens.control),
          borderSide: BorderSide(color: Tones.hairline),
        ),
      ),
    );
  }
}
