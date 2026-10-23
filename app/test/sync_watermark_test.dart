import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/domain/manifest.dart';
import 'package:tunes/domain/sync_watermark.dart';

DateTime at(int seconds) => DateTime.utc(2026, 10, 22, 12, 0, seconds);

void main() {
  group('the manifest carries its own build time', () {
    test('read off the wire', () {
      final m = TunesManifest.fromJson({
        'generatedAt': '2026-10-22T14:53:27.752Z',
        'tracks': const [],
      });
      expect(m.generatedAt, DateTime.utc(2026, 10, 22, 14, 53, 27, 752));
    });

    test('absent stays absent rather than becoming now', () {
      final m = TunesManifest.fromJson({'tracks': const []});
      expect(m.generatedAt, isNull);
    });
  });

  group('newestAddedAt', () {
    test('finds the newest timestamp', () {
      expect(newestAddedAt([at(10), at(30), at(20)]), at(30));
    });

    test('ignores the absent ones', () {
      expect(newestAddedAt([null, at(30), null]), at(30));
    });

    test('is null when nothing carries one', () {
      expect(newestAddedAt([null, null]), isNull);
      expect(newestAddedAt(const []), isNull);
    });
  });

  group('watermarkAfterApply', () {
    test('is the build time of the manifest it applied', () {
      expect(
        watermarkAfterApply(
          current: at(5),
          generatedAt: at(40),
          addedAts: [at(10), at(30)],
        ),
        at(40),
      );
    });

    test('does not run ahead of what the manifest covered', () {
      // The bug this exists to prevent: the edge served a manifest built at
      // at(40) while the daemon already had three tracks from at(50)+. Taking
      // "now" (at(100)) as the watermark retired those three for good —
      // /changes only names what arrived after the watermark, so they would
      // never be asked about again.
      final watermark = watermarkAfterApply(
        current: null,
        generatedAt: at(40),
        addedAts: [at(10), at(30)],
      );
      expect(watermark, at(40));
      expect(watermark!.isBefore(at(50)), isTrue);
    });

    test('a stale manifest leaves the watermark behind, not at now', () {
      // A copy built hours ago stays the watermark until a fresh one lands:
      // the daemon keeps naming what that copy lacks.
      final watermark = watermarkAfterApply(
        current: at(10),
        generatedAt: at(40),
      );
      expect(watermark, at(40));
    });

    test('falls back to the newest track it carried', () {
      expect(
        watermarkAfterApply(current: at(5), addedAts: [at(10), at(30)]),
        at(30),
      );
    });

    test('keeps the watermark when the manifest carries no timestamps', () {
      expect(
        watermarkAfterApply(current: at(100), addedAts: [null, null]),
        at(100),
      );
    });

    test('keeps the watermark when no manifest was applied', () {
      expect(
        watermarkAfterApply(current: at(100), addedAts: const []),
        at(100),
      );
    });

    test('moves forward when the manifest is current', () {
      expect(
        watermarkAfterApply(
          current: at(10),
          generatedAt: at(60),
          addedAts: [at(40), at(50)],
        ),
        at(60),
      );
    });
  });
}
