import 'package:flutter/material.dart';

import '../../core/data/play_history.dart';
import '../../core/nav/nav_controller.dart';
import '../../core/ui/pressable.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/artwork.dart';
import '../../core/ui/generated_artwork.dart';
import '../../domain/listening_stats.dart';
import '../../domain/manifest.dart';

/// Where the names on "Your listening" lead, handed down from the app shell.
class ListeningLinks {
  const ListeningLinks({this.onArtist, this.onAlbum, this.onSong});

  final void Function(String artist)? onArtist;
  final void Function(Ranked album)? onAlbum;
  final void Function(Ranked song)? onSong;
}

/// "Your listening": how much, when, and what, over a range you pick.
///
/// Numbers first, as tiles, because the headline is a number; then two bar
/// charts (over the range, and over the day); then the top lists. One colour
/// for every bar -- there is only ever one series -- and words in text
/// colours, never the bar colour.
class ListeningPage extends StatefulWidget {
  const ListeningPage({
    super.key,
    required this.history,
    required this.library,
    this.artUrlFor,
    this.onArtist,
    this.onAlbum,
    this.onSong,
  });

  final PlayHistory history;
  final Map<String, ManifestTrack> library;
  final String Function(String sha)? artUrlFor;

  /// Where a name in the top lists goes: the artist's page, the album's
  /// page, the song itself. Without one the row is just a row.
  final void Function(String artist)? onArtist;
  final void Function(Ranked album)? onAlbum;
  final void Function(Ranked song)? onSong;

  @override
  State<ListeningPage> createState() => _ListeningPageState();
}

class _ListeningPageState extends State<ListeningPage> {
  StatsRange _range = StatsRange.week;
  List<ListenEvent>? _events;

  @override
  void initState() {
    super.initState();
    widget.history.listenEvents().then((e) {
      if (mounted) setState(() => _events = e);
    });
  }

  @override
  Widget build(BuildContext context) {
    final events = _events;
    final stats = events == null
        ? null
        : ListeningStats.compute(
            events: events,
            library: widget.library,
            range: _range,
            now: DateTime.now(),
          );
    return Scaffold(
      backgroundColor: Tones.base,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.sm,
            Space.lg,
            Space.xl,
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: () {
                  // Opened as a panel from Settings, or pushed on its own.
                  final nav = NavScope.maybeOf(context);
                  if (nav != null && nav.canPop) {
                    nav.back();
                  } else {
                    Navigator.of(context).maybePop();
                  }
                },
                tooltip: 'Back',
                padding: EdgeInsets.zero,
                icon: Icon(Icons.arrow_back_rounded, color: Tones.textMuted),
              ),
            ),
            Text(
              'Your listening',
              style: TypeScale.display.copyWith(fontSize: 34),
            ),
            const SizedBox(height: Space.md),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final r in StatsRange.values) ...[
                    ChoiceChip(
                      label: Text(r.label),
                      selected: r == _range,
                      onSelected: (_) => setState(() => _range = r),
                      showCheckmark: false,
                      selectedColor: Tones.surfaceRaised,
                      backgroundColor: Colors.transparent,
                      side: BorderSide(
                        color: r == _range ? Tones.primary : Tones.hairline,
                      ),
                      labelStyle: TypeScale.caption.copyWith(
                        fontSize: 13,
                        color: r == _range ? Tones.text : Tones.textMuted,
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                  ],
                ],
              ),
            ),
            const SizedBox(height: Space.lg),
            if (stats == null)
              const Padding(
                padding: EdgeInsets.all(Space.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (stats.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xl),
                child: Text(
                  'Nothing played in this stretch yet. Play something and '
                  'it starts counting.',
                  style: TypeScale.note.copyWith(color: Tones.textMuted),
                ),
              )
            else
              ..._body(stats),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(ListeningStats s) {
    final perDay = _range.days != null && _range.days! <= 30;
    final peak = s.peakHour;
    return [
      _Tiles(
        tiles: [
          ('Listened', _hours(s.listened), null),
          ('Plays', '${s.plays}', null),
          (
            'Artists',
            '${s.artists}',
            s.newArtists > 0 ? '${s.newArtists} new' : null,
          ),
          (
            'Streak',
            '${s.streakDays} ${s.streakDays == 1 ? 'day' : 'days'}',
            null,
          ),
        ],
      ),
      const SizedBox(height: Space.xl),
      _Heading(perDay ? 'Minutes a day' : 'Minutes a month'),
      const SizedBox(height: Space.sm),
      _Bars(
        values: s.buckets,
        labels: s.bucketLabels,
        unit: 'min',
        height: 140,
      ),
      const SizedBox(height: Space.xl),
      const _Heading('When you listen'),
      if (peak != null)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            'Mostly around ${_hourLabel(peak, long: true)}',
            style: TypeScale.note.copyWith(
              fontSize: 15,
              color: Tones.textMuted,
            ),
          ),
        ),
      const SizedBox(height: Space.sm),
      _Bars(
        values: s.byHour,
        labels: [for (var h = 0; h < 24; h++) _hourLabel(h)],
        unit: 'min',
        height: 100,
        everyNthLabel: 6,
      ),
      if (s.topArtists.isNotEmpty) ...[
        const SizedBox(height: Space.xl),
        const _Heading('Top artists'),
        _TopList(
          items: s.topArtists,
          onTap: widget.onArtist == null
              ? null
              : (r) => widget.onArtist!(r.name),
        ),
      ],
      if (s.topSongs.isNotEmpty) ...[
        const SizedBox(height: Space.xl),
        const _Heading('Top songs'),
        _TopList(
          items: s.topSongs,
          artUrlFor: widget.artUrlFor,
          onTap: widget.onSong,
        ),
      ],
      if (s.topAlbums.isNotEmpty) ...[
        const SizedBox(height: Space.xl),
        const _Heading('Top albums'),
        _TopList(
          items: s.topAlbums,
          artUrlFor: widget.artUrlFor,
          onTap: widget.onAlbum,
        ),
      ],
      const SizedBox(height: Space.xl),
      const _Heading('Also'),
      const SizedBox(height: Space.sm),
      _Fact('Skipped', '${(s.skipRate * 100).round()}% of songs you started'),
      _Fact('Library heard', '${(s.heardShare * 100).round()}% of it, ever'),
    ];
  }

  static String _hours(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h == 0) return '${d.inMinutes} min';
    return m == 0 ? '$h h' : '$h h $m m';
  }

  static String _hourLabel(int h, {bool long = false}) {
    final am = h < 12;
    final twelve = h % 12 == 0 ? 12 : h % 12;
    if (long) {
      if (h == 0) return 'midnight';
      if (h == 12) return 'noon';
      return '$twelve ${am ? 'am' : 'pm'}';
    }
    return '$twelve${am ? 'a' : 'p'}';
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TypeScale.title.copyWith(fontSize: 17));
}

