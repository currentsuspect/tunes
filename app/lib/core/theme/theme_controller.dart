import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/settings_store.dart';
import 'looks.dart';

/// Which theme to show, and when.
///
/// The listener picks a theme (Room, Noir, Crayon, or Auto) and a brightness
/// (follow the phone, always dark, always light). Auto is Crayon by day and
/// Noir after dark, switching at times the listener can move. Whatever comes out is written to [Looks.current], and the
/// whole tree is marked to rebuild in place: nothing is torn down, so the
/// page, the scroll position and the playing song all stay where they were.
class ThemeController extends ChangeNotifier with WidgetsBindingObserver {
  ThemeController(this.settings) {
    WidgetsBinding.instance.addObserver(this);
    settings.addListener(_apply);
    // Auto moves on its own at the day/night edges; once a minute is plenty.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) => _apply());
    _apply(rebuild: false);
  }

  final SettingsStore settings;
  Timer? _clock;

  /// Auto's day, by default: 06:30 until 18:45 (settings can move both).
  static const dayStarts = 6 * 60 + 30;
  static const nightStarts = 18 * 60 + 45;

  static const auto = 'auto';

  TunesLook get look => Looks.current;

  /// Pure, for tests: the look for a choice, a brightness mode and a moment.
  static TunesLook resolve({
    required String choice,
    required int brightnessMode,
    required Brightness platform,
    required DateTime now,
    int dayFrom = dayStarts,
    int nightFrom = nightStarts,
  }) {
    final m = now.hour * 60 + now.minute;
    // A night that wraps midnight (the usual case) or one that does not.
    final night = nightFrom > dayFrom
        ? m < dayFrom || m >= nightFrom
        : m >= nightFrom && m < dayFrom;
    final spec = choice == auto
        ? (night ? Looks.noir : Looks.crayon)
        : Looks.byId(choice);
    final brightness = switch (brightnessMode) {
      1 => Brightness.dark,
      2 => Brightness.light,
      _ => platform,
    };
    return spec.of(brightness);
  }

  void _apply({bool rebuild = true}) {
    final next = resolve(
      choice: settings.themeChoice,
      brightnessMode: settings.themeBrightness,
      platform: WidgetsBinding.instance.platformDispatcher.platformBrightness,
      now: DateTime.now(),
      dayFrom: settings.autoDayMinutes,
      nightFrom: settings.autoNightMinutes,
    );
    _setSystemBars(next);
    if (identical(next, Looks.current)) return;
    Looks.current = next;
    notifyListeners();
    if (rebuild) _rebuildEverything();
  }

  @override
  void didChangePlatformBrightness() => _apply();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _apply();
  }

  /// Every widget reads its colours through the look, many from inside
  /// const constructors that a normal rebuild skips. Marking every element
  /// dirty redraws them all with the new look while keeping their state.
  static void _rebuildEverything() {
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(mark);
  }

  static void _setSystemBars(TunesLook look) {
    final icons = look.isDark ? Brightness.light : Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: icons,
        statusBarBrightness: look.brightness,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: icons,
        systemNavigationBarContrastEnforced: false,
      ),
    );
  }

  @override
  void dispose() {
    _clock?.cancel();
    settings.removeListener(_apply);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
