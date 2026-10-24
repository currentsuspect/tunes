import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/looks.dart';
import '../../core/theme/tokens.dart';

/// The pieces the Roon pass's pages share (song, person; album and artist
/// next): a section heading, a write-up that opens up, credits whose names
/// open their pages, and small tiles.

bool get _crayon => Looks.current.kind == LookKind.crayon;

/// "1:06".
String clock(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// "24 Oct" this year, "24 Oct 2025" before.
String shortDate(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final m = '${d.day} ${months[d.month - 1]}';
  return d.year == DateTime.now().year ? m : '$m ${d.year}';
}

class AboutHeading extends StatelessWidget {
  const AboutHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.xl, bottom: Space.sm),
    child: Text(text, style: TypeScale.display.copyWith(fontSize: 22)),
  );
}

/// A write-up from Genius: a few lines, then all of it. The source is named
/// and can be copied, since a link out of the app is not ours to open.
class ReadMore extends StatefulWidget {
  const ReadMore({super.key, required this.text, required this.url});

  final String text;
  final String url;

  @override
  State<ReadMore> createState() => _ReadMoreState();
}

class _ReadMoreState extends State<ReadMore> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final long = widget.text.length > 280;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          style: TypeScale.body.copyWith(height: 1.5, color: Tones.text),
          maxLines: _open || !long ? null : 4,
          overflow: _open || !long ? null : TextOverflow.ellipsis,
        ),
        Row(
          children: [
            if (long)
              TextButton(
                onPressed: () => setState(() => _open = !_open),
                style: TextButton.styleFrom(
                  foregroundColor: Tones.primary,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 36),
                ),
                child: Text(_open ? 'Less' : 'Read more'),
              ),
            const Spacer(),
            if (widget.url.isNotEmpty)
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.url));
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    const SnackBar(
                      content: Text('Genius link copied'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  foregroundColor: Tones.textMuted,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 36),
                ),
                child: const Text('From Genius'),
              ),
          ],
        ),
      ],
    );
  }
}

/// A name that opens its page.
class NameLink extends StatelessWidget {
  const NameLink({super.key, required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(4),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        name,
        style: TypeScale.title.copyWith(fontSize: 15, color: Tones.primary),
      ),
    ),
  );
}

class CreditsCard extends StatelessWidget {
  const CreditsCard({super.key, required this.rows});

  final List<Widget> rows;

  /// A Material, not a decorated box, so a row that is a ListTile shows
  /// its tap.
  @override
  Widget build(BuildContext context) => Material(
    color: Tones.surfaceRaised,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(
        color: _crayon ? Tones.text : Tones.hairline,
        width: _crayon ? 2 : 1,
      ),
    ),
    child: Column(
      children: [
        for (final (i, r) in rows.indexed) ...[
          if (i > 0) Divider(height: 1, color: Tones.hairline),
          r,
        ],
      ],
    ),
  );
}

/// "Produced by  BNYX, Bangs": each name opens that person's page.
class CreditRow extends StatelessWidget {
  const CreditRow({
    super.key,
    required this.role,
    required this.names,
    required this.onName,
  });

  final String role;
  final List<String> names;

  /// Null: names that are not people (a label) and open nothing.
  final void Function(String name)? onName;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(role, style: TypeScale.caption),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 10,
            children: [
              for (final n in names)
                if (onName case final open?)
                  NameLink(name: n, onTap: () => open(n))
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      n,
                      style: TypeScale.title.copyWith(fontSize: 15),
                    ),
                  ),
            ],
          ),
        ),
      ],
    ),
  );
}

class ConnectionTile extends StatelessWidget {
  const ConnectionTile({
    super.key,
    required this.label,
    required this.title,
    required this.artist,
    required this.held,
    required this.onOpen,
  });

  final String label;
  final String title;
  final String artist;

  /// The library's copy, when it has one: then it plays.
  final Object? held;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final have = held != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Material(
        color: have ? Tones.surface : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: have ? Tones.text : Tones.textMuted,
            width: _crayon ? 2 : 1,
          ),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          onTap: have ? onOpen : null,
          child: Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Tones.badge,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    label.toUpperCase(),
                    style: TypeScale.caption.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TypeScale.title.copyWith(fontSize: 14),
                      ),
                      Text(
                        [
                          if (artist.isNotEmpty) artist,
                          have ? 'in your library' : 'not yet',
                        ].join(' · '),
                        style: TypeScale.caption,
                      ),
                    ],
                  ),
                ),
                if (have) Icon(Icons.play_arrow_rounded, color: Tones.text),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Where in the song its moments fall.
class MomentStrip extends StatelessWidget {
  const MomentStrip({super.key, required this.duration, required this.at});

  final Duration duration;
  final List<Duration> at;

  @override
  Widget build(BuildContext context) => Container(
    height: 40,
    decoration: BoxDecoration(
      color: Tones.surfaceRaised,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Tones.text, width: _crayon ? 2 : 1),
    ),
    child: LayoutBuilder(
      builder: (context, box) => Stack(
        children: [
          for (final a in at)
            Positioned(
              left:
                  (box.maxWidth - 6) *
                  (a.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0),
              top: 6,
              bottom: 6,
              child: Container(
                width: 6,
                decoration: BoxDecoration(
                  color: Tones.primary,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Tones.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _crayon ? Tones.text : Tones.hairline,
          width: _crayon ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TypeScale.title.copyWith(fontSize: 20)),
          ),
          Text(label, style: TypeScale.caption),
        ],
      ),
    ),
  );
}

class VersionTile extends StatelessWidget {
  const VersionTile({super.key, required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.sm),
    child: Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: Tones.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _crayon ? Tones.text : Tones.hairline,
          width: _crayon ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TypeScale.title.copyWith(fontSize: 14)),
          Text(detail, style: TypeScale.caption),
        ],
      ),
    ),
  );
}

/// Songs per year as crayon bars, the years under them (an artist's
/// "Through the years").
class YearBars extends StatelessWidget {
  const YearBars({super.key, required this.counts});

  /// Year → songs, oldest first.
  final Map<int, int> counts;

  @override
  Widget build(BuildContext context) {
    final most = counts.values.fold<int>(1, (a, b) => a > b ? a : b);
    final crayons = Looks.current.crayons;
    final years = counts.keys.toList();
    return Column(
      children: [
        Container(
          height: 96,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Tones.text, width: _crayon ? 2 : 1),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (i, y) in years.indexed)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Tooltip(
                      message: '${counts[y]} in $y',
                      child: Container(
                        height: 8 + 84 * counts[y]! / most,
                        decoration: BoxDecoration(
                          color: crayons[i % crayons.length],
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                          border: _crayon
                              ? Border.all(color: Tones.text, width: 1.5)
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final y in years)
              Expanded(
                child: Text(
                  years.length > 8 ? "'${y % 100}" : '$y',
                  textAlign: TextAlign.center,
                  style: TypeScale.caption.copyWith(fontSize: 11),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
