import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/platform/diag_log.dart';
import 'package:tunes/core/platform/share_log.dart';

// 25 Oct: reading the phone's log took swapping its Tunes for a debug build.
// Settings now hands it to the share sheet; on a computer it is saved instead.
void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('sharelog'));
  tearDown(() async {
    DiagLog.fileForTest = null;
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('the log is saved with the build that wrote it', () async {
    DiagLog.fileForTest = File('${tmp.path}/tunes_diag.log');
    DiagLog.log('radio: pick after Trinity: Telephone');

    final out = Directory('${tmp.path}/out');
    final copy = await shareDiagLog(
      buildNumber: '3071',
      commit: 'abc1234',
      into: out,
    );

    expect(copy, isNotNull);
    expect(copy!.path, contains('tunes-log-3071-'));
    final text = await copy.readAsString();
    expect(text, startsWith('Tunes build 3071, commit abc1234'));
    expect(text, contains('radio: pick after Trinity: Telephone'));
  });

  test('no log yet, nothing to share', () async {
    DiagLog.fileForTest = null;
    expect(
      await shareDiagLog(buildNumber: '1', commit: 'x', into: tmp),
      isNull,
    );
  });
}
