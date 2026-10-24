import 'package:flutter/material.dart';

import '../../core/data/gets.dart';
import '../../core/theme/looks.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/artwork.dart';
import '../../core/ui/generated_artwork.dart';
import '../../core/ui/initials.dart';
import '../../domain/discography.dart';
import '../../domain/manifest.dart';

/// The artist page's v2 sections (approved 24 Oct): the band at the top,
/// the discography by kind, and the collaborators.

bool get _crayon => Looks.current.kind == LookKind.crayon;

/// The name on a dark band, the photo beside it, one line of facts, and
/// Play and Shuffle.
class ArtistBand extends StatelessWidget {
  const ArtistBand({
    super.key,
    required this.artist,
    required this.photoUrl,
    required this.photoSha,
    required this.tint,
    required this.facts,
    required this.onBack,
    required this.onPlay,
    required this.onShuffle,
  });

  final String artist;
  final String? photoUrl;
  final String? photoSha;
  final Color tint;
  final String facts;
  final VoidCallback onBack;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  @override
  Widget build(BuildContext context) {
    final band = _crayon
        ? const Color(0xFF2B2438)
        : Color.lerp(tint, Colors.black, 0.62)!;
    const paper = Color(0xFFFFFBF2);
    return Container(
      color: band,
      padding: EdgeInsets.fromLTRB(
        Space.lg,
        MediaQuery.paddingOf(context).top + Space.xs,
        Space.lg,
        Space.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: 'Back',
            padding: EdgeInsets.zero,
            alignment: Alignment.centerLeft,
            icon: const Icon(Icons.arrow_back_rounded, color: paper),
          ),
          const SizedBox(height: Space.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      artist,
                      style: TypeScale.display.copyWith(
                        fontSize: 44,
                        height: 1,
                        color: paper,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: Space.sm),
                    Text(
                      facts,
                      style: TypeScale.caption.copyWith(
                        color: paper.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.md),
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: paper, width: 3),
                ),
                child: Artwork(
                  url: photoUrl,
                  artSha: photoSha,
                  size: 104,
                  borderRadius: 52,
                  fallback: InitialsAvatar(name: artist, size: 104),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.sm,
            children: [
              FilledButton.icon(
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Play'),
                style: FilledButton.styleFrom(
                  backgroundColor: Tones.primary,
                  foregroundColor: Colors.white,
                  side: _crayon
                      ? const BorderSide(color: Color(0xFF22201C), width: 2)
                      : null,
                ),
              ),
              OutlinedButton.icon(
                onPressed: onShuffle,
                icon: const Icon(Icons.shuffle_rounded, size: 18),
                label: const Text('Shuffle'),
                style: OutlinedButton.styleFrom(
                  backgroundColor: paper,
                  foregroundColor: const Color(0xFF22201C),
                  side: const BorderSide(color: Color(0xFF22201C), width: 2),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One record in the discography: held (a release in the library) or not
/// yet (a group from the catalogue).
class DiscoItem {
  const DiscoItem({
    required this.title,
    required this.kind,
    required this.year,
    this.release,
    this.group,
    this.editions = const [],
  });

  /// Other editions of it held ("ADL (Deluxe)" beside ADL): one record.
  final List<ManifestRelease> editions;

  final String title;

  /// album, ep or single.
  final String kind;
  final String? year;
  final ManifestRelease? release;
  final DiscographyGroup? group;

  bool get held => release != null;
}

/// album, ep or single, from a release's or a catalogue group's type.
String discoKind(String? type) {
  final t = (type ?? '').toLowerCase();
  if (t.contains('single')) return 'single';
  if (t == 'ep' || t.contains(' ep')) return 'ep';
  return 'album';
}

/// A record's title without a trailing edition note: "ADL (Deluxe)" is ADL.
String editionBase(String title) => title
    .replaceAll(RegExp(r'\s*[(\[][^)\]]*[)\]]\s*$'), '')
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '');

/// The records held and not, by kind, newest first. A catalogue group
/// held already (through any edition) is left out: the held release is it.
List<DiscoItem> discoItems(
  List<ManifestRelease> held,
  List<DiscographyGroup> missing,
) {
  // Editions of one record are one tile: the one with most of it held
  // (the plainer title on a tie), the others named under it.
  final byBase = <String, List<ManifestRelease>>{};
  for (final r in held) {
    byBase.putIfAbsent(editionBase(r.title), () => []).add(r);
  }
  final items = [
    for (final group in byBase.values)
      () {
        final sorted = [...group]
          ..sort((a, b) {
            final byHeld = b.trackShas.length - a.trackShas.length;
            return byHeld != 0 ? byHeld : a.title.length - b.title.length;
          });
        final r = sorted.first;
        return DiscoItem(
          title: r.title,
          kind: discoKind(r.type),
          year: r.year,
          release: r,
          editions: sorted.skip(1).toList(),
        );
      }(),
    for (final g in missing)
      if (!g.owned)
        DiscoItem(
          title: g.title,
          kind: discoKind(g.type),
          year: g.year,
          group: g,
        ),
  ];
  int year(DiscoItem i) =>
      int.tryParse((i.year ?? '').padRight(4).substring(0, 4)) ?? 0;
  items.sort((a, b) => year(b) - year(a));
  return items;
}

/// Albums · EPs · Singles, as a grid of covers: held in colour with how much
/// of it, not yet dashed with Get it.
class Discography extends StatefulWidget {
  const Discography({
    super.key,
    required this.artist,
    required this.items,
    required this.artUrlFor,
    required this.onOpen,
  });

  final String artist;
  final List<DiscoItem> items;
  final String Function(String sha) artUrlFor;
  final void Function(ManifestRelease release) onOpen;

  @override
  State<Discography> createState() => _DiscographyState();
}

class _DiscographyState extends State<Discography> {
  String? _kind;
  bool _all = false;
  final Set<String> _asked = {};

  static const _labels = {'album': 'Albums', 'ep': 'EPs', 'single': 'Singles'};

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final i in widget.items) {
      counts[i.kind] = (counts[i.kind] ?? 0) + 1;
    }
    final kinds = [
      for (final k in const ['album', 'ep', 'single'])
        if ((counts[k] ?? 0) > 0) k,
    ];
    if (kinds.isEmpty) return const SizedBox.shrink();
    final kind = kinds.contains(_kind) ? _kind! : kinds.first;
    final shown = widget.items.where((i) => i.kind == kind).toList();
    final visible = _all ? shown : shown.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final k in kinds)
              ChoiceChip(
                label: Text('${_labels[k]} · ${counts[k]}'),
                selected: k == kind,
                showCheckmark: false,
                selectedColor: Tones.text,
                labelStyle: TypeScale.caption.copyWith(
                  color: k == kind ? Tones.base : Tones.text,
                  fontWeight: FontWeight.w700,
                ),
                onSelected: (_) => setState(() {
                  _kind = k;
                  _all = false;
                }),
              ),
          ],
        ),
        const SizedBox(height: Space.xs),
        Text(
          'Newest first. In colour: in your library. Dashed: not yet.',
          style: TypeScale.caption,
        ),
        const SizedBox(height: Space.md),
        LayoutBuilder(
          builder: (context, box) {
            final columns = (box.maxWidth / 180).floor().clamp(2, 6);
            const gap = 14.0;
            final w = (box.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: Space.md,
              children: [
                for (final i in visible)
                  SizedBox(width: w, child: _tile(context, i, w)),
              ],
            );
          },
        ),
        if (shown.length > 6)
          TextButton(
            onPressed: () => setState(() => _all = !_all),
            child: Text(
              _all
                  ? 'Show fewer'
                  : 'All ${shown.length} ${_labels[kind]!.toLowerCase()}',
            ),
          ),
      ],
    );
  }

  /// "Deluxe" from "ADL (Deluxe)".
  static String? _note(String title) =>
      RegExp(r'[(\[]([^)\]]*)[)\]]\s*$').firstMatch(title)?.group(1);

  Widget _tile(BuildContext context, DiscoItem i, double size) {
    final r = i.release;
    final sub = [?i.year?.padRight(4).substring(0, 4).trim()];
    if (r != null) {
      final total = r.totalTracks;
      final have = r.trackShas.length;
      final whole = total != null && have >= total;
      final badge = total == null
          ? '$have'
          : whole
          ? 'all $total'
          : '$have / $total';
      return InkWell(
        onTap: () => widget.onOpen(r),
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Artwork(
                  url: r.artSha == null ? null : widget.artUrlFor(r.artSha!),
                  artSha: r.artSha,
                  size: size,
                  borderRadius: 14,
                  fallback: GeneratedArtwork(
                    title: r.title,
                    artist: widget.artist,
                    size: size,
                    borderRadius: 14,
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: whole ? Tones.held : Tones.base,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Tones.text, width: 1.5),
                    ),
                    child: Text(
                      badge,
                      style: TypeScale.caption.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: whole ? Colors.white : Tones.text,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              r.title,
              style: TypeScale.title.copyWith(fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              [
                ...sub,
                for (final e in i.editions) 'also ${_note(e.title) ?? e.title}',
              ].join(' · '),
              style: TypeScale.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }
    final gets = GetsScope.maybeOf(context);
    final asked = _asked.contains(i.title);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomPaint(
          painter: _Dashed(Tones.textMuted),
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: gets == null
                  ? Text('not yet', style: TypeScale.caption)
                  : OutlinedButton(
                      onPressed: asked
                          ? null
                          : () async {
                              setState(() => _asked.add(i.title));
                              final messenger = ScaffoldMessenger.maybeOf(
                                context,
                              );
                              final n = await gets.completeAlbum(
                                widget.artist,
                                i.title,
                              );
                              messenger?.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    n > 0
                                        ? 'Getting $n songs of ${i.title}'
                                        : "Couldn't find ${i.title} to get",
                                  ),
                                ),
                              );
                            },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Tones.primary,
                        side: BorderSide(color: Tones.primary, width: 2),
                      ),
                      child: Text(asked ? 'Asked' : 'Get it'),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          i.title,
          style: TypeScale.title.copyWith(fontSize: 14, color: Tones.textMuted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text([...sub, 'not yet'].join(' · '), style: TypeScale.caption),
      ],
    );
  }
}

/// A dashed, rounded outline: a record not yet in the library.
class _Dashed extends CustomPainter {
  _Dashed(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(14),
        ).deflate(1.5),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 12) {
        canvas.drawPath(m.extractPath(d, d + 7), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_Dashed old) => old.color != color;
}

/// An artist shared songs with: a card with their photo and how many.
class CollabCard extends StatelessWidget {
  const CollabCard({
    super.key,
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
  Widget build(BuildContext context) => Material(
    color: Tones.surfaceRaised,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(
        color: _crayon ? Tones.text : Tones.hairline,
        width: _crayon ? 2 : 1,
      ),
    ),
    child: InkWell(
      customBorder: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Artwork(
              url: photoUrl,
              artSha: photoSha,
              size: 44,
              borderRadius: 22,
              fallback: InitialsAvatar(name: name, size: 44),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TypeScale.title.copyWith(fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '$songs ${songs == 1 ? 'song' : 'songs'}',
                    style: TypeScale.caption,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A small heading over part of a section ("ARTISTS · …").
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.md, bottom: Space.sm),
    child: Text(text.toUpperCase(), style: TypeScale.mono),
  );
}
