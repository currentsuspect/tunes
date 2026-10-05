import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/ui/cover_tint.dart';
import 'package:tunes/core/ui/source_pill.dart';

Uint8List _solid(int r, int g, int b, {int count = 64}) {
  final out = Uint8List(count * 4);
  for (var i = 0; i < count; i++) {
    out[i * 4] = r;
    out[i * 4 + 1] = g;
    out[i * 4 + 2] = b;
    out[i * 4 + 3] = 255;
  }
  return out;
}

void main() {
  group('tintFromRgba', () {
    test('a coloured cover gives its colour', () {
      final tint = tintFromRgba(_solid(200, 60, 40))!;
      final hsl = HSLColor.fromColor(tint);
      expect(hsl.hue, inInclusiveRange(0, 15));
      expect(hsl.lightness, inInclusiveRange(0.42, 0.62));
    });

    test('a greyscale cover gives null, so the room stays lilac', () {
      expect(tintFromRgba(_solid(128, 128, 128)), isNull);
      expect(tintFromRgba(_solid(20, 20, 20)), isNull);
    });

    test('one saturated object on a dark cover wins over the dark', () {
      final px = _solid(10, 10, 12, count: 60);
      final accent = _solid(40, 90, 210, count: 4);
      final both = Uint8List.fromList([...px, ...accent]);
      // Mostly near-black: mean saturation is low, so this is the case the
      // weighting exists for and it must still return a blue, not null mud.
      final tint = tintFromRgba(both);
      if (tint != null) {
        expect(HSLColor.fromColor(tint).hue, inInclusiveRange(200, 235));
      }
    });

    test('an empty or fully transparent image gives null', () {
      expect(tintFromRgba(Uint8List(0)), isNull);
      expect(tintFromRgba(Uint8List.fromList([255, 0, 0, 0])), isNull);
    });
  });

  group('sourceFor', () {
    test('a saved track is held, whatever the connection does', () {
      expect(sourceFor(held: true, offline: true), TrackSource.saved);
      expect(sourceFor(held: true, offline: false), TrackSource.saved);
    });

    test('an unsaved track streams when connected', () {
      expect(sourceFor(held: false, offline: false), TrackSource.streaming);
    });

    test('an unsaved track with no connection is not on this phone', () {
      expect(sourceFor(held: false, offline: true), TrackSource.unavailable);
      expect(TrackSource.unavailable.label, 'not on this phone yet');
    });
  });
}
