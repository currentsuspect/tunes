import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/radio/radio_engine.dart';
import 'package:tunes/core/radio/session.dart';
import 'package:tunes/domain/manifest.dart';

import 'radio_engine_test.dart' show t;

ArtistGenre g(String name, String family) =>
    ArtistGenre(name: name, family: family, weight: 1);

void main() {
  // Three rooms of hip-hop, R&B next door (acts tagged in both), reggae a
  // family away.
  final genres = <String, List<ArtistGenre>>{
    'rage a': [g('Rage', 'Hip-Hop')],
    'rage b': [g('Rage', 'Hip-Hop')],
    'plugg a': [g('Plugg', 'Hip-Hop')],
    'rnb a': [g('R&B', 'R&B & Soul')],
    'both a': [g('Trap', 'Hip-Hop'), g('R&B', 'R&B & Soul')],
    'both b': [g('Trap', 'Hip-Hop'), g('R&B', 'R&B & Soul')],
    'reggae a': [g('Reggae', 'Reggae & Dancehall')],
  };
  final library = [
    for (final a in genres.keys)
      for (var i = 0; i < 4; i++) t('$a-$i', artist: a.toUpperCase()),
  ];
  final taste = TasteSnapshot.build(artistGenres: genres);
  final playing = library.firstWhere((x) => x.sha == 'rage a-0');

  group('stretch slot', () {
    test('comes round every Nth pick for the mode', () {
      final s = RadioSession()..useMode(RadioMode.drift);
      final e = RadioEngine(random: Random(1));
      final turns = <bool>[];
      var cur = playing;
      for (var i = 0; i < 10; i++) {
        cur = e.next(library: library, session: s, taste: taste, current: cur)!;
        turns.add(e.lastStretch);
      }
      expect(turns, [
        false,
        false,
        false,
        false,
        true,
        false,
        false,
        false,
        false,
        true,
      ]);
    });

    test('a stretch picks next door, not more of the same', () {
      final ranked = RadioEngine(random: Random(1)).rank(
        library: library,
        session: RadioSession()..useMode(RadioMode.stayClose),
        taste: taste,
        current: playing,
        stretch: true,
      );
      final top = ranked.first.track.artistKey.toLowerCase();
      expect(top, isNot(startsWith('rage')));
      // Plugg (same family) or R&B (a family this library pairs with) beat
      // more Rage, and beat reggae, a family away.
      expect(['plugg a', 'rnb a', 'both a', 'both b'], contains(top));
      final reggae = ranked.indexWhere((r) => r.track.artistKey == 'REGGAE A');
      final rage = ranked.indexWhere((r) => r.track.artistKey == 'RAGE B');
      expect(
        ranked.indexWhere((r) => r.track.artistKey == 'PLUGG A'),
        lessThan(rage),
      );
      expect(reggae, greaterThan(0));
    });

    test('an ordinary pick still stays in the lane', () {
      final ranked = RadioEngine(random: Random(1)).rank(
        library: library,
        session: RadioSession()..useMode(RadioMode.stayClose),
        taste: taste,
        current: playing,
      );
      expect(ranked.first.track.artistKey, 'RAGE A');
    });
  });

  test('families paired by two or more acts are neighbours', () {
    expect(taste.neighbours['Hip-Hop'], contains('R&B & Soul'));
    expect(taste.neighbours['Hip-Hop'], isNot(contains('Reggae & Dancehall')));
  });

  test('old plays fade: loved now beats loved once', () {
    final now = DateTime(2026, 10, 17);
    final a = TasteSnapshot.fadedAffinity([
      for (var i = 0; i < 20; i++)
        (sha: 'old', at: now.subtract(const Duration(days: 365))),
      for (var i = 0; i < 5; i++)
        (sha: 'new', at: now.subtract(const Duration(days: 10))),
    ], now: now);
    expect(a['new']!, greaterThan(a['old']!));
    expect(a['new']!, closeTo(5 * pow(0.5, 10 / 45), 0.01));
  });

  test('modes step from close to far', () {
    expect(RadioMode.stayClose.reach, lessThan(RadioMode.drift.reach));
    expect(RadioMode.drift.reach, lessThan(RadioMode.surprise.reach));
    expect(
      RadioMode.surprise.stretchEvery,
      lessThan(RadioMode.stayClose.stretchEvery),
    );
  });
}