/// The headline numbers, two to a row.
class _Tiles extends StatelessWidget {
  const _Tiles({required this.tiles});

  final List<(String label, String value, String? note)> tiles;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: Space.sm));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _tile(tiles[i])),
              const SizedBox(width: Space.sm),
              Expanded(
                child: i + 1 < tiles.length
                    ? _tile(tiles[i + 1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }

  Widget _tile((String, String, String?) t) {
    final (label, value, note) = t;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: Tones.surface,
        borderRadius: BorderRadius.circular(RadiusTokens.card),
        border: Border.all(color: Tones.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TypeScale.mono.copyWith(fontSize: 10),
          ),
          const SizedBox(height: Space.xs),
          Text(
            value,
            style: TypeScale.display.copyWith(fontSize: 26),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (note != null)
            Text(note, style: TypeScale.caption.copyWith(color: Tones.held)),
        ],
      ),
    );
  }
}

/// One series of bars over a baseline. Tap (or drag across) a bar to read
/// its value; the bar under the finger is drawn full strength and the rest
/// step back.
class _Bars extends StatefulWidget {
  const _Bars({
    required this.values,
    required this.labels,
    required this.unit,
    required this.height,
    this.everyNthLabel,
  });

  final List<int> values;
  final List<String> labels;
  final String unit;
  final double height;

  /// Label every nth bar; by default first, middle and last.
  final int? everyNthLabel;

  @override
  State<_Bars> createState() => _BarsState();
}

class _BarsState extends State<_Bars> {
  int? _picked;

