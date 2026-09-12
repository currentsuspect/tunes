import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/data/art_store.dart';
import 'package:tunes/core/net/tunes_client.dart';
import 'package:tunes/core/ui/artwork.dart';

/// A valid 1x1 PNG. Decodes without assets, HTTP, or plugins.
const _png = [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, //
  0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, //
  0, 0, 0, 11, 73, 68, 65, 84, 120, 156, 99, 100, 96, 0, 0, 0, //
  6, 0, 2, 48, 129, 208, 47, 0, 0, 0, 0, 73, 69, 78, 68, 174, //
  66, 96, 130,
];

/// All filesystem work happens in setUp: widget-test bodies run under a fake
/// clock where awaiting real IO wedges, so by the time a body starts every
/// byte is already on disk.
void main() {
  const sha = 'abc';
  late Directory tmp;
  late ArtStore store;
  late ArtStore emptyStore;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('artwork');
    store = ArtStore(Directory('${tmp.path}/art'), client: _PngClient());
    await store.fetch(sha);
    emptyStore = ArtStore(Directory('${tmp.path}/empty'));
    await emptyStore.load();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  testWidgets('a cached cover renders from disk with no network URL', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ArtScope(
          store: store,
          child: const Artwork(
            url: null,
            artSha: sha,
            size: 48,
            fallback: Text('fallback'),
          ),
        ),
      ),
    );
    await tester.pump();
    // The Image widget itself proves the file branch: with no local copy
    // and no URL this sleeve renders the fallback alone, with no Image.
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('without a cached file the sleeve falls back offline', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ArtScope(
          store: emptyStore,
          child: const Artwork(
            url: null,
            artSha: 'missing',
            size: 48,
            fallback: Text('fallback'),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('fallback'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}

class _PngClient extends TunesClient {
  _PngClient() : super('http://test');

  @override
  Future<void> downloadArt(String sha, String path) async {
    await File(path).parent.create(recursive: true);
    await File(path).writeAsBytes(_png);
  }
}
