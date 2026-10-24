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

/// Whether the app wears its computer frame (sidebar, play bar across the
/// bottom). On a computer from 600 wide, so a window tiled to half a laptop
/// screen is still a computer app, with a slim sidebar ([compactSidebar]),
/// not the phone's tab bar; elsewhere, a wide window as before.
bool usesDesktopShell(Size size) => Device.isDesktop
    ? size.width >= 600 && size.height >= 400
    : isWideWindow(size);

/// The sidebar as icons only, between 600 and 900 wide.
bool compactSidebar(Size size) => size.width < 900;

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
