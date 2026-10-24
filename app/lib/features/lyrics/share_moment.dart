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
import '../../domain/manifest.dart';
import '../stats/month_card.dart' show PaperDots;

const _share = MethodChannel('tunes/share');

/// Cuts a moment of a song on the box: [card] is the PNG to show over it.
typedef MomentClipper = Future<Uint8List?> Function(
  String sha,
  Duration from,
  Duration to, {
  Uint8List? card,
});

/// A lyric line and the moment it is sung, shared as a short video: the
/// words on a card, the song under them, cut from the line's first word to
/// its last. Word timing is what makes the cut exact without trimming.
Future<void> shareMoment(
  BuildContext context, {
  required ManifestTrack track,
  required String words,
  required Duration from,
  required Duration to,
  required MomentClipper clip,
  String Function(String sha)? artUrlFor,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.showSnackBar(
    const SnackBar(
      content: Text('Cutting your moment…'),
      duration: Duration(seconds: 30),
    ),
  );
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
            child: MomentCard(track: track, words: words, artUrlFor: artUrlFor),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  // Removed as soon as the card is captured, not after the cut: the cut can
  // take seconds and the card has done its job. `entry.mounted` stays true
  // until the next frame, so it cannot say whether that already happened.
  var removed = false;
  void removeCard() {
    if (removed) return;
    removed = true;
    entry.remove();
  }

  try {
    // Two frames: one to lay out, one for the cover image to decode.
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) throw StateError('no card');
    final image = await boundary.toImage(pixelRatio: 3);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    removeCard();
    final video = await clip(
      track.sha,
      from,
      to,
      card: png?.buffer.asUint8List(),
    );
    messenger?.hideCurrentSnackBar();
    if (video == null) {
      messenger?.showSnackBar(
        const SnackBar(content: Text("Couldn't cut that moment this time")),
      );
      return;
    }
    final file = await _momentFile(track, from);
    await file.writeAsBytes(video, flush: true);
    if (Platform.isAndroid) {
      await _share.invokeMethod<void>('file', {
        'path': file.path,
        'mime': 'video/mp4',
        'title': 'Share this moment',
        'text': '“$words” — ${track.artist}, ${track.title}',
      });
    } else {
      messenger?.showSnackBar(SnackBar(content: Text('Saved to ${file.path}')));
    }
  } catch (_) {
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      const SnackBar(content: Text("Couldn't cut that moment this time")),
    );
  } finally {
    removeCard();
  }
}

Future<File> _momentFile(ManifestTrack t, Duration from) async {
  final Directory dir;
  if (Platform.isAndroid) {
    // The folder the share FileProvider may hand out (res/xml/update_paths).
    dir = Directory('${(await getApplicationSupportDirectory()).path}/share');
  } else {
    final home = Platform.environment['HOME'] ?? '.';
    final videos = Directory('$home/Videos');
    dir = videos.existsSync() ? videos : Directory(home);
  }
  await dir.create(recursive: true);
  // One moment kept at a time on the phone: the share sheet has its copy.
  if (Platform.isAndroid) {
    for (final old in dir.listSync().whereType<File>()) {
      if (old.path.contains('tunes-moment-')) old.deleteSync();
    }
  }
  return File(
    '${dir.path}/tunes-moment-${t.sha.substring(0, 8)}-${from.inMilliseconds}.mp4',
  );
}

/// The picture under a shared moment: the words, large, and whose they are.
/// Portrait, sized for a status or a story.
class MomentCard extends StatelessWidget {
  const MomentCard({
    super.key,
    required this.track,
    required this.words,
    this.artUrlFor,
  });

  static const size = Size(360, 640);

  final ManifestTrack track;
  final String words;
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
    final art = track.artSha;
    final small = TextStyle(
      fontFamily: crayon ? Faces.display : Faces.mono,
      color: muted,
      fontWeight: FontWeight.w700,
      letterSpacing: 2,
      fontSize: 11,
    );
    // Long lines get a smaller size, so a verse still fits the card.
    final quoteSize = words.length > 90
        ? 26.0
        : words.length > 50
        ? 31.0
        : 37.0;
    // Its own text defaults, so the card draws the same wherever it is put.
    return DefaultTextStyle(
      style: const TextStyle(decoration: TextDecoration.none),
      child: SizedBox.fromSize(
        size: size,
        child: Container(
          color: ground,
          child: CustomPaint(
            painter: crayon ? const PaperDots() : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 30, 28, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('NOW PLAYING', style: small)),
                      Text('tunes', style: small.copyWith(letterSpacing: 0)),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    '“',
                    style: TextStyle(
                      fontFamily: Faces.display,
                      fontSize: 72,
                      height: 0.6,
                      color: crayon ? look.crayons[0] : look.primary,
                    ),
                  ),
                  Text(
                    words,
                    style: TextStyle(
                      fontFamily: Faces.display,
                      color: ink,
                      fontSize: quoteSize,
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                      fontVariations: const [FontVariation('wght', 700)],
                    ),
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (crayon)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SizedBox(
                        width: 170,
                        child: CrayonSquiggle(color: look.crayons[0]),
                      ),
                    ),
                  const Spacer(),
                  Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: crayon
                              ? Border.all(color: inkC, width: 2)
                              : null,
                          boxShadow: crayon
                              ? const [
                                  BoxShadow(color: inkC, offset: Offset(4, 4)),
                                ]
                              : null,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Artwork(
                            url: art == null || artUrlFor == null
                                ? null
                                : artUrlFor!(art),
                            artSha: art,
                            size: 64,
                            fallback: GeneratedArtwork(
                              title: track.album,
                              artist: track.artist,
                              size: 64,
                              borderRadius: 8,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: Faces.display,
                                color: ink,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: Faces.body,
                                color: muted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
