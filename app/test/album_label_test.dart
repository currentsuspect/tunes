import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/domain/manifest.dart';

ManifestTrack _track({
  String title = 'THAT GUY',
  String artist = 'Tyler, The Creator',
  String? primaryArtist,
  String album = 'CHERRY BOMB',
}) {
  return ManifestTrack(
    sha: 'a',
    size: 0,
    codec: 'flac',
    sampleRate: 44100,
    channels: 2,
    bitrate: 900000,
    durationMs: 1000,
    title: title,
    artist: artist,
    album: album,
    year: null,
    artSha: null,
    releaseId: null,
    trackNumber: null,
    discNumber: null,
    primaryArtist: primaryArtist,
    featured: const [],
  );
}

void main() {
  group('albumOrNull', () {
    test('passes a real album through unchanged', () {
      expect(_track().albumOrNull, 'CHERRY BOMB');
    });

    test('reports no album rather than showing the parser placeholder', () {
      // fromJson fills an absent album with this literal. A screen that
      // prints it is showing the listener our internal default.
      expect(_track(album: 'unknown album').albumOrNull, isNull);
      expect(_track(album: 'Unknown Album').albumOrNull, isNull);
    });

    test('treats a blank or whitespace album as absent', () {
      expect(_track(album: '').albumOrNull, isNull);
      expect(_track(album: '   ').albumOrNull, isNull);
    });

    test('keeps an album that merely matches the title', () {
      // The detail panel states facts; the release really is named this.
      expect(_track(album: 'THAT GUY').albumOrNull, 'THAT GUY');
    });
  });

  group('albumLabel', () {
    test('drops a single whose album repeats the title', () {
      // The regression: Now Playing printed THAT GUY twice in a row.
      expect(_track(album: 'THAT GUY').albumLabel, isNull);
    });

    test('ignores case and surrounding space when comparing', () {
      expect(_track(album: '  that guy ').albumLabel, isNull);
    });

    test('keeps an album that differs from the title', () {
      expect(_track(album: 'CHERRY BOMB').albumLabel, 'CHERRY BOMB');
    });

    test('inherits the placeholder rule', () {
      expect(_track(album: 'unknown album').albumLabel, isNull);
    });
  });

  group('artistAlbumLine', () {
    test('joins the act and the album', () {
      expect(_track().artistAlbumLine, 'Tyler, The Creator — CHERRY BOMB');
    });

    test('shows the act alone when the album would only repeat', () {
      expect(_track(album: 'THAT GUY').artistAlbumLine, 'Tyler, The Creator');
    });

    test('shows the act alone when there is no album', () {
      expect(
        _track(album: 'unknown album').artistAlbumLine,
        'Tyler, The Creator',
      );
    });

    test('never leaks Vorbis multi-value syntax to the listener', () {
      // Two of the four screens built this line from the raw tag, so a
      // collaboration read as "Yeat;Don Toliver".
      final line = _track(
        artist: 'Yeat;Don Toliver',
        primaryArtist: 'Yeat',
        album: 'LYFESTYLE',
      ).artistAlbumLine;
      expect(line, 'Yeat — LYFESTYLE');
      expect(line, isNot(contains(';')));
    });
  });
}
