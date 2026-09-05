import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/domain/manifest.dart';

ManifestTrack _track({
  required String sha,
  required String artist,
  String? primaryArtist,
  List<String> featured = const [],
  String album = 'A',
}) {
  return ManifestTrack(
    sha: sha,
    size: 0,
    codec: 'flac',
    sampleRate: 44100,
    channels: 2,
    bitrate: 900000,
    durationMs: 1000,
    title: 't',
    artist: artist,
    album: album,
    year: null,
    artSha: null,
    releaseId: null,
    trackNumber: null,
    discNumber: null,
    primaryArtist: primaryArtist,
    featured: featured,
  );
}

void main() {
  group('artistKey', () {
    test('groups a collaboration under its lead act', () {
      // The regression: the library grouped by the raw credit line, so one
      // album showed up under nine different "artists".
      final keys = <String>{
        _track(sha: 'a', artist: 'Yeat', primaryArtist: 'Yeat').artistKey,
        _track(
          sha: 'b',
          artist: 'Yeat;Don Toliver',
          primaryArtist: 'Yeat',
        ).artistKey,
        _track(
          sha: 'c',
          artist: 'Yeat, Kodak Black',
          primaryArtist: 'Yeat',
        ).artistKey,
      };
      expect(keys, {'Yeat'});
    });

    test('falls back to the raw credit when the daemon sent no act', () {
      // Rows synced before the daemon started sending primaryArtist.
      expect(_track(sha: 'a', artist: 'Yeat').artistKey, 'Yeat');
      expect(
        _track(sha: 'b', artist: 'Yeat', primaryArtist: '').artistKey,
        'Yeat',
      );
    });
  });

  group('releasesFor', () {
    ManifestRelease release(String id, String artist) => ManifestRelease(
      id: id,
      title: id,
      artist: artist,
      year: null,
      artSha: null,
      type: null,
      totalTracks: null,
      trackShas: const [],
    );

    test('finds a joint album from any member of its cast', () {
      // CONGLOMERATE is credited to its whole cast, so tapping any one of them
      // has to reach it.
      final m = TunesManifest(
        tracks: const [],
        releases: [
          release('CONGLOMERATE', 'Fimiguerrero, Lancey Foux, Len'),
          release('LYFESTYLE', 'Yeat'),
        ],
      );
      expect(m.releasesFor('Len').map((r) => r.id), ['CONGLOMERATE']);
      expect(m.releasesFor('Lancey Foux').map((r) => r.id), ['CONGLOMERATE']);
      expect(m.releasesFor('Yeat').map((r) => r.id), ['LYFESTYLE']);
    });

    test('does not match an artist who is merely a substring', () {
      final m = TunesManifest(
        tracks: const [],
        releases: [release('X', 'Lenny Kravitz')],
      );
      expect(m.releasesFor('Len'), isEmpty);
    });
  });

  group('fromJson', () {
    test('reads the act and guests the daemon sends', () {
      final t = ManifestTrack.fromJson({
        'sha': 'a',
        'title': 'NEW HIGH',
        'artist': 'Yeat;Don Toliver',
        'album': 'LYFESTYLE',
        'primaryArtist': 'Yeat',
        'featured': ['Don Toliver'],
      });
      expect(t.primaryArtist, 'Yeat');
      expect(t.featured, ['Don Toliver']);
      expect(t.artistKey, 'Yeat');
      // Display is untouched.
      expect(t.artist, 'Yeat;Don Toliver');
    });

    test('tolerates a daemon that has not been updated yet', () {
      final t = ManifestTrack.fromJson({
        'sha': 'a',
        'title': 't',
        'artist': 'Yeat',
        'album': 'A',
      });
      expect(t.primaryArtist, isNull);
      expect(t.featured, isEmpty);
      expect(t.artistKey, 'Yeat');
    });
  });

  group('artistDisplay', () {
    test('shows the act alone, never the raw tag separators', () {
      // ";" and "/" are Vorbis multi-value syntax. A listener should never
      // see "Yeat;Don Toliver" or "Don Toliver/ HVN/" in a list row.
      expect(
        _track(
          sha: 'a',
          artist: 'Yeat;Don Toliver',
          primaryArtist: 'Yeat',
          featured: const ['Don Toliver'],
        ).artistDisplay,
        'Yeat',
      );
      expect(
        _track(
          sha: 'b',
          artist: 'Don Toliver/ HVN/',
          primaryArtist: 'Don Toliver',
          featured: const ['HVN'],
        ).artistDisplay,
        'Don Toliver',
      );
    });

    test('is unchanged for a solo credit', () {
      expect(
        _track(sha: 'a', artist: 'Yeat', primaryArtist: 'Yeat').artistDisplay,
        'Yeat',
      );
    });

    test('falls back to the raw credit when no act was sent', () {
      expect(_track(sha: 'a', artist: 'Yeat').artistDisplay, 'Yeat');
    });

    test('leaves the raw credit intact for search to match on', () {
      // Typing a guest's name must still find the track.
      final t = _track(
        sha: 'a',
        artist: 'Ken Carson, Young Thug',
        primaryArtist: 'Ken Carson',
        featured: const ['Young Thug'],
      );
      expect(t.artist, 'Ken Carson, Young Thug');
      expect(t.artist.toLowerCase().contains('young thug'), isTrue);
    });
  });
}
