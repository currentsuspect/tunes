import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/audio/offline_anchor.dart';

void main() {
  test('going back to a song is allowed once', () {
    final anchor = OfflineAnchor();
    expect(anchor.take('a'), isTrue);
    expect(anchor.take('a'), isFalse);
  });

  test('the replayed song being heard does not open the way back again', () {
    // The loop: back to A, A plays its last seconds, the next song fails again.
    final anchor = OfflineAnchor()..take('a');
    anchor.heard('a');
    expect(anchor.take('a'), isFalse);
  });

  test('hearing a different song opens it again', () {
    final anchor = OfflineAnchor()..take('a');
    anchor.heard('b');
    expect(anchor.take('a'), isTrue);
  });

  test('a move by the listener opens it again', () {
    final anchor = OfflineAnchor()..take('a');
    anchor.clear();
    expect(anchor.take('a'), isTrue);
  });

  test('each song has its own way back', () {
    final anchor = OfflineAnchor()..take('a');
    expect(anchor.take('b'), isTrue);
  });
}
