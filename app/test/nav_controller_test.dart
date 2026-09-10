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

  test('popped panes are retained, not destroyed', () {
    openArtist();
    nav.instanceFor(TunesPanels.artist('A'));
    expect(nav.registrySize, 1);
    nav.back();
    expect(nav.registrySize, 1);
    expect(nav.current, const TabDest(0));
  });
}
