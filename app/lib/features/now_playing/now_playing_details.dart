import 'package:flutter/material.dart';

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
  });

  final ManifestTrack track;
  final TunesManifest manifest;
  final String Function(String sha) artUrlFor;
  final void Function(String artist) onOpenArtist;
  final VoidCallback onOpenAlbum;

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
              Icon(
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

/// What the file is, as a quality card: the format as a badge, a plain-words
/// verdict with a five-step meter, then the three figures that explain it. The
/// old version was a grid of seven labels and values, which listed everything
/// and said nothing; this one says first how good it is, and shows why.
class _FileSheet extends StatelessWidget {
  const _FileSheet({required this.track});

  final ManifestTrack track;

  static const _lossless = {'flac', 'alac', 'wav', 'aiff', 'aif', 'ape', 'wv'};

  static String _kHz(int hz) {
    final k = hz / 1000;
    return k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1);
  }

  /// The verdict and how many of five steps it earns.
  (String, int) get _tier {
    final codec = (track.codec ?? '').toLowerCase();
    final kbps = (track.bitrate ?? 0) / 1000;
    if (_lossless.contains(codec)) {
      return (
        (track.sampleRate ?? 0) >= 88200 ? 'Hi-res lossless' : 'Lossless',
        5,
      );
    }
    if (kbps >= 256) return ('High quality', 4);
    if (kbps >= 192) return ('Good', 3);
    if (kbps >= 128) return ('Standard', 2);
    return (kbps > 0 ? 'Compact' : 'Unknown quality', 1);
  }

  @override
  Widget build(BuildContext context) {
    final accent = AccentScope.of(context);
    final (verdict, steps) = _tier;
    final stats = <(String, String)>[
      if (track.sampleRate != null) (_kHz(track.sampleRate!), 'kHz'),
      if (track.channels != null)
        (track.channels == 2 ? 'Stereo' : '${track.channels}', 'channels'),
      if (track.bitrate != null) ('${(track.bitrate! / 1000).round()}', 'kbps'),
    ];
    final foot = [
      if (track.durationLabel.isNotEmpty) track.durationLabel,
      if (track.size > 0) '${(track.size / 1048576).toStringAsFixed(1)} MB',
    ].join('  ·  ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Heading('The file'),
        const SizedBox(height: Space.md),
        Container(
          padding: const EdgeInsets.all(Space.md + 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(RadiusTokens.card),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: 0.16),
                accent.withValues(alpha: 0.03),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      (track.codec ?? '?').toUpperCase(),
                      style: TypeScale.mono.copyWith(
                        fontSize: 18,
                        height: 1,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                        color: Tones.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          verdict,
                          style: TypeScale.display.copyWith(
                            fontSize: 20,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            for (var i = 0; i < 5; i++)
                              Container(
                                width: 26,
                                height: 4,
                                margin: const EdgeInsets.only(right: 4),
                                decoration: BoxDecoration(
                                  color: i < steps ? accent : Tones.hairline,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (stats.isNotEmpty) ...[
                const SizedBox(height: Space.lg),
                IntrinsicHeight(
                  child: Row(
                    children: [
                      for (var i = 0; i < stats.length; i++) ...[
                        if (i > 0)
                          VerticalDivider(
                            width: Space.lg,
                            thickness: 1,
                            color: Tones.hairline,
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                stats[i].$1,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TypeScale.title.copyWith(
                                  fontSize: 18,
                                  fontVariations: const [
                                    FontVariation('wght', 500),
                                  ],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                stats[i].$2.toUpperCase(),
                                style: TypeScale.mono.copyWith(
                                  fontSize: 10,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (foot.isNotEmpty) ...[
                const SizedBox(height: Space.md),
                Text(foot, style: TypeScale.caption),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
