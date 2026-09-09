import 'package:flutter/material.dart';

/// One panel at a time.
///
/// Album, artist, now-playing and settings are panels: opening one while
/// another is up replaces it rather than stacking, and opening the one that
/// is already up does nothing. Before this, every opener pushed
/// unconditionally, so opening an album twice left two identical routes and
/// Back landed on the twin.
///
/// Panels are recognised by their route name. Anything that is not a panel --
/// the shell itself, sheets, dialogs -- opens normally on top.
Future<void> openTunesPanel(
  BuildContext context,
  String name,
  WidgetBuilder builder,
) {
  final current = ModalRoute.of(context)?.settings.name;
  // Already there. Tapping the same album twice is the common case; pushing
  // a second copy is never what it meant.
  if (current == name) return Future.value();
  final route = MaterialPageRoute<void>(
    settings: RouteSettings(name: name),
    builder: builder,
  );
  if (current != null && current.startsWith('tunes/')) {
    return Navigator.of(context).pushReplacement(route);
  }
  return Navigator.of(context).push(route);
}

/// Route names for the panels above. Compared by equality, so they only have
/// to be unique per panel -- and stable, so the same panel maps to the same
/// name from every opener.
abstract final class TunesPanels {
  static const settings = 'tunes/settings';
  static const nowPlaying = 'tunes/now-playing';
  static String album(String id) => 'tunes/album/$id';
  static String artist(String name) => 'tunes/artist/$name';
}
