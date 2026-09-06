import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/manifest.dart';
import '../theme/tokens.dart';

/// Bottom sheet that helps the user manually resolve a track whose
/// auto-enrichment has failed or produced 'unknown artist' / 'unknown
/// album'. Surfaces search URLs for MusicBrainz, Spotify, Discogs,
/// and DuckDuckGo, plus one-tap copy of each URL to the clipboard.
/// Does not open browsers (no url_launcher dep); the user pastes the
/// URL into whatever browser they want.
class ManualFindSheet extends StatelessWidget {
  const ManualFindSheet({super.key, required this.track});

  final ManifestTrack track;

  static Future<void> show(BuildContext context, ManifestTrack track) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Tones.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(RadiusTokens.card),
        ),
      ),
      builder: (_) => ManualFindSheet(track: track),
    );
  }

  @override
  Widget build(BuildContext context) {
    final queries = _searchQueries(track);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(track.title, style: TypeScale.title),
            const SizedBox(height: Space.xs),
            Text(
              track.artistAlbumLine,
              style: TypeScale.body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: Space.md),
            const Text('Find artist / album manually', style: TypeScale.title),
            const SizedBox(height: Space.sm),
            const Text(
              'Auto-enrichment could not resolve this track. Pick a '
              'source below — copy the URL, open it in a browser, '
              'identify the track, then come back here and use '
              '"Edit info" to write the right title/artist/album/year '
              'into the local store. The change survives every sync '
              'until you edit it again.',
              style: TypeScale.caption,
            ),
            const SizedBox(height: Space.md),
            for (final q in queries) ...[
              _SearchRow(source: q.source, url: q.url),
              const Divider(),
            ],
            const SizedBox(height: Space.sm),
            Text(
              'sha: ${track.sha}',
              style: TypeScale.caption.copyWith(color: Tones.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  static List<_SearchQuery> _searchQueries(ManifestTrack t) {
    final title = t.title;
    final artist = t.artist;
    String enc(String s) => Uri.encodeComponent(s);
    return [
      _SearchQuery(
        source: 'MusicBrainz',
        url:
            'https://musicbrainz.org/search?query=${enc("$artist $title")}&type=recording',
      ),
      _SearchQuery(
        source: 'Spotify',
        url: 'https://open.spotify.com/search/${enc("$artist $title")}/tracks',
      ),
      _SearchQuery(
        source: 'Discogs',
        url:
            'https://www.discogs.com/search/?q=${enc("$artist $title")}&type=release',
      ),
      _SearchQuery(
        source: 'DuckDuckGo',
        url: 'https://duckduckgo.com/?q=${enc("$artist $title music")}',
      ),
    ];
  }
}

class _SearchQuery {
  const _SearchQuery({required this.source, required this.url});
  final String source;
  final String url;
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({required this.source, required this.url});
  final String source;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(source, style: TypeScale.title),
                Text(
                  url,
                  style: TypeScale.caption.copyWith(color: Tones.textMuted),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy URL',
            icon: const Icon(Icons.copy_rounded, color: Tones.textMuted),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$source URL copied'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
