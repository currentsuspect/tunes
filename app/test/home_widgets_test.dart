import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/features/home_widgets/home_widgets.dart';

import 'widget_test.dart' show FakeTunePlayer;

Duration ms(int n) => Duration(milliseconds: n);

void main() {
  const timed =
      '[tunesbeat:drop=67660]\n'
      "[01:05.16] Bitch, don't get hit with the b- (ah)\n"
      "[01:07.28] Oh, yeah, you're goin' stupid\n"
      "[01:08.93] Oh, it's as good as it look";

  test('the lyrics widget shows the line being sung and those either side', () {
    final w = lyricWindow(timed, ms(67500));
    expect(w.kind, 'timed');
    expect(w.prev, "Bitch, don't get hit with the b- (ah)");
    expect(w.current, "Oh, yeah, you're goin' stupid");
    expect(w.next, "Oh, it's as good as it look");
  });

  test('before the first line, the first line is what comes', () {
    final w = lyricWindow(timed, ms(1000));
    expect(w.current, '');
    expect(w.next, "Bitch, don't get hit with the b- (ah)");
  });

  test(
    'plain lyrics show their opening, section labels skipped; none is none',
    () {
      final w = lyricWindow("[Intro]\nBitch, I'm the goat\nHuh", ms(1000));
      expect(w.kind, 'plain');
      expect(w.current, "Bitch, I'm the goat");
      expect(lyricWindow(null, ms(0)).kind, 'none');
      expect(lyricWindow('   ', ms(0)).kind, 'none');
    },
  );

  test('with nothing playing the report says so', () {
    final r = widgetReport(FakeTunePlayer());
    expect(r['hasTrack'], false);
    expect(r['title'], '');
    expect(r['lyricsKind'], 'none');
  });
}
