import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/audio/source_plan.dart';

const _remote = 'https://tunes.aestra.studio/t/a?sig=1';
const _remote2 = 'https://tunes.aestra.studio/t/b?sig=1';
const _local = '/data/user/0/stream-cache/a';
const _local2 = '/data/user/0/stream-cache/b';

void main() {
  test('local paths and server addresses are told apart', () {
    expect(isLocalUri(_local), isTrue);
    expect(isLocalUri(_remote), isFalse);
    expect(isLocalUri('http://100.64.0.1:8080/t/a'), isFalse);
  });

  test('a song cached since its queue opened is reopened only when allowed', () {
    final allowed = planSources(
      opened: [_remote],
      resolved: [_local],
      index: 0,
      touchCurrent: true,
    );
    expect(allowed.reopenCurrent, isTrue);

    // Online and streaming fine: leave it alone, the next play reads the copy.
    final playingFine = planSources(
      opened: [_remote],
      resolved: [_local],
      index: 0,
      touchCurrent: false,
    );
    expect(playingFine.isNone, isTrue);
  });

  test('a song still to come that reached the phone rebuilds the tail', () {
    final plan = planSources(
      opened: [_remote, _remote2],
      resolved: [_remote, _local2],
      index: 0,
      touchCurrent: true,
    );
    expect(plan.reopenCurrent, isFalse);
    expect(plan.rebuildTail, isTrue);
  });

  test('songs already played do not rebuild anything', () {
    final plan = planSources(
      opened: [_remote, _remote2],
      resolved: [_local, _remote2],
      index: 1,
      touchCurrent: true,
    );
    expect(plan.isNone, isTrue);
  });

  test('nothing changed, nothing to do', () {
    final plan = planSources(
      opened: [_local, _remote2],
      resolved: [_local, _remote2],
      index: 0,
      touchCurrent: true,
    );
    expect(plan.isNone, isTrue);
  });

  test('a queue edited since it opened is left to the next open', () {
    final plan = planSources(
      opened: [_remote],
      resolved: [_local, _local2],
      index: 0,
      touchCurrent: true,
    );
    expect(plan.isNone, isTrue);
  });

  test('offline, the next song on the phone is found past streamed ones', () {
    expect(nextLocalAfter([_local, _remote, _remote2, _local2], 0), 3);
    expect(nextLocalAfter([_local, _remote], 0), isNull);
  });
}
