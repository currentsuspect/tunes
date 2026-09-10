import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/radio/radio_engine.dart';
import 'package:tunes/core/radio/session.dart';
import 'package:tunes/domain/manifest.dart';

ManifestTrack t(
  String sha, {
  String artist = 'A',
  String? release,
  String title = 'x',
  List<String> featured = const [],
}) => ManifestTrack(
  sha: sha,
  size: 1,
  codec: 'flac',
  sampleRate: 44100,
  channels: 2,
  bitrate: 1000,
  durationMs: 180000,
  title: title,
  artist: artist,
  album: 'album',
  year: null,
  artSha: null,
  releaseId: release,
  trackNumber: null,
  discNumber: null,
  primaryArtist: artist,
  featured: featured,
);

/// Zero jitter and deterministic sampling, so a ranking assertion is about the
/// scoring rules and not about luck.
class _FixedRandom implements Random {
  const _FixedRandom();
  @override
  int nextInt(int max) => 0;
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => false;
}

void main() {
  final engine = RadioEngine(random: const _FixedRandom());
  const noTaste = TasteSnapshot();

  List<String> order(List<ScoredTrack> r) => r.map((s) => s.track.sha).toList();

  group('continuity', () {
    test('prefers the same artist as what is playing', () {
      final lib = [t('same', artist: 'Yeat'), t('other', artist: 'Vax')];
      final r = engine.rank(
        library: lib,
        session: RadioSession(),
        taste: noTaste,
        current: t('cur', artist: 'Yeat'),
      );
      expect(order(r).first, 'same');
    });

    test('prefers the same release over merely the same artist', () {
      final lib = [
        t('sameRelease', artist: 'Yeat', release: 'r1'),
        t('sameArtist', artist: 'Yeat', release: 'r2'),
      ];
      final r = engine.rank(
        library: lib,
        session: RadioSession(),
        taste: noTaste,
        current: t('cur', artist: 'Yeat', release: 'r1'),
      );
      expect(order(r).first, 'sameRelease');
    });
  });

  group('not repeating itself', () {
    test('a track heard this session drops below one that has not been', () {
      final s = RadioSession()..completed(t('heard', artist: 'Yeat'));
      final r = engine.rank(
        library: [
          t('heard', artist: 'Yeat'),
          t('fresh', artist: 'Yeat'),
        ],
        session: s,
        taste: noTaste,
        current: t('cur', artist: 'Yeat'),
      );
      expect(order(r).first, 'fresh');
    });

    test('the artist penalty grows with each repeat', () {
      // One in a row is a choice; three is a rut. The engine has to feel that
      // difference or a "radio" is just a shuffle stuck on one act.
      final one = RadioSession()..completed(t('a', artist: 'Yeat'));
      final three = RadioSession()
        ..completed(t('a', artist: 'Yeat'))
        ..completed(t('b', artist: 'Yeat'))
        ..completed(t('c', artist: 'Yeat'));

      double penalty(RadioSession s) => engine
          .rank(
            library: [t('cand', artist: 'Yeat')],
            session: s,
            taste: noTaste,
          )
          .first
          .reasons['repeat-artist']!;

      expect(penalty(three), lessThan(penalty(one)));
    });

    test('a skipped track is never offered again this session', () {
      final s = RadioSession()..skipped(t('nope'));
      final r = engine.rank(
        library: [t('nope'), t('yes')],
        session: s,
        taste: noTaste,
      );
      expect(order(r), ['yes']);
    });

    test('never suggests what is already playing', () {
      final r = engine.rank(
        library: [t('cur'), t('other')],
        session: RadioSession(),
        taste: noTaste,
        current: t('cur'),
      );
      expect(order(r), ['other']);
    });
  });

  group('taste', () {
    test('a played track outranks an unplayed one, all else equal', () {
      final r = engine.rank(
        library: [t('played'), t('never')],
        session: RadioSession(),
        taste: const TasteSnapshot(playCounts: {'played': 5}),
      );
      expect(order(r).first, 'played');
    });

    test('taste saturates rather than compounding without limit', () {
      // A single obsession must not be able to outweigh every penalty in a
      // 600-track library.
      double taste(int plays) => engine
          .rank(
            library: [t('x')],
            session: RadioSession(),
            taste: TasteSnapshot(playCounts: {'x': plays}),
          )
          .first
          .reasons['taste']!;
      expect(taste(50) - taste(10), lessThan(taste(10) - taste(2)));
      expect(taste(1000), lessThan(0.31));
    });

    test('a repeatedly skipped track sinks', () {
      final r = engine.rank(
        library: [t('hated'), t('neutral')],
        session: RadioSession(),
        taste: const TasteSnapshot(skipCounts: {'hated': 8}),
      );
      expect(order(r).first, 'neutral');
    });
  });

  group('the wander', () {
    test('completions widen it and skips narrow it, asymmetrically', () {
      // A skip must cost more than a completion earns, or one bad suggestion
      // takes a dozen good ones to undo.
      final a = RadioSession();
      final before = a.exploration;
      a.completed(t('1'));
      final gain = a.exploration - before;

      final b = RadioSession();
      final before2 = b.exploration;
      b.skipped(t('1'));
      final loss = before2 - b.exploration;

      expect(loss, greaterThan(gain));
    });

    test('exploration stays within bounds under repetition', () {
      final s = RadioSession();
      for (var i = 0; i < 100; i++) {
        s.completed(t('$i'));
      }
      expect(s.exploration, lessThanOrEqualTo(1.0));
      for (var i = 0; i < 100; i++) {
        s.skipped(t('s$i'));
      }
      expect(s.exploration, greaterThanOrEqualTo(0.0));
    });

    test('novelty is worth more to an adventurous session', () {
      double novelty(RadioSession s) => engine
          .rank(library: [t('new')], session: s, taste: noTaste)
          .first
          .reasons['novelty']!;

      final cautious = RadioSession()..skipped(t('x'));
      final bold = RadioSession();
      for (var i = 0; i < 5; i++) {
        bold.completed(t('c$i', artist: 'Z$i'));
      }
      expect(novelty(bold), greaterThan(novelty(cautious)));
    });
  });

  group('next()', () {
    test('returns null on an empty library rather than throwing', () {
      expect(
        engine.next(library: const [], session: RadioSession(), taste: noTaste),
        isNull,
      );
    });

    test('returns null when everything has been skipped', () {
      final s = RadioSession()..skipped(t('only'));
      expect(
        engine.next(library: [t('only')], session: s, taste: noTaste),
        isNull,
      );
    });

    test('does not always take the top score', () {
      // docs/RADIO.md §4: always taking the maximum converges on one loop and
      // starts to feel algorithmic.
      final lib = List.generate(8, (i) => t('t$i', artist: 'A$i'));
      final s = RadioSession();
      for (var i = 0; i < 6; i++) {
        s.completed(t('warm$i', artist: 'W$i'));
      }
      final picks = <String>{};
      final e = RadioEngine(random: Random(1));
      for (var i = 0; i < 40; i++) {
        picks.add(e.next(library: lib, session: s, taste: noTaste)!.sha);
      }
      expect(picks.length, greaterThan(1));
    });
  });

  group('relationships', () {
    test('a track featuring the current act outranks an unrelated one', () {
      final lib = [
        t('feat', artist: 'B', featured: ['A']),
        t('far', artist: 'Q'),
      ];
      final r = engine.rank(
        library: lib,
        session: RadioSession(),
        taste: noTaste,
        current: t('cur', artist: 'A'),
      );
      expect(order(r).first, 'feat');
      expect(r.first.reasons, contains('feature-out'));
    });

    test('a track by a featured guest outranks an unrelated one', () {
      final lib = [t('by-guest', artist: 'B'), t('far', artist: 'Q')];
      final r = engine.rank(
        library: lib,
        session: RadioSession(),
        taste: noTaste,
        current: t('cur', artist: 'A', featured: ['B']),
      );
      expect(order(r).first, 'by-guest');
      expect(r.first.reasons, contains('feature-in'));
    });

    test('a shared guest beats no connection', () {
      final lib = [
        t('shared', artist: 'C', featured: ['Z']),
        t('far', artist: 'Q'),
      ];
      final r = engine.rank(
        library: lib,
        session: RadioSession(),
        taste: noTaste,
        current: t('cur', artist: 'A', featured: ['Z']),
      );
      expect(order(r).first, 'shared');
      expect(r.first.reasons, contains('shared-guest'));
    });
  });

  group('lookahead', () {
    RadioSession sessionOf(List<String> artists) {
      final s = RadioSession();
      for (final a in artists.reversed) {
        s.completed(t('x-$a', artist: a));
      }
      return s;
    }

    test('a third consecutive track by one act is penalized', () {
      final lib = [t('again', artist: 'A'), t('elsewhere', artist: 'B')];
      final r = engine.rank(
        library: lib,
        session: sessionOf(['A', 'A']),
        taste: noTaste,
        current: t('cur', artist: 'A'),
      );
      expect(order(r).first, 'elsewhere');
      final scored = r.firstWhere((s) => s.track.sha == 'again');
      expect(scored.reasons, contains('run'));
    });

    test('closing an A-B-A-B alternation is penalized', () {
      final lib = [t('b2', artist: 'B'), t('c1', artist: 'C')];
      final r = engine.rank(
        library: lib,
        session: sessionOf(['A', 'B', 'A']),
        taste: noTaste,
        current: t('cur', artist: 'A'),
      );
      expect(order(r).first, 'c1');
      final scored = r.firstWhere((s) => s.track.sha == 'b2');
      expect(scored.reasons, contains('alternation'));
    });
  });
}
