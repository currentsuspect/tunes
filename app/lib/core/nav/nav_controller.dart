import 'package:flutter/widgets.dart';

/// One destination in navigation history.
///
/// A destination is an instruction to *activate* a pane, never to create
/// one. Pane creation belongs exclusively to [NavController] through the
/// registry; history entries only name identities.
@immutable
abstract class NavDest {
  const NavDest();

  /// Registry key. Tab roots use `tab:<index>`; panels use the
  /// [TunesPanels] names (`artist:<name>`, `album:<id>`, ...).
  String get key;
}

/// One of the bottom-navigation roots.
@immutable
class TabDest extends NavDest {
  const TabDest(this.index);

  final int index;

  @override
  String get key => 'tab:$index';

  @override
  bool operator ==(Object other) => other is TabDest && other.index == index;

  @override
  int get hashCode => index.hashCode;
}

/// A panel destination: artist, album, now-playing, settings, playlist.
@immutable
class PanelDest extends NavDest {
  const PanelDest(this.id);

  final String id;

  @override
  String get key => id;

  @override
  bool operator ==(Object other) => other is PanelDest && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Route names for the panels. Compared by equality, so they only have to be
/// unique per panel -- and stable, so the same panel maps to the same name
/// from every opener.
abstract final class TunesPanels {
  static const settings = 'tunes/settings';
  static const nowPlaying = 'tunes/now-playing';
  static const liked = 'tunes/liked';
  static const listening = 'tunes/listening';
  static String album(String id) => 'tunes/album/$id';
  static String artist(String name) => 'tunes/artist/$name';
  static String playlist(int id) => 'tunes/playlist/$id';

  /// A mix the app built. Keyed by what is in it as well as what it is called,
  /// because the same mix is a different list next week and a retained panel
  /// would otherwise keep showing last week's.
  static String mix(String id) => 'tunes/mix/$id';
}

/// One pane per identity; one history entry per identity.
///
/// The registry maps an identity to its single live instance. History is a
/// plain list of destination identities in which each identity occurs at
/// most once. Opening resolves through the registry (create on first use)
/// and moves any existing entry to the top; back pops history and
/// re-activates whatever the new top names. So `Artist -> Album -> Artist
/// -> Back` lands on the Album pane without ever building a second Artist
/// pane, and the trail underneath stays intact.
class NavController extends ChangeNotifier {
  NavController();

  final List<NavDest> _history = [const TabDest(0)];
  final Map<String, Widget Function()> _builders = {};
  final Map<String, Widget> _instances = {};

  List<NavDest> get history => List.unmodifiable(_history);
  NavDest get current => _history.last;
  bool get canPop => _history.length > 1;

  /// How many live pane instances the registry holds. Test seam: repeated
  /// navigation must not grow this past the distinct identities visited.
  int get registrySize => _instances.length;

  /// Opens a panel: resolve (never duplicate) then move to top.
  ///
  /// A request for the destination already on top is a no-op. A request for
  /// an identity deeper in history removes that entry and appends it again:
  /// a revisit is a navigation event that repositions, never a second
  /// instance and never a second entry.
  void openPanel(String id, Widget Function() builder) {
    _builders[id] = builder;
    if (current.key == id) return;
    _history.removeWhere((d) => d is PanelDest && d.id == id);
    _history.add(PanelDest(id));
    notifyListeners();
  }

  /// Lets go of every pane that is not in the history.
  ///
  /// Panes are kept for the session so going back to one is instant, and each was
  /// built from whatever the library looked like when it opened. When that
  /// changes under them, as it does when the connection comes or goes (offline
  /// the library is only what is downloaded), a kept pane would show the old
  /// picture. Dropping them means the next visit builds a fresh one.
  void forgetUnused() {
    final live = {
      for (final d in _history)
        if (d is PanelDest) d.id,
    };
    _instances.removeWhere((id, _) => !live.contains(id));
  }

  /// Switches the tab root. Replaces rather than pushes: tabs are places,
  /// not a trail -- Back from a tab must not walk other tabs.
  ///
  /// From inside a page (an artist, an album, a playlist) the tabs are still
  /// on screen, so a tap on another tab lands here with panels above it. Those
  /// are dropped: leaving them in history made Back from the new tab walk into
  /// a page that had been left on purpose. The registry still holds their
  /// instances, so opening one again re-activates it.
  void selectTab(int index) {
    final top = _history.last;
    if (top is TabDest && top.index == index) return;
    if (top is TabDest) {
      _history[_history.length - 1] = TabDest(index);
    } else {
      _history
        ..clear()
        ..add(TabDest(index));
    }
    notifyListeners();
  }

  /// Walks one step back through history. Returns false at the root, where
  /// the shell performs the app-level close instead.
  ///
  /// History removal never destroys the pane: the registry retains the
  /// instance, so returning later re-activates it without reconstruction.
  bool back() {
    if (_history.length <= 1) return false;
    _history.removeLast();
    notifyListeners();
    return true;
  }

  /// The live instance for an identity, creating it on first activation.
  /// Only the shell calls this, for the history top. Instances are retained
  /// for the session once built: leaving history does not destroy the pane.
  Widget instanceFor(String id) {
    return _instances.putIfAbsent(id, () {
      final build = _builders[id];
      assert(build != null, 'no builder registered for panel $id');
      return build!();
    });
  }
}

/// Makes the [NavController] reachable from panels without threading it
/// through every constructor. Published by the shell above its content, so
/// pushed sheets and dialogs (which live on the root Navigator) do not see
/// it -- only panel content does.
class NavScope extends InheritedNotifier<NavController> {
  const NavScope({
    super.key,
    required NavController controller,
    required super.child,
  }) : super(notifier: controller);

  static NavController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<NavScope>();
    assert(scope != null, 'NavScope.of() called outside the app shell');
    return scope!.notifier!;
  }

  static NavController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<NavScope>()?.notifier;
  }
}
