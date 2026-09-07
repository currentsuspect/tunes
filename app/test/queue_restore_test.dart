import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/audio/queue_restore.dart';
import 'package:tunes/domain/manifest.dart';

ManifestTrack _t(String sha, String title) => ManifestTrack(
  sha: sha,
  size: 1000,
  codec: 'flac',
  sampleRate: 44100,
  channels: 2,
  bitrate: 900000,
  durationMs: 100000,
  title: title,
  artist: 'Artist',
  album: 'Album',
  year: null,
  artSha: null,
  releaseId: null,
  trackNumber: null,
  discNumber: null,
);

/// Where a restored queue resumes.
///
/// The queue was written on every play and never read back, so closing the app
/// lost the listener's place — and with no current track there is no
/// mini-player, so the app returned looking like nothing had been played.
///
/// `QueueStore.load` already resolves the shas and drops tracks the library no
/// longer has. What is left, and what this covers, is deciding which of the
/// survivors to sit on.
void main() {
  final one = _t('a' * 64, 'One');
  final two = _t('b' * 64, 'Two');
  final three = _t('c' * 64, 'Three');

  test('lands on the track that was playing', () {
    expect(restoreIndexFor([one, two, three], 'b' * 64), 1);
  });

  test('resolves by identity, so a dropped track does not shift it', () {
    // 'One' is gone from the library, so load() returned two entries and
    // 'Three' now sits at index 1 rather than 2. A remembered number would
    // have come back pointing at 'Two'.
    expect(restoreIndexFor([two, three], 'c' * 64), 1);
  });

  test('falls back to the start when the track is gone', () {
    // The queue is still worth restoring; the position in it is not knowable.
    expect(restoreIndexFor([one, two], 'z' * 64), 0);
  });

  test('falls back to the start when nothing was remembered', () {
    expect(restoreIndexFor([one], null), 0);
  });

  test('an empty queue has no position', () {
    expect(restoreIndexFor(const [], 'a' * 64), 0);
  });

  group('resumePosition', () {
    const song = Duration(minutes: 4);

    test('resumes where playback stopped', () {
      expect(
        resumePosition(const Duration(minutes: 2), song),
        const Duration(minutes: 2),
      );
    });

    test('ignores a position barely into the track', () {
      // Being dropped eight seconds in reads as a glitch, not a courtesy.
      expect(resumePosition(const Duration(seconds: 8), song), Duration.zero);
    });

    test('starts over when the track was effectively finished', () {
      // Resuming into the last few seconds of something already heard is
      // worse than starting it again.
      expect(
        resumePosition(const Duration(minutes: 3, seconds: 50), song),
        Duration.zero,
      );
    });

    test('starts over when the stored position is past the end', () {
      // The file was re-encoded, or the sha now points at something shorter.
      expect(resumePosition(const Duration(minutes: 9), song), Duration.zero);
    });

    test('applies no end rule when the duration is unknown', () {
      // Guessing an end would mean refusing to resume long podcasts and live
      // sets, which are exactly the things worth resuming.
      expect(
        resumePosition(const Duration(minutes: 40), null),
        const Duration(minutes: 40),
      );
    });

    test('zero and negative stay at the start', () {
      expect(resumePosition(Duration.zero, song), Duration.zero);
      expect(resumePosition(const Duration(seconds: -5), song), Duration.zero);
    });
  });
}
