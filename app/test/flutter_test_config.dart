import 'dart:async';

import 'package:tunes/core/platform/device.dart';
import 'package:tunes/core/search/search_worker.dart';

/// The suite runs on a computer, but the screens it checks are the phone's:
/// say so, unless a test says otherwise.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  Device.debugDesktop = false;
  // The fake clock never lets a real isolate's answer land.
  SearchWorker.inline = true;
  await testMain();
}
