import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

/// What kind of device this is, in the words the app uses for it.
///
/// A music library "on this phone" is "on this computer" on a computer. The
/// words come from here so no screen has to know which it is on.
/// Whether a window is big enough for the desktop layout: wide and tall. A
/// phone on its side is wide but short, so it keeps the phone layout.
bool isWideWindow(Size size) => size.width >= 900 && size.height >= 560;

class Device {
  static final bool _desktop =
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  /// Lets a test pretend to be a phone or a computer whatever it runs on.
  @visibleForTesting
  static bool? debugDesktop;

  static bool get isDesktop => debugDesktop ?? _desktop;

  /// "phone" or "computer".
  static String get noun => isDesktop ? 'computer' : 'phone';

  /// "this phone" / "this computer".
  static String get thisOne => 'this $noun';

  /// "This phone" / "This computer", for titles.
  static String get titleThis => 'This $noun';
}
