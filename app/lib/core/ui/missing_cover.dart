import 'package:flutter/material.dart';

import '../../domain/discography.dart';
import '../theme/tokens.dart';
import 'artwork.dart';
import 'generated_artwork.dart';
import 'initials.dart';

/// The sleeve for a record the library does not have.
///
/// The daemon fetches these from Deezer on its enrichment cycle, so a null
/// [MissingRelease.artSha] is ordinary rather than an error -- it means the
/// cover has not been fetched yet, or no confident match was found. Falling
/// back to the generated tile keeps a rail the same shape either way, so
/// covers arriving later do not reflow the page.
///
/// Shared by the home rail and the discover screen. They used to be the same
/// code twice, which is how two views of one idea start disagreeing.
class MissingCover extends StatelessWidget {
  const MissingCover({
    super.key,
    required this.album,
    required this.artUrlFor,
    this.size = 132,
  });

  final MissingRelease album;
  final String Function(String sha) artUrlFor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final generated = GeneratedArtwork(
      title: album.title,
      artist: album.artist,
      size: size,
      borderRadius: RadiusTokens.card,
      // The act is named in the caption and repeats down the whole rail; the
      // album is what distinguishes one card from the next.
      label: initialsFor(album.title),
    );
    final sha = album.artSha;
    return Artwork(
      url: sha == null ? null : artUrlFor(sha),
      size: size,
      fallback: generated,
    );
  }
}
