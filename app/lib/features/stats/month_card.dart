import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/theme/looks.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/artwork.dart';
import '../../core/ui/generated_artwork.dart';
import '../../core/ui/look_extras.dart';
import '../../domain/month_recap.dart';

const _share = MethodChannel('tunes/share');

/// The card on "Your listening": the month in a line, Open and Share.
class MonthEntry extends StatelessWidget {
  const MonthEntry({
    super.key,
    required this.recap,
    required this.name,
    this.artUrlFor,
  });

  final MonthRecap recap;
  final String? name;
  final String Function(String sha)? artUrlFor;

  @override
  Widget build(BuildContext context) {
    final look = Looks.current;
    final crayon = look.kind == LookKind.crayon;
    final fill = crayon ? look.crayons[4] : Tones.surfaceRaised;
    final ink = crayon ? const Color(0xFF22201C) : Tones.text;
    final art = recap.topSong.artSha;
    return Container(
      margin: const EdgeInsets.only(bottom: Space.lg),
      padding: const EdgeInsets.all(Space.md + 2),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(RadiusTokens.card),
        border: Border.all(
          color: crayon ? Tones.text : Tones.hairline,
          width: crayon ? 2 : 1,
        ),
        boxShadow: crayon
            ? [BoxShadow(color: look.inkShadow, offset: const Offset(4, 4))]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR MONTH IN TUNES',
            style: TypeScale.caption.copyWith(
              color: ink,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            recap.monthName,
            style: TypeScale.heading.copyWith(fontSize: 30, color: ink),
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Transform.rotate(
                angle: crayon ? -0.05 : 0,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Artwork(
                    url: art == null || artUrlFor == null
                        ? null
                        : artUrlFor!(art),
                    artSha: art,
                    size: 64,
                    fallback: GeneratedArtwork(
                      title: recap.topSong.name,
                      artist: recap.topSong.sub ?? '',
                      size: 64,
                      borderRadius: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(
                  '${recap.hours} hours. ${recap.topSong.name} '
                  '${recap.topSong.plays} times. ${recap.topArtist.name} '
                  'was your person.',
                  style: TypeScale.body.copyWith(color: ink, height: 1.3),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(
                child: _Button(
                  label: 'Open',
                  filled: false,
                  ink: ink,
                  onTap: () => MonthCardPage.open(
                    context,
                    recap: recap,
                    name: name,
                    artUrlFor: artUrlFor,
                  ),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: _Button(
                  label: 'Share',
                  filled: true,
                  ink: ink,
                  onTap: () => shareMonthCard(
                    context,
                    recap: recap,
                    name: name,
                    artUrlFor: artUrlFor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({
    required this.label,
    required this.filled,
    required this.ink,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final Color ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final crayon = Looks.current.kind == LookKind.crayon;
    final bg = filled ? (crayon ? ink : Tones.primary) : Colors.transparent;
    final fg = filled
        ? (crayon ? const Color(0xFFFFFBF2) : Tones.onPrimary)
        : ink;
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: crayon ? ink : (filled ? Colors.transparent : Tones.hairline),
          width: crayon ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 46,
          child: Center(
            child: Text(
              label,
              style: TypeScale.title.copyWith(fontSize: 15, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}

/// The card full screen, with Share under it.
class MonthCardPage extends StatelessWidget {
  const MonthCardPage({
    super.key,
    required this.recap,
    required this.name,
    this.artUrlFor,
  });

  final MonthRecap recap;
  final String? name;
  final String Function(String sha)? artUrlFor;

  static Future<void> open(
    BuildContext context, {
    required MonthRecap recap,
    required String? name,
    String Function(String sha)? artUrlFor,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          MonthCardPage(recap: recap, name: name, artUrlFor: artUrlFor),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tones.base,
      appBar: AppBar(
        backgroundColor: Tones.base,
        surfaceTintColor: Colors.transparent,
        title: Text('${recap.monthName} in Tunes', style: TypeScale.title),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(Space.lg),
                  child: FittedBox(
                    child: MonthShareCard(
                      recap: recap,
                      name: name,
                      artUrlFor: artUrlFor,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                0,
                Space.lg,
                Space.lg,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => shareMonthCard(
                    context,
                    recap: recap,
                    name: name,
                    artUrlFor: artUrlFor,
                  ),
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('Share'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: Looks.current.kind == LookKind.crayon
                        ? Tones.text
                        : Tones.primary,
                    foregroundColor: Looks.current.kind == LookKind.crayon
                        ? Tones.base
                        : Tones.onPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The 9:16 card itself, drawn at 360 by 640 and saved at three times that.
///
/// A Crayon card is paper with the cover taped on, in any mode, the way a
/// sticker stays a sticker; the other looks print theirs in their own type
/// and colours.
class MonthShareCard extends StatelessWidget {
  const MonthShareCard({
    super.key,
    required this.recap,
    required this.name,
    this.artUrlFor,
  });

  static const size = Size(360, 640);

  final MonthRecap recap;
  final String? name;
  final String Function(String sha)? artUrlFor;

  @override
  Widget build(BuildContext context) {
    final look = Looks.current;
    final crayon = look.kind == LookKind.crayon;
    const paper = Color(0xFFFFFBF2);
    const inkC = Color(0xFF22201C);
    final ground = crayon ? paper : look.base;
    final ink = crayon ? inkC : look.text;
    final muted = crayon ? const Color(0xFF6E675C) : look.textMuted;
    final art = recap.topSong.artSha;
    final who = (name ?? '').trim();
    final display = TextStyle(
      fontFamily: Faces.display,
      color: ink,
      fontWeight: FontWeight.w700,
      fontVariations: const [FontVariation('wght', 700)],
    );
    final small = TextStyle(
      fontFamily: crayon ? Faces.display : Faces.mono,
      color: ink,
      fontWeight: FontWeight.w700,
      letterSpacing: 2,
      fontSize: 12,
    );
    Widget stat(String big, String label) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: crayon ? Colors.white : look.surfaceRaised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: crayon ? inkC : look.hairline,
            width: crayon ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            FittedBox(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(big, style: display.copyWith(fontSize: 20)),
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontFamily: Faces.body,
                fontSize: 11,
                color: muted,
              ),
            ),
          ],
        ),
      ),
    );
    return SizedBox.fromSize(
      size: size,
      child: Container(
        color: ground,
        child: CustomPaint(
          painter: crayon ? const _PaperDots() : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        [
                          if (who.isNotEmpty) who.toUpperCase(),
                          recap.monthName.toUpperCase(),
                        ].join(' · '),
                        style: small,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text('tunes', style: small.copyWith(letterSpacing: 0)),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  '${recap.hours} hours\nof music.',
                  style: display.copyWith(fontSize: 42, height: 1.0),
                ),
                if (crayon)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SizedBox(
                      width: 190,
                      child: CrayonSquiggle(color: look.crayons[0]),
                    ),
                  ),
                const Spacer(),
                Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Transform.rotate(
                        angle: crayon ? -0.05 : 0,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: crayon
                                ? Border.all(color: inkC, width: 2.5)
                                : null,
                            boxShadow: crayon
                                ? const [
                                    BoxShadow(
                                      color: inkC,
                                      offset: Offset(6, 6),
                                    ),
                                  ]
                                : null,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Artwork(
                              url: art == null || artUrlFor == null
                                  ? null
                                  : artUrlFor!(art),
                              artSha: art,
                              size: 220,
                              fallback: GeneratedArtwork(
                                title: recap.topSong.name,
                                artist: recap.topSong.sub ?? '',
                                size: 220,
                                borderRadius: 10,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (crayon)
                        Positioned(
                          top: -12,
                          left: 70,
                          child: CrayonTape(
                            color: look.crayons[1],
                            angle: 0.07,
                            length: 90,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Column(
                    children: [
                      Text(
                        'ON REPEAT',
                        style: small.copyWith(color: muted, fontSize: 11),
                      ),
                      Text(
                        '${recap.topSong.name} · ${recap.topSong.plays} times',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: display.copyWith(fontSize: 22),
                      ),
                      if (recap.topSong.sub != null)
                        Text(
                          recap.topSong.sub!,
                          style: TextStyle(
                            fontFamily: Faces.body,
                            fontSize: 13,
                            color: ink,
                          ),
                        ),
                    ],
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    stat(recap.topArtist.name, 'your person'),
                    const SizedBox(width: 10),
                    stat('${recap.artists}', 'artists'),
                    const SizedBox(width: 10),
                    stat(recap.peakHourLabel, 'your hour'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PaperDots extends CustomPainter {
  const _PaperDots();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x1F22201C)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    const gap = 14.0;
    canvas.drawPoints(ui.PointMode.points, [
      for (var y = gap / 2; y < size.height; y += gap)
        for (var x = gap / 2; x < size.width; x += gap) Offset(x, y),
    ], p);
  }

  @override
  bool shouldRepaint(_PaperDots old) => false;
}

/// Draws the card off screen at 1080 by 1920 and hands it to the phone's
/// share sheet. On the desktop it is saved to Pictures (or the home folder)
/// and the path is shown.
Future<void> shareMonthCard(
  BuildContext context, {
  required MonthRecap recap,
  required String? name,
  String Function(String sha)? artUrlFor,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final key = GlobalKey();
  final overlay = Overlay.of(context);
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      // Off screen, but laid out and painted so it can be captured.
      left: -10000,
      top: 0,
      child: RepaintBoundary(
        key: key,
        child: MediaQuery(
          data: const MediaQueryData(),
          child: Material(
            type: MaterialType.transparency,
            child: MonthShareCard(
              recap: recap,
              name: name,
              artUrlFor: artUrlFor,
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  try {
    // Two frames: one to lay out, one for the cover image to decode.
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 3);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (png == null) return;
    final file = await _cardFile(recap);
    await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
    if (Platform.isAndroid) {
      await _share.invokeMethod<void>('image', {
        'path': file.path,
        'title': '${recap.monthName} in Tunes',
      });
    } else {
      messenger?.showSnackBar(SnackBar(content: Text('Saved to ${file.path}')));
    }
  } catch (_) {
    messenger?.showSnackBar(
      const SnackBar(content: Text("Couldn't make the card this time")),
    );
  } finally {
    entry.remove();
  }
}

Future<File> _cardFile(MonthRecap r) async {
  final stamp = '${r.month.year}-${r.month.month.toString().padLeft(2, '0')}';
  final Directory dir;
  if (Platform.isAndroid) {
    // The folder the share FileProvider may hand out (res/xml/update_paths).
    dir = Directory('${(await getApplicationSupportDirectory()).path}/share');
  } else {
    final home = Platform.environment['HOME'] ?? '.';
    final pictures = Directory('$home/Pictures');
    dir = pictures.existsSync() ? pictures : Directory(home);
  }
  await dir.create(recursive: true);
  return File('${dir.path}/tunes-$stamp.png');
}
