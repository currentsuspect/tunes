import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/net/update_check.dart';

/// Whether to tell someone their app is out of date.
///
/// The cost of a false positive is real: the banner leads to a ~100 MB
/// download and a system install prompt. The cost of a false negative is that
/// someone stays on an old build, which is what happens today anyway. So this
/// leans towards silence whenever it cannot be sure.
void main() {
  AvailableUpdate update(int build) =>
      AvailableUpdate(build: build, name: 'Build $build', notes: '', size: 0);

  group('shouldOfferUpdate', () {
    test('offers a strictly newer build', () {
      expect(shouldOfferUpdate('10', update(11)), isTrue);
    });

    test('says nothing when up to date', () {
      expect(shouldOfferUpdate('11', update(11)), isFalse);
    });

    test('never offers a downgrade', () {
      // The daemon can hold an older cached release after a re-run.
      expect(shouldOfferUpdate('12', update(11)), isFalse);
    });

    test('says nothing when the daemon has no update', () {
      expect(shouldOfferUpdate('10', null), isFalse);
    });

    test('says nothing on a locally built app', () {
      // BUILD_NUMBER defaults to 'local'. Comparing that to a number would
      // offer an update on every launch, forever, to the one person who
      // definitely does not want it.
      expect(shouldOfferUpdate('local', update(11)), isFalse);
      expect(shouldOfferUpdate('', update(11)), isFalse);
    });

    test('tolerates whitespace around the build number', () {
      expect(shouldOfferUpdate(' 10 ', update(11)), isTrue);
    });
  });

  group('AvailableUpdate.fromJson', () {
    test('reads a well-formed payload', () {
      final u = AvailableUpdate.fromJson({
        'build': 42,
        'name': 'Build 42',
        'notes': 'fix(player): keep the queue',
        'size': 104000000,
      });
      expect(u?.build, 42);
      expect(u?.notes, 'fix(player): keep the queue');
    });

    test('rejects a payload with no usable build', () {
      // Rejected rather than defaulted: a zero would compare as "older than
      // everything" and silently mean "never update".
      expect(AvailableUpdate.fromJson({'build': 0}), isNull);
      expect(AvailableUpdate.fromJson({'build': 'twelve'}), isNull);
      expect(AvailableUpdate.fromJson(const {}), isNull);
    });

    test('falls back to the tag-shaped name when none is given', () {
      expect(AvailableUpdate.fromJson({'build': 7})?.name, 'build-7');
    });

    test('renders a size someone can judge a download by', () {
      expect(
        AvailableUpdate.fromJson({'build': 7, 'size': 104000000})?.readableSize,
        // 104 MB on disk is 99.2 MiB; one decimal below 100 so the number
        // still distinguishes a 99 MB update from a 99.9 MB one.
        '99.2 MB',
      );
      expect(
        AvailableUpdate.fromJson({'build': 7, 'size': 5 * 1024 * 1024})
            ?.readableSize,
        '5.0 MB',
      );
      // Unknown size shows nothing rather than "0 MB".
      expect(AvailableUpdate.fromJson({'build': 7})?.readableSize, '');
    });
  });
}
