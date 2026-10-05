import 'package:flutter/material.dart';

import '../../core/lyrics/lrc_parser.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/artwork.dart';
import '../../core/ui/cover_tint.dart';
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.lg,
        Space.lg,
        Space.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Lyrics(track: track, onOpen: onOpenLyrics),
          const SizedBox(height: Space.xl),
          _MadeBy(
            track: track,
            manifest: manifest,
            artUrlFor: artUrlFor,
            onOpenArtist: onOpenArtist,
          ),
          if (track.albumLabel != null) ...[
            const SizedBox(height: Space.lg),
            _AlbumCard(track: track, artUrlFor: artUrlFor, onTap: onOpenAlbum),
          ],
          const SizedBox(height: Space.xl),
          _FileSheet(track: track),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.title, {this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: Text(title, style: TypeScale.heading)),
        ?trailing,
      ],
    );
  }
}

/// The words, set the way they are on the lyrics screen: serif, from the left,
/// with the colour of the record down the edge. The first lines are shown at
/// full strength and fade as they go, so it reads as an opening, not a cut-off.
class _Lyrics extends StatelessWidget {
  const _Lyrics({required this.track, required this.onOpen});

  final ManifestTrack track;
  final VoidCallback onOpen;

  static const _shown = 8;

  /// Whichever form the lyrics are in. A synced lyric reads out of `lines`, a
  /// pasted one out of `untimed`, and the preview should not care which.
  ({List<String> lines, int total, bool synced}) _read() {
    final raw = track.lyrics;
    if (raw == null || raw.trim().isEmpty) {
      return (lines: const [], total: 0, synced: false);
    }
    final lrc = LrcParser.parse(raw);
    final all = lrc.lines.isNotEmpty
        ? lrc.lines.map((l) => l.text).toList()
        : lrc.untimed;
    final cleaned = all.where((l) => l.trim().isNotEmpty).toList();
    return (
      lines: cleaned.take(_shown).toList(),
      total: cleaned.length,
      synced: lrc.hasTimedLines,
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = AccentScope.of(context);
    final read = _read();
    final lines = read.lines;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(
          'Lyrics',
          trailing: lines.isEmpty
              ? null
              : Text(
                  read.synced ? 'synced' : 'plain text',
                  style: TypeScale.mono.copyWith(
                    color: read.synced ? accent : Tones.textMuted,
                  ),
                ),
        ),
        const SizedBox(height: Space.md),
        if (lines.isEmpty)
          Material(
            color: Tones.surfaceRaised,
            borderRadius: BorderRadius.circular(RadiusTokens.card),
            child: InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(RadiusTokens.card),
              child: Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'No lyrics yet. Paste them in, then tap along with the '
                        'track to sync them.',
                        style: TypeScale.note.copyWith(
                          fontSize: 15,
                          color: Tones.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: Space.md),
                    Text('Add', style: TypeScale.title.copyWith(color: accent)),
                  ],
                ),
              ),
            ),
          )
        else
          InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(RadiusTokens.control),
            // No bar and no indent: the words sit on the page.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < lines.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      lines[i],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TypeScale.display.copyWith(
                        fontSize: 19,
                        height: 1.3,
                        // Full strength at the top, fading down.
                        color: Tones.text.withValues(
                          alpha: (1 - i * 0.1).clamp(0.35, 1.0),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: Space.xs),
                Row(
                  children: [
                    Text('${read.total} lines', style: TypeScale.mono),
                    const Spacer(),
                    Text(
                      'Read it all',
                      style: TypeScale.title.copyWith(
                        fontSize: 14,
                        color: accent,
                      ),
                    ),
                    Icon(Icons.arrow_forward_rounded, size: 16, color: accent),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The people on the track, as faces. The act first and named as such; guests
/// after it, each reachable, which is the whole point of splitting them out
/// of the credit line in the first place.
class _MadeBy extends StatelessWidget {
  const _MadeBy({
    required this.track,
    required this.manifest,
    required this.artUrlFor,
    required this.onOpenArtist,
  });

  final ManifestTrack track;
  final TunesManifest manifest;
  final String Function(String sha) artUrlFor;
  final void Function(String artist) onOpenArtist;

  String? _artShaFor(String name) {
    for (final a in manifest.artists) {
      if (a.name.toLowerCase() == name.toLowerCase()) return a.artSha;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final act = track.artistKey;
    final guests = track.featured.where((g) => g != act).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(
          guests.isEmpty ? 'Made by' : 'Made together',
          trailing: Text(
            '${1 + guests.length} ${guests.isEmpty ? 'artist' : 'artists'}',
            style: TypeScale.mono,
          ),
        ),
        const SizedBox(height: Space.md),
        Wrap(
          spacing: Space.md,
          runSpacing: Space.lg,
          children: [
            _Person(
              name: act,
              role: 'Artist',
              lead: true,
              artSha: _artShaFor(act),
              artUrlFor: artUrlFor,
              onTap: () => onOpenArtist(act),
            ),
            for (final g in guests)
              _Person(
                name: g,
                role: 'Featured',
                lead: false,
                artSha: _artShaFor(g),
                artUrlFor: artUrlFor,
                onTap: () => onOpenArtist(g),
              ),
          ],
        ),
      ],
    );
  }
}

class _Person extends StatelessWidget {
  const _Person({
    required this.name,
    required this.role,
    required this.lead,
    required this.artSha,
    required this.artUrlFor,
    required this.onTap,
  });

  final String name;
  final String role;
  final bool lead;
  final String? artSha;
  final String Function(String sha) artUrlFor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sha = artSha;
    final size = lead ? 76.0 : 64.0;
    final accent = AccentScope.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(RadiusTokens.control),
      child: SizedBox(
        width: 88,
        child: Column(
          children: [
            // The lead wears a ring in the record's colour, so the act reads
            // as the subject and the guests as company.
            Container(
              padding: EdgeInsets.all(lead ? 3 : 0),
              decoration: lead
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: accent, width: 1.5),
                    )
                  : null,
              child: Artwork(
                url: sha == null ? null : artUrlFor(sha),
                artSha: sha,
                size: size,
                borderRadius: size / 2,
                fallback: InitialsAvatar(name: name, size: size),
              ),
            ),
            const SizedBox(height: Space.sm),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TypeScale.caption.copyWith(color: Tones.text),
            ),
            const SizedBox(height: 2),
            Text(
              role.toUpperCase(),
              style: TypeScale.mono.copyWith(
                fontSize: 10,
                letterSpacing: 1.1,
                color: lead ? accent : Tones.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({
    required this.track,
    required this.artUrlFor,
    required this.onTap,
  });

  final ManifestTrack track;
  final String Function(String sha) artUrlFor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sha = track.artSha;
    final year = track.year?.split('-').first;
    final n = track.totalTracks;
    return Material(
      color: Tones.surfaceRaised,
      borderRadius: BorderRadius.circular(RadiusTokens.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RadiusTokens.card),
        child: Container(
          padding: const EdgeInsets.all(Space.sm + 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(RadiusTokens.card),
            border: Border.all(color: Tones.hairline),
          ),
          child: Row(
            children: [
              Artwork(
                url: sha == null ? null : artUrlFor(sha),
                artSha: sha,
                size: 60,
                borderRadius: 10,
                fallback: const ArtworkPlaceholder(borderRadius: 10),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FROM THE ALBUM',
                      style: TypeScale.mono.copyWith(
                        fontSize: 10,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.albumLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TypeScale.title,
                    ),
                    Text(
                      [?year, if (n != null && n > 0) '$n songs'].join('  ·  '),
                      style: TypeScale.mono,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Tones.textMuted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the file is, as a spec sheet: small caps labels over plain values, two
/// to a row, so the figures line up and read at a glance.
class _FileSheet extends StatelessWidget {
  const _FileSheet({required this.track});

  final ManifestTrack track;

  static String _kHz(int hz) {
    final k = hz / 1000;
    return '${k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1)} kHz';
  }

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Quality', track.qualityLabel),
      if (track.codec != null) ('Format', track.codec!.toUpperCase()),
      if (track.sampleRate != null) ('Sample rate', _kHz(track.sampleRate!)),
      if (track.channels != null)
        ('Channels', track.channels == 2 ? 'Stereo' : '${track.channels}'),
      if (track.bitrate != null)
        ('Bitrate', '${(track.bitrate! / 1000).round()} kbps'),
      ('Length', track.durationLabel),
      if (track.size > 0)
        ('Size', '${(track.size / 1048576).toStringAsFixed(1)} MB'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Heading('The file'),
        const SizedBox(height: Space.md),
        LayoutBuilder(
          builder: (context, c) {
            const gap = Space.md;
            final w = (c.maxWidth - gap) / 2;
            return Wrap(
              spacing: gap,
              runSpacing: Space.md,
              children: [
                for (final (label, value) in rows)
                  SizedBox(
                    width: w,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(
                        Space.md,
                        Space.sm + 2,
                        Space.md,
                        Space.sm + 2,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: AccentScope.of(context)
                                .withValues(alpha: 0.5),
                            width: 1.5,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label.toUpperCase(),
                            style: TypeScale.mono.copyWith(
                              fontSize: 10,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TypeScale.title.copyWith(
                              fontSize: 15,
                              fontVariations: const [
                                FontVariation('wght', 500),
                              ],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
