import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/audio/tune_player.dart';
import 'package:tunes/domain/manifest.dart';
import 'package:tunes/features/desktop/desktop_keys.dart';

class _P extends TunePlayer {
  final calls = <String>[];
  Duration pos = const Duration(seconds: 30);
  @override
  List<ManifestTrack> get queue => const [];
  @override
  int get index => -1;
  @override
  bool get playing => false;
  @override
  Duration get position => pos;
  @override
  Duration get duration => const Duration(minutes: 3);
  @override
  ManifestTrack? get current => null;
  @override
  PlaybackRepeat get repeat => PlaybackRepeat.off;
  @override
  bool get shuffle => false;
  @override
  void playQueue(List<ManifestTrack> t, int i) {}
  @override
  void play() {}
  @override
  void pause() {}
  @override
  void toggle() => calls.add('toggle');
  @override
  void next() => calls.add('next');
  @override
  void previous() => calls.add('previous');
  @override
  void playAt(int i) {}
  @override
  void seek(Duration t) => calls.add('seek${t.inSeconds}');
  @override
  void stop() {}
  @override
  void setRepeat(PlaybackRepeat m) {}
  @override
  void setShuffle(bool on) {}
}

KeyDownEvent _down(LogicalKeyboardKey k) => KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.keyA,
  logicalKey: k,
  timeStamp: Duration.zero,
);

void main() {
  late _P p;
  late List<String> hits;
  KeyEventResult press(
    LogicalKeyboardKey k, {
    bool typing = false,
    bool ctrl = false,
    bool alt = false,
  }) => handleDesktopKey(
    event: _down(k),
    player: p,
    typing: typing,
    ctrl: ctrl,
    alt: alt,
    onLike: () => hits.add('like'),
    onSearch: () => hits.add('search'),
    onBack: () {
      hits.add('back');
      return true;
    },
  );

  setUp(() {
    p = _P();
    hits = [];
  });

  test('space plays and pauses', () {
    expect(press(LogicalKeyboardKey.space), KeyEventResult.handled);
    expect(p.calls, ['toggle']);
  });

  test('space typed into a text box is not a pause', () {
    expect(
      press(LogicalKeyboardKey.space, typing: true),
      KeyEventResult.ignored,
    );
    expect(
      press(LogicalKeyboardKey.keyL, typing: true),
      KeyEventResult.ignored,
    );
    expect(p.calls, isEmpty);
    expect(hits, isEmpty);
  });

  test('media keys work even while typing', () {
    press(LogicalKeyboardKey.mediaPlayPause, typing: true);
    press(LogicalKeyboardKey.mediaTrackNext, typing: true);
    expect(p.calls, ['toggle', 'next']);
  });

  test('arrows seek five seconds and ctrl+arrows skip', () {
    press(LogicalKeyboardKey.arrowRight);
    press(LogicalKeyboardKey.arrowLeft);
    press(LogicalKeyboardKey.arrowRight, ctrl: true);
    press(LogicalKeyboardKey.arrowLeft, ctrl: true);
    expect(p.calls, ['seek35', 'seek25', 'next', 'previous']);
  });

  test('seeking stops at the ends', () {
    p.pos = const Duration(seconds: 2);
    press(LogicalKeyboardKey.arrowLeft);
    p.pos = const Duration(seconds: 178);
    press(LogicalKeyboardKey.arrowRight);
    expect(p.calls, ['seek0', 'seek180']);
  });

  test('L likes, / searches, Esc and alt+left go back', () {
    press(LogicalKeyboardKey.keyL);
    press(LogicalKeyboardKey.slash);
    press(LogicalKeyboardKey.keyF, ctrl: true);
    press(LogicalKeyboardKey.escape);
    press(LogicalKeyboardKey.arrowLeft, alt: true);
    expect(hits, ['like', 'search', 'search', 'back', 'back']);
    expect(p.calls, isEmpty);
  });

  test('keys that mean nothing are left alone', () {
    expect(press(LogicalKeyboardKey.keyQ), KeyEventResult.ignored);
  });
}
