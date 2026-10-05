import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/audio/queue_order.dart';

void main() {
  final list = ['a', 'b', 'c', 'd', 'e', 'f'];

  group('shuffleAfter', () {
    test('keeps what was played and what is playing, shuffles the rest', () {
      final out = shuffleAfter(list, 2, Random(1));
      expect(out.sublist(0, 3), ['a', 'b', 'c']);
      expect(out.sublist(3).toSet(), {'d', 'e', 'f'});
      expect(out.length, list.length);
    });

    test('actually reorders the future', () {
      // Across many seeds at least one differs, or it is not shuffling.
      final futures = {
        for (var s = 0; s < 20; s++) shuffleAfter(list, 0, Random(s)).join(),
      };
      expect(futures.length, greaterThan(1));
      expect(futures.contains('abcdef'), isTrue); // and may keep the order
    });

    test('leaves short or finished queues alone', () {
      expect(shuffleAfter(['a', 'b'], 0, Random(1)), ['a', 'b']);
      expect(shuffleAfter(list, 5, Random(1)), list);
      expect(shuffleAfter(list, -1, Random(1)), list);
    });

    test('does not change the list it was given', () {
      final copy = List.of(list);
      shuffleAfter(list, 1, Random(3));
      expect(list, copy);
    });
  });

  group('inOrderAfter', () {
    test('what follows is the next song in the list, in order', () {
      // Shuffled earlier into c, e, a, f, b, d; now on "e" (index 1).
      final playing = ['c', 'e', 'a', 'f', 'b', 'd'];
      final out = inOrderAfter(playing, list, 1);
      expect(out, ['c', 'e', 'f']);
    });

    test('continues from here rather than restarting the list', () {
      final playing = ['d', 'a', 'f', 'b', 'c', 'e'];
      // On "d" at index 0: the list after d is e, f.
      expect(inOrderAfter(playing, list, 0), ['d', 'e', 'f']);
    });

    test('on the last song of the list there is nothing after it', () {
      final playing = ['f', 'a', 'b', 'c', 'd', 'e'];
      expect(inOrderAfter(playing, list, 0), ['f']);
    });

    test('a song that is not in the list has no list to follow', () {
      final playing = ['x', 'y', 'z'];
      expect(inOrderAfter(playing, list, 1), ['x', 'y']);
    });

    test('keeps what was already played', () {
      final playing = ['b', 'a', 'c', 'e', 'd', 'f'];
      expect(inOrderAfter(playing, list, 2), ['b', 'a', 'c', 'd', 'e', 'f']);
    });

    test('out of range returns the queue as it was', () {
      expect(inOrderAfter(list, list, 99), list);
      expect(inOrderAfter(list, list, -1), list);
    });
  });

  test('on then off puts the future back in list order', () {
    final shuffled = shuffleAfter(list, 1, Random(7));
    final restored = inOrderAfter(shuffled, list, 1);
    expect(restored, ['a', 'b', 'c', 'd', 'e', 'f']);
  });

  group('sameFuture', () {
    test('ignores the past, compares what is still to come', () {
      expect(sameFuture(['x', 'b', 'c'], ['y', 'b', 'c'], 0), isTrue);
      expect(sameFuture(['a', 'b', 'c'], ['a', 'c', 'b'], 0), isFalse);
      expect(sameFuture(['a', 'b'], ['a', 'b', 'c'], 0), isFalse);
    });
  });
}
