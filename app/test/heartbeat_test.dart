import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/data/reachability.dart';

void main() {
  test(
    'a check that never answers does not stop the checks after it',
    () async {
      final r = Reachability();
      var calls = 0;
      final beat = Heartbeat(
        reachability: r,
        pingTimeout: const Duration(milliseconds: 50),
        ping: () {
          calls += 1;
          // The first lookup hangs forever, as one can while the phone moves
          // between networks; the next one answers.
          return calls == 1 ? Completer<bool>().future : Future.value(true);
        },
      );
      await beat.probe();
      await beat.probe();
      expect(calls, 2);
      expect(r.offline, isFalse);
    },
  );
}
