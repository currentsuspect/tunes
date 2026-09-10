import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/domain/manifest.dart';
import 'package:tunes/main.dart';

/// The primed grant set covers everything the library can show.
///
/// Regression file: artist photos went unprimed while every cover around them
/// worked, because the path loop knew tracks and releases but not artists. A
/// missing category here is invisible (a placeholder) rather than loud, so it
/// is pinned by name.
void main() {
  ManifestTrack track() => ManifestTrack(
    sha: 's' * 64,
    size: 1000,
    codec: 'flac',
    sampleRate: 44100,
    channels: 2,
    bitrate: 950000,
    durationMs: 125000,
    title: 'Song',
    artist: 'Vax',
    album: 'Album',
    year: null,
    artSha: 't' * 64,
    releaseId: 'rel-1',
    trackNumber: null,
    discNumber: null,
  );

  ManifestRelease release() => ManifestRelease(
    id: 'rel-1',
    title: 'Album',
    artist: 'Vax',
    year: '2026',
    artSha: 'r' * 64,
    type: 'album',
    totalTracks: 1,
    trackShas: ['s' * 64],
  );

  TunesManifest manifest() => TunesManifest(
    tracks: [track()],
    releases: [release()],
    artists: [ManifestArtist(name: 'Vax', artSha: 'a' * 64)],
  );

  test('covers track art, release art and artist photos', () {
    final paths = grantPathsFor(manifest(), (_) => null);
    expect(paths, contains('/art/${'t' * 64}'));
    expect(paths, contains('/art/${'r' * 64}'));
    expect(paths, contains('/art/${'a' * 64}'));
  });

  test('streams anything not on disk', () {
    final paths = grantPathsFor(manifest(), (_) => null);
    expect(paths, contains('/track/${'s' * 64}'));
  });

  test('a download needs no stream grant but keeps its art', () {
    final paths = grantPathsFor(manifest(), (sha) => '/disk/$sha');
    expect(paths, isNot(contains('/track/${'s' * 64}')));
    expect(paths, contains('/art/${'t' * 64}'));
    expect(paths, contains('/art/${'a' * 64}'));
  });
}
