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

  test('Android gets only the filters its libmpv has', () {
    // media_kit_libs_android_audio: ffmpeg with every filter off except
    // `equalizer` (17 Oct: a lowshelf made every song skip).
    final c = BuiltInEq.wanerRedLionNeutral.mpvChain(full: false);
    final filters = RegExp(r'(?<=\[|,)([a-z]+)=')
        .allMatches(c.af)
        .map((m) => m.group(1))
        .toSet();
    expect(filters, {'equalizer'});
    // The preamp comes back for mpv's volume, the shelf's flat part folded in.
    expect(c.preampDb, closeTo(-4.73, 0.01));
    // The low shelf became two broad peaks low down.
    expect(c.af, contains('equalizer=f=12.03:t=q:w=0.25:g=-6.01'));
    expect(c.af, contains('equalizer=f=57.52:t=q:w=0.84:g=-2.90'));
  });

  test('desktop keeps the exact chain, preamp in it', () {
    final c = BuiltInEq.wanerRedLionNeutral.mpvChain(full: true);
    expect(c.preampDb, 0);
    expect(c.af, startsWith('lavfi=[volume=-4.80dB,lowshelf='));
  });

  test('a high shelf becomes three peaks under 19 kHz', () {
    final (peaks, flat) = shelfAsPeaks(
      const EqFilter(EqFilterType.highShelf, 10000, 6, 0.71),
    );
    expect(peaks, hasLength(3));
    expect(peaks.every((p) => p.freq <= 19000), isTrue);
    expect(flat.abs(), lessThan(0.2));
  });
}