  void _pick(Offset local, double width) {
    final n = widget.values.length;
    if (n == 0 || width <= 0) return;
    final i = (local.dx / width * n).floor().clamp(0, n - 1);
    if (i != _picked) setState(() => _picked = i);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.values.length;
    final picked = _picked;
    final maxV = widget.values.fold<int>(0, (a, b) => a > b ? a : b);
    final readout = picked == null
        ? 'Most: $maxV ${widget.unit}'
        : '${widget.labels[picked]} · ${widget.values[picked]} ${widget.unit}';
    bool labelled(int i) {
      final nth = widget.everyNthLabel;
      if (nth != null) return i % nth == 0;
      return i == 0 || i == n - 1 || (n > 6 && i == n ~/ 2);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(readout, style: TypeScale.mono),
        const SizedBox(height: Space.sm),
        LayoutBuilder(
          builder: (context, c) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _pick(d.localPosition, c.maxWidth),
            onHorizontalDragUpdate: (d) => _pick(d.localPosition, c.maxWidth),
            onHorizontalDragEnd: (_) {},
            child: Semantics(
              label: [
                for (var i = 0; i < n; i++)
                  '${widget.labels[i]} ${widget.values[i]} ${widget.unit}',
              ].join(', '),
              child: CustomPaint(
                size: Size(c.maxWidth, widget.height),
                painter: _BarPainter(
                  values: widget.values,
                  max: maxV,
                  picked: picked,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.xs),
        LayoutBuilder(
          builder: (context, c) {
            final w = n == 0 ? 0.0 : c.maxWidth / n;
            return SizedBox(
              height: 16,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < n; i++)
                    if (labelled(i))
                      Positioned(
                        left: (i == n - 1 && n > 1)
                            ? null
                            : (i * w).clamp(0, c.maxWidth - 40),
                        right: (i == n - 1 && n > 1) ? 0 : null,
                        child: Text(
                          widget.labels[i],
                          style: TypeScale.mono.copyWith(fontSize: 10),
                        ),
                      ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({required this.values, required this.max, required this.picked});

  final List<int> values;
  final int max;
  final int? picked;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0) return;
    // Recessive baseline; no grid.
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()
        ..color = Tones.hairline
        ..strokeWidth = 1,
    );
    final slot = size.width / n;
    // A 2px gap between bars, never thinner than a hairline bar.
    final gap = slot > 6 ? 2.0 : 1.0;
    final w = (slot - gap).clamp(1.0, 28.0);
    for (var i = 0; i < n; i++) {
      final v = values[i];
      if (v <= 0 || max <= 0) continue;
      final h = (v / max * (size.height - 2)).clamp(2.0, size.height);
      final x = i * slot + (slot - w) / 2;
      final r = Radius.circular(w >= 8 ? 4 : w / 2);
      final dim = picked != null && picked != i;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x, size.height - h, w, h),
          topLeft: r,
          topRight: r,
        ),
        Paint()..color = Tones.primary.withValues(alpha: dim ? 0.35 : 0.9),
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.values != values || old.max != max || old.picked != picked;
}

/// A ranked list, with a thin bar for each item's share of the leader.
class _TopList extends StatelessWidget {
  const _TopList({required this.items, this.artUrlFor, this.onTap});

  final List<Ranked> items;
  final String Function(String sha)? artUrlFor;
  final void Function(Ranked)? onTap;

  @override
  Widget build(BuildContext context) {
    final lead = items.first.plays;
    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          PressRow(
            onTap: onTap == null ? null : () => onTap!(items[i]),
            borderRadius: BorderRadius.circular(RadiusTokens.control),
            child: Padding(
              padding: const EdgeInsets.only(top: Space.sm + 2, bottom: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text('${i + 1}', style: TypeScale.mono),
                  ),
                  if (artUrlFor != null) ...[
                    Artwork(
                      url: items[i].artSha == null
                          ? null
                          : artUrlFor!(items[i].artSha!),
                      artSha: items[i].artSha,
                      size: 40,
                      borderRadius: 8,
                      fallback: GeneratedArtwork(
                        title: items[i].name,
                        artist: items[i].sub ?? '',
                        size: 40,
                        borderRadius: 8,
                      ),
                    ),
                    const SizedBox(width: Space.md),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          items[i].name,
                          style: TypeScale.title.copyWith(fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (items[i].sub != null)
                          Text(
                            items[i].sub!,
                            style: TypeScale.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        const SizedBox(height: Space.xs),
                        LayoutBuilder(
                          builder: (context, c) => Container(
                            height: 3,
                            width: c.maxWidth * items[i].plays / lead,
                            decoration: BoxDecoration(
                              color: Tones.primary.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Text(
                    '${items[i].plays} ${items[i].plays == 1 ? 'play' : 'plays'}',
                    style: TypeScale.mono,
                  ),
                  if (onTap != null)
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: Tones.textMuted,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.xs),
    child: Row(
      children: [
        Expanded(child: Text(label, style: TypeScale.body)),
        Text(value, style: TypeScale.body.copyWith(color: Tones.text)),
      ],
    ),
  );
}
