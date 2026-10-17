import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/domain/eq.dart';

void main() {
  test('the Wan\'er profile becomes the chain checked against mpv', () {
    expect(
      BuiltInEq.wanerRedLionNeutral.toMpvAf(),
      'lavfi=[volume=-4.80dB,'
      'lowshelf=f=97:t=q:w=0.71:g=-6,'
      'equalizer=f=173:t=q:w=1.05:g=-2.60,'
      'equalizer=f=4500:t=q:w=1.52:g=2.50,'
      'equalizer=f=6188:t=q:w=2:g=3.50,'
      'equalizer=f=8645:t=q:w=2.50:g=-2.60]',
    );
  });

  test('reads AutoEQ / squig.link / APO text', () {
    final p = parseEqText(
      '''
Preamp: -4.8 dB
Filter 1: ON LSC Fc 97 Hz Gain -6.0 dB Q 0.71
Filter 2: ON PK Fc 173 Hz Gain -2.6 dB Q 1.05
Filter 3: OFF PK Fc 4500 Hz Gain 2.5 dB Q 1.52
Filter 4: ON HSC Fc 10000 Hz Gain 1.5 dB Q 0.7
Filter 5: ON PK Fc 8645 Hz Gain -2.6 dB
''',
      id: 'x',
      name: 'Aria 2',
    );
    expect(p, isNotNull);
    expect(p!.preamp, -4.8);
    expect(p.filters.map((f) => f.type), [
      EqFilterType.lowShelf,
      EqFilterType.peak,
      EqFilterType.highShelf,
      EqFilterType.peak,
    ]);
    expect(p.filters.last.q, 1.0); // a peak with no Q given
  });

  test('nothing readable is no profile, and bad filters never reach mpv', () {
    expect(parseEqText('hello', id: 'x', name: 'y'), isNull);
    const odd = EqProfile(
      id: 'x',
      name: 'y',
      preamp: 0,
      filters: [
        EqFilter(EqFilterType.peak, 5, 3, 1), // below the audible range
        EqFilter(EqFilterType.peak, 1000, 0, 1), // no gain
        EqFilter(EqFilterType.peak, 1000, 2, 0), // no Q
      ],
    );
    expect(odd.toMpvAf(), '');
  });

  test('a profile survives being saved', () {
    final p = BuiltInEq.wanerRedLionNeutral;
    final back = EqProfile.fromJson(p.toJson())!;
    expect(back.toMpvAf(), p.toMpvAf());
    expect(back.name, p.name);
  });
}
