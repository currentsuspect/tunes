import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'diag_log.dart';

const _share = MethodChannel('tunes/share');

/// Hands the diagnostics log to the phone's share sheet, so it can be sent
/// anywhere (Telegram, Drive, a chat) and read off the phone.
///
/// A release build keeps the log where nothing else can read it, adb included:
/// on 25 Oct the only way to see why the radio stopped was to swap the phone's
/// Tunes for a debug build. This is the cheap way.
///
/// On a computer it is saved to the home folder instead ([into], for tests).
/// Returns the copy, or null when there is no log to share.
Future<File?> shareDiagLog({
  required String buildNumber,
  required String commit,
  Directory? into,
}) async {
  final path = DiagLog.path;
  if (path == null) return null;
  final log = File(path);
  if (!await log.exists()) return null;

  final now = DateTime.now();
  final stamp =
      '${now.year}${_two(now.month)}${_two(now.day)}-'
      '${_two(now.hour)}${_two(now.minute)}';
  final Directory dir;
  if (into != null) {
    dir = into;
  } else if (Platform.isAndroid) {
    // The folder the share FileProvider may hand out (res/xml/update_paths).
    dir = Directory('${(await getApplicationSupportDirectory()).path}/share');
  } else {
    dir = Directory(Platform.environment['HOME'] ?? '.');
  }
  await dir.create(recursive: true);
  // One log kept at a time on the phone: the share sheet has its copy.
  if (Platform.isAndroid) {
    for (final old in dir.listSync().whereType<File>()) {
      if (old.path.contains('tunes-log-')) old.deleteSync();
    }
  }
  final copy = File('${dir.path}/tunes-log-$buildNumber-$stamp.txt');
  // Which build wrote it, so a log read later is read against the right code.
  await copy.writeAsString(
    'Tunes build $buildNumber, commit $commit, shared ${now.toIso8601String()}\n'
    '${Platform.operatingSystem} ${Platform.operatingSystemVersion}\n\n',
    flush: true,
  );
  await copy.writeAsBytes(await log.readAsBytes(), mode: FileMode.append);

  if (Platform.isAndroid) {
    await _share.invokeMethod<void>('file', {
      'path': copy.path,
      'mime': 'text/plain',
      'title': 'Share the Tunes log',
    });
  }
  return copy;
}

String _two(int n) => n.toString().padLeft(2, '0');
