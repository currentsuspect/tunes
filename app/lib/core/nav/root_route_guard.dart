import 'package:flutter/widgets.dart';

/// Brings the app back if its last route is ever popped.
///
/// The shell is the Navigator's only route. Popping it, which `Navigator.pop`
/// does when called from a panel that is not really a route (deleting a
/// playlist did exactly that), leaves nothing on screen. The engine and the
/// audio service live on regardless, so the music carried on under a blank,
/// stale screen and relaunching the app only resumed the blank one.
///
/// This puts the shell back on the next frame. It is a net under the fix, not
/// a substitute for it: panels leave through the shell's own history.
class RootRouteGuard extends NavigatorObserver {
  RootRouteGuard({required this.restore});

  /// Builds a fresh route for the shell.
  final Route<void> Function() restore;

  bool _empty = false;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) return;
    _empty = true;
    // After the frame, not now: the Navigator is part-way through the pop and
    // cannot take a push yet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = navigator;
      if (_empty && nav != null && nav.mounted) {
        _empty = false;
        nav.push(restore());
      }
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _empty = false;
  }
}
