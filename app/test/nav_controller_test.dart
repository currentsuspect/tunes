import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/nav/nav_controller.dart';

/// Pane registry vs navigation history, per the nav spec.
///
/// One instance per identity, one history entry per identity. Revisiting an
/// existing destination moves that entry to the top; it never duplicates in
/// either structure.
void main() {
  Widget builder(String label) => Text(label);

  late NavController nav;

  setUp(() {
    nav = NavController();
  });

  void openArtist() =>
      nav.openPanel(TunesPanels.artist('A'), () => builder('artist A'));
  void openAlbum() =>
      nav.openPanel(TunesPanels.album('rel-a'), () => builder('album A'));

  List<String> keys() => [for (final d in nav.history) d.key];

  test('Test 1: Home -> Artist -> Album -> Back = Artist', () {
    openArtist();
    openAlbum();
    expect(nav.back(), isTrue);
    expect(nav.current, const PanelDest('tunes/artist/A'));
  });

  test('Test 2: revisit moves to top, Back walks the trail', () {
    openArtist();
    openAlbum();
    openArtist();
    // [tab, album, artist]: the revisit repositioned, never duplicated.
    expect(keys(), ['tab:0', 'tunes/album/rel-a', 'tunes/artist/A']);
    expect(nav.back(), isTrue);
    expect(nav.current, const PanelDest('tunes/album/rel-a'));
    expect(nav.back(), isTrue);
    expect(nav.current, const TabDest(0));
    expect(nav.back(), isFalse);
  });

  test('Test 3: alternating revisits never duplicate', () {
    openArtist();
    openAlbum();
    openArtist();
    openAlbum();
    // [A, a] -> [a, A] -> [A, a], as identities.
    expect(keys(), ['tab:0', 'tunes/artist/A', 'tunes/album/rel-a']);
    nav.instanceFor(TunesPanels.artist('A'));
    nav.instanceFor(TunesPanels.album('rel-a'));
    expect(nav.registrySize, 2);
  });

  test('opening the top destination is idempotent', () {
    openArtist();
    openArtist();
    expect(keys(), ['tab:0', 'tunes/artist/A']);
    // Every pane type, same rule.
    nav.openPanel(TunesPanels.nowPlaying, () => builder('player'));
    nav.openPanel(TunesPanels.nowPlaying, () => builder('player'));
    expect(keys(), ['tab:0', 'tunes/artist/A', 'tunes/now-playing']);
  });

  test('the player follows the same identity semantics', () {
    openArtist();
    openAlbum();
    nav.openPanel(TunesPanels.nowPlaying, () => builder('player'));
    openArtist();
    expect(keys(), [
      'tab:0',
      'tunes/album/rel-a',
      'tunes/now-playing',
      'tunes/artist/A',
    ]);
    expect(nav.back(), isTrue);
    expect(nav.current, const PanelDest('tunes/now-playing'));
  });

  test('back at the root returns false for the app-level close', () {
    expect(nav.canPop, isFalse);
    expect(nav.back(), isFalse);
    expect(nav.current, const TabDest(0));
  });

  test('tab switches replace rather than trail', () {
    nav.selectTab(2);
    nav.selectTab(3);
    expect(keys(), ['tab:3']);
    expect(nav.current, const TabDest(3));
  });

  test('a tab tapped from inside a page leaves the page for good', () {
    // The tabs are on screen under pages now, so this tap is reachable. Before,
    // it stacked the tab on top of the page, and Back from the new tab walked
    // into a page that had been left on purpose.
    final nav = NavController();
    nav.selectTab(3);
    nav.openPanel('tunes/artist/a', () => const SizedBox());
    nav.openPanel('tunes/album/b', () => const SizedBox());
    expect(nav.history.length, 3);

    nav.selectTab(1);

    expect(nav.history, [const TabDest(1)]);
    expect(nav.back(), isFalse);
  });

  test('a left page is still there to come back to later', () {
    final nav = NavController();
    nav.openPanel('tunes/artist/a', () => const Text('artist'));
    final first = nav.instanceFor('tunes/artist/a');
    nav.selectTab(2);

    nav.openPanel('tunes/artist/a', () => const Text('artist'));
    expect(identical(nav.instanceFor('tunes/artist/a'), first), isTrue);
  });

  test('forgetting unused panes keeps the ones on screen', () {
    nav.openPanel('tunes/artist/a', () => const Text('a1'));
    final onScreen = nav.instanceFor('tunes/artist/a');
    nav.openPanel('tunes/album/b', () => const Text('b1'));
    nav.instanceFor('tunes/album/b');
    nav.back(); // album left, artist is on top again
    expect(nav.registrySize, 2);

    nav.forgetUnused();

    expect(nav.registrySize, 1);
    expect(identical(nav.instanceFor('tunes/artist/a'), onScreen), isTrue);
  });

  test(
    'a forgotten pane is rebuilt from the builder it is opened with next',
    () {
      // Opened offline, built from a cut-down library; the connection returns.
      nav.openPanel('tunes/album/b', () => const Text('built offline'));
      expect((nav.instanceFor('tunes/album/b') as Text).data, 'built offline');
      nav.selectTab(0);
      nav.forgetUnused();

      nav.openPanel('tunes/album/b', () => const Text('built online'));
      expect((nav.instanceFor('tunes/album/b') as Text).data, 'built online');
    },
  );

  test('popped panes are retained, not destroyed', () {
    openArtist();
    nav.instanceFor(TunesPanels.artist('A'));
    expect(nav.registrySize, 1);
    nav.back();
    expect(nav.registrySize, 1);
    expect(nav.current, const TabDest(0));
  });
}
