import 'package:flutter/widgets.dart';

import '../../domain/manifest.dart';

/// Opens the Roon pass's Song and Person pages from anywhere (a track's
/// menu, Now Playing, a credit), so no screen has to carry the shell's
/// dependencies to do it. Provided by the shell.
class AboutNav extends InheritedWidget {
  const AboutNav({
    super.key,
    required this.openSong,
    required this.openPerson,
    required super.child,
  });

  final void Function(ManifestTrack track) openSong;
  final void Function(String name) openPerson;

  static AboutNav? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AboutNav>();

  @override
  bool updateShouldNotify(AboutNav old) => false;
}
