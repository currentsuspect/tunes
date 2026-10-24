import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/platform/notifications.dart';

void main() {
  test('a desktop note says it is from Tunes, with Play, and waits for it', () {
    final args = linuxNoteArgs(
      id: 7,
      title: 'Griddlë is in your library',
      body: 'Yeat',
      tap: 'play:abc',
      actionLabel: 'Play',
      action: 'play:abc',
    );
    expect(args, [
      '--app-name=Tunes',
      '--icon=com.currentsuspect.tunes',
      '--hint=string:desktop-entry:com.currentsuspect.tunes',
      '--replace-id=7',
      '--action=default=Open',
      '--action=act=Play',
      '--wait',
      'Griddlë is in your library',
      'Yeat',
    ]);
  });

  test('a note with nothing to click does not wait', () {
    final args = linuxNoteArgs(id: 1, title: 'Hi');
    expect(args, isNot(contains('--wait')));
    expect(args.last, 'Hi');
  });
}
