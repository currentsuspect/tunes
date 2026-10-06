import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/lyrics/voices.dart';

void main() {
  test('unlabelled lyrics all sit on the left', () {
    final v = LyricVoices.resolve(['one', 'two']);
    expect(v.map((e) => e.side), [LyricSide.left, LyricSide.left]);
  });

  test('v1 / v2 labels switch sides and are stripped', () {
    final v = LyricVoices.resolve([
      'v1: hello',
      'still me',
      'v2: hi there',
      'and me',
    ]);
    expect(v.map((e) => e.side), [
      LyricSide.left,
      LyricSide.left,
      LyricSide.right,
      LyricSide.right,
    ]);
    expect(v[0].text, 'hello');
    expect(v[2].text, 'hi there');
  });

  test('v2 on its own is the right-hand voice', () {
    final v = LyricVoices.resolve(['hello', 'v2: reply', 'carry on']);
    expect(v.map((e) => e.side), [
      LyricSide.left,
      LyricSide.right,
      LyricSide.right,
    ]);
  });

  test('the first voice heard is left, whatever it is called', () {
    final v = LyricVoices.resolve(['F: a', 'M: b', 'F: c']);
    expect(v.map((e) => e.side), [
      LyricSide.left,
      LyricSide.right,
      LyricSide.left,
    ]);
  });

  test('a track artist can label a line, by first name too', () {
    final v = LyricVoices.resolve(
      ['Kendrick: yo', 'SZA: oh', 'Kendrick: again'],
      artists: ['Kendrick Lamar', 'SZA'],
    );
    expect(v.map((e) => e.side), [
      LyricSide.left,
      LyricSide.right,
      LyricSide.left,
    ]);
    expect(v[0].text, 'yo');
  });

  test('a stranger before a colon is just lyrics', () {
    final v = LyricVoices.resolve(
      ['Note: this is a word'],
      artists: ['Kendrick Lamar'],
    );
    expect(v.single.text, 'Note: this is a word');
    expect(v.single.side, LyricSide.left);
  });

  test('both is centred and does not change who carries on', () {
    final v = LyricVoices.resolve(['v1: a', 'v2: b', 'D: together', 'next']);
    expect(v[2].side, LyricSide.center);
    expect(v[3].side, LyricSide.right);
  });

  test('a bracketed line is a backing vocal on the right and does not take the verse', () {
    final v = LyricVoices.resolve(['lead line', '(echo)', 'lead again']);
    expect(v[1].side, LyricSide.right);
    expect(v[1].backing, isTrue);
    expect(v[2].side, LyricSide.left);
    expect(v[2].backing, isFalse);
  });

  test('withVoice swaps, adds and removes the label', () {
    expect(LyricVoices.withVoice('hello', 2), 'v2: hello');
    expect(LyricVoices.withVoice('v1: hello', 2), 'v2: hello');
    expect(LyricVoices.withVoice('v2: hello', null), 'hello');
    expect(LyricVoices.withVoice('Kendrick: hello', 2), 'v2: Kendrick: hello');
  });
}
