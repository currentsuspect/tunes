import 'package:flutter/material.dart';

import '../../core/lyrics/lrc_parser.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/artwork.dart';
import '../../core/ui/initials.dart';
import '../../domain/manifest.dart';

/// What sits below the player on Now Playing: the words, who made it, and
/// what the file actually is.
///
/// Only shows what the library genuinely knows. The tags carry title, artist,
/// album, year and the audio properties -- there is no producer, engineer or
/// label data anywhere in the collection, so this does not pretend otherwise
/// by printing empty rows for them.
class NowPlayingDetails extends StatelessWidget {
  const NowPlayingDetails({
    super.key,
    required this.track,
    required this.manifest,
    required this.artUrlFor,
    required this.onOpenArtist,
    required this.onOpenAlbum,
    required this.onOpenLyrics,
  });

  final ManifestTrack track;
  final TunesManifest manifest;
  final String Function(String sha) artUrlFor;
  final void Function(String artist) onOpenArtist;
  final VoidCallback onOpenAlbum;
  final VoidCallback onOpenLyrics;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1, thickness: 0.5, color: Tones.hairline),
        _LyricsPreview(track: track, onOpen: onOpenLyrics),
        const Divider(height: 1, thickness: 0.5, color: Tones.hairline),
        _Credits(
          track: track,
          manifest: manifest,
          artUrlFor: artUrlFor,
          onOpenArtist: onOpenArtist,
          onOpenAlbum: onOpenAlbum,
        ),
        const Divider(height: 1, thickness: 0.5, color: Tones.hairline),
        _Details(track: track),
        const SizedBox(height: Space.xl),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.lg,
        Space.md,
        Space.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TypeScale.caption.copyWith(
                color: Tones.textMuted,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

class _LyricsPreview extends StatelessWidget {
  const _LyricsPreview({required this.track, required this.onOpen});

  final ManifestTrack track;
  final VoidCallback onOpen;

  /// The first few lines, whichever form the lyrics are in. A synced lyric
  /// reads out of `lines`, a pasted one out of `untimed`, and the preview
  /// should not care which.
  List<String> _preview() {
    final raw = track.lyrics;
    if (raw == null || raw.trim().isEmpty) return const [];
    final lrc = LrcParser.parse(raw);
    final lines = lrc.lines.isNotEmpty
        ? lrc.lines.map((l) => l.text).toList()
        : lrc.untimed;
    return lines.take(6).toList();
  }

  @override
  Widget build(BuildContext context) {
    final lines = _preview();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(
          'Lyrics',
          action: lines.isEmpty ? 'Add' : 'Open',
          onAction: onOpen,
        ),
        InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
            child: lines.isEmpty
                ? Text(
                    'No lyrics yet. Paste them in, then tap along with the '
                    'track to sync them.',
                    style: TypeScale.body.copyWith(color: Tones.textMuted),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final l in lines)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            l,
                            style: TypeScale.body.copyWith(height: 1.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _Credits extends StatelessWidget {
  const _Credits({
    required this.track,
    required this.manifest,
    required this.artUrlFor,
    required this.onOpenArtist,
    required this.onOpenAlbum,
  });

  final ManifestTrack track;
  final TunesManifest manifest;
  final String Function(String sha) artUrlFor;
  final void Function(String artist) onOpenArtist;
  final VoidCallback onOpenAlbum;

  String? _artShaFor(String name) {
    for (final a in manifest.artists) {
      if (a.name.toLowerCase() == name.toLowerCase()) return a.artSha;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final act = track.artistKey;
    // Guests listed separately and each reachable, which is the whole point
    // of splitting them out of the credit line in the first place.
    final guests = track.featured.where((g) => g != act).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('Credits'),
        _PersonRow(
          name: act,
          role: 'Artist',
          artSha: _artShaFor(act),
          artUrlFor: artUrlFor,
          onTap: () => onOpenArtist(act),
        ),
        for (final g in guests)
          _PersonRow(
            name: g,
            role: 'Featured',
            artSha: _artShaFor(g),
            artUrlFor: artUrlFor,
            onTap: () => onOpenArtist(g),
          ),
        if (track.albumLabel != null)
          _AlbumRow(
            title: track.albumLabel!,
            year: track.year,
            artSha: track.artSha,
            artUrlFor: artUrlFor,
            onTap: onOpenAlbum,
          ),
      ],
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.name,
    required this.role,
    required this.artSha,
    required this.artUrlFor,
    required this.onTap,
  });

  final String name;
  final String role;
  final String? artSha;
  final String Function(String sha) artUrlFor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sha = artSha;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.sm,
        ),
        child: Row(
          children: [
            Artwork(
              url: sha == null ? null : artUrlFor(sha),
              size: 44,
              borderRadius: 22,
              fallback: InitialsAvatar(name: name, size: 44),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TypeScale.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(role, style: TypeScale.caption),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Tones.textMuted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumRow extends StatelessWidget {
  const _AlbumRow({
    required this.title,
    required this.year,
    required this.artSha,
    required this.artUrlFor,
    required this.onTap,
  });

  final String title;
  final String? year;
  final String? artSha;
  final String Function(String sha) artUrlFor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sha = artSha;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.sm,
        ),
        child: Row(
          children: [
            Artwork(
              url: sha == null ? null : artUrlFor(sha),
              size: 44,
              borderRadius: 6,
              fallback: const ArtworkPlaceholder(borderRadius: 6),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TypeScale.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    year == null ? 'Album' : 'Album · $year',
                    style: TypeScale.caption,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Tones.textMuted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.track});

  final ManifestTrack track;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Quality', track.qualityLabel),
      if (track.sampleRate != null) ('Sample rate', '${track.sampleRate} Hz'),
      if (track.channels != null)
        ('Channels', track.channels == 2 ? 'Stereo' : '${track.channels}'),
      ('Duration', track.durationLabel),
      if (track.size > 0)
        ('Size', '${(track.size / 1048576).toStringAsFixed(1)} MB'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('File'),
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Text(label, style: TypeScale.caption),
                ),
                Expanded(child: Text(value, style: TypeScale.body)),
              ],
            ),
          ),
      ],
    );
  }
}
