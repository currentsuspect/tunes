import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/search/search_worker.dart';
import 'package:tunes/domain/manifest.dart';

ManifestTrack _t(String c, String title, {String? lyrics}) => ManifestTrack(
  sha: c * 64,
  size: 1,
  codec: 'flac',
  sampleRate: 44100,
  channels: 2,
  bitrate: 1000,
  durationMs: 120000,
  title: title,
  artist: 'Travis Scott',
  album: 'ASTROWORLD',
  year: '2018',
  artSha: null,
  releaseId: 'r1',
  trackNumber: 1,
  discNumber: 1,
  primaryArtist: 'Travis Scott',
  featured: const [],
  lyrics: lyrics,
);

void main() {
  // The real isolate, not the inline seam the widget tests use.
  test('the worker answers from its own isolate, lyrics once ready', () async {
    final tracks = [
      _t('a', 'STARGAZING', lyrics: '[00:01.00] rollin rollin rollin'),
      _t('b', 'SICKO MODE', lyrics: "[00:02.00] don't get hit with the shakes"),
    ];
    final w = await SearchWorker.start(
      tracks: tracks,
      releases: const [],
      artists: const [],
      plays: const {},
    );
    addTearDown(w.dispose);
    expect(w.isInline, isFalse);

    final r = await w.search('stargazing');
    expect(r.songs.map((t) => t.title), ['STARGAZING']);

    // Only what is on this phone.
    final held = await w.search('travis', onlyShas: {'b' * 64});
    expect(held.songs.map((t) => t.title), ['SICKO MODE']);

    // Each answer finds its own question, asked back to back.
    final both = await Future.wait([w.search('sicko'), w.search('star')]);
    expect(both[0].songs.single.title, 'SICKO MODE');
    expect(both[1].songs.single.title, 'STARGAZING');

    if (!w.lyricsReady.value) {
      final ready = Completer<void>();
      w.lyricsReady.addListener(ready.complete);
      await ready.future;
    }
    final words = await w.search("don't get hit with");
    expect(words.lyrics.single.track.title, 'SICKO MODE');
  });
}
