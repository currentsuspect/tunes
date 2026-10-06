import 'dart:async';

import 'package:tunes/core/platform/device.dart';

/// The suite runs on a computer, but the screens it checks are the phone's:
/// say so, unless a test says otherwise.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  Device.debugDesktop = false;
  await testMain();
}
