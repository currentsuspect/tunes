import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/domain/manifest.dart';
import 'package:tunes/domain/mixes.dart';

ManifestTrack _t(
  String sha,
  String artist, {
  DateTime? addedAt,
  String album = 'A',
}) => ManifestTrack(
  sha: sha,
  size: 1,
  codec: 'flac',
  sampleRate: 44100,
  channels: 2,
  bitrate: 1000,
  durationMs: 120000,
  title: 'Song $sha',
  artist: artist,
  album: album,
  year: '2026',
  artSha: null,
  releaseId: null,
  trackNumber: null,
  discNumber: null,
  primaryArtist: artist,
  featured: const [],
  addedAt: addedAt,
);

// 2026-10-09 is a Friday; 2026-10-10 a Saturday.
final friEvening = DateTime(2026, 10, 9, 19, 30);
final friLate = DateTime(2026, 10, 9, 23, 30);
final satMorning = DateTime(2026, 10, 10, 8, 0);

/// 40 tracks over 8 artists, five each.
List<ManifestTrack> library() => [
  for (var a = 0; a < 8; a++)
    for (var i = 0; i < 5; i++) _t('a${a}t$i', 'Artist $a'),
];

/// 60 tracks over 30 artists, two each: wide enough that the three-per-artist
/// limit is not what decides how long a mix is.
List<ManifestTrack> wide() => [
  for (var a = 0; a < 30; a++)
    for (var i = 0; i < 2; i++) _t('w${a}t$i', 'Wide $a'),
];

/// [times] plays of [sha], each at [when].
List<PlayStamp> plays(String sha, DateTime when, {int times = 1}) => [
  for (var i = 0; i < times; i++) PlayStamp(sha, when),
];

MixInputs inputs({
  List<ManifestTrack>? tracks,
  List<ManifestArtist> artists = const [],
  List<ManifestRelease> releases = const [],
  List<PlayStamp> stamps = const [],
  Set<String> liked = const {},
  DateTime? now,
}) => MixInputs(
  tracks: tracks ?? library(),
  artists: artists,
  releases: releases,
  stamps: stamps,
  liked: liked,
  now: now ?? friEvening,
);

void main() {
  group('the weekday mix', () {
    test('on a Friday it is Feel Good Friday, from your Fridays', () {
      final fridays = DateTime(2026, 10, 2, 20); // last Friday
      final stamps = [
        for (final t in wide()) ...plays(t.sha, fridays, times: 2),
      ];
      final m = buildMixes(inputs(tracks: wide(), stamps: stamps))
          .firstWhere((m) => m.kind == MixKind.weekday);
      expect(m.title, 'Feel Good Friday');
      expect(m.tracks.length, 30);
      expect(m.note, contains('Fridays'));
    });

    test('it is a different mix on a Saturday', () {
      final stamps = [
        for (final t in library()) ...plays(t.sha, DateTime(2026, 10, 3, 21)),
      ];
      final m = buildMixes(inputs(stamps: stamps, now: satMorning))
          .firstWhere((m) => m.kind == MixKind.weekday);
      expect(m.title, 'Saturday Night');
    });

    test('songs played on Fridays beat songs played on other days', () {
      final tracks = wide();
      final onFri = tracks.take(30).toList();
      final onMon = tracks.skip(30).toList();
      final stamps = [
        for (final t in onFri)
          ...plays(t.sha, DateTime(2026, 10, 2, 20), times: 4),
        for (final t in onMon)
          ...plays(t.sha, DateTime(2026, 10, 5, 20), times: 4),
      ];
      final m = buildMixes(inputs(tracks: tracks, stamps: stamps))
          .firstWhere((m) => m.kind == MixKind.weekday);
      final fri = onFri.map((t) => t.sha).toSet();
      // A Friday of Friday songs: none of the Monday ones.
      expect(m.tracks.every((t) => fri.contains(t.sha)), isTrue);
    });

    test('hearted songs are pulled in even with no plays', () {
      final tracks = wide();
      final liked = {for (final t in tracks.take(30)) t.sha};
      final m = buildMixes(inputs(tracks: tracks, liked: liked))
          .firstWhere((m) => m.kind == MixKind.weekday);
      expect(m.tracks.every((t) => liked.contains(t.sha)), isTrue);
    });

    test('with too little to go on it is left out, not padded', () {
      final stamps = plays('a0t0', friEvening, times: 3);
      expect(
        buildMixes(inputs(stamps: stamps))
            .where((m) => m.kind == MixKind.weekday),
        isEmpty,
      );
      expect(buildMixes(inputs()), isEmpty);
    });

    test('no more than three from one artist', () {
      final stamps = [
        for (final t in library()) ...plays(t.sha, DateTime(2026, 10, 2, 20)),
      ];
      final m = buildMixes(inputs(stamps: stamps))
          .firstWhere((m) => m.kind == MixKind.weekday);
      final perArtist = <String, int>{};
      for (final t in m.tracks) {
        perArtist[t.artistKey] = (perArtist[t.artistKey] ?? 0) + 1;
      }
      expect(perArtist.values.every((n) => n <= 3), isTrue);
    });

    test('the same all week, different next week', () {
      final stamps = [
        for (final t in library()) ...plays(t.sha, DateTime(2026, 10, 2, 20)),
      ];
      List<String> at(DateTime d) =>
          buildMixes(inputs(stamps: stamps, now: d))
              .firstWhere((m) => m.kind == MixKind.weekday)
              .tracks
              .map((t) => t.sha)
              .toList();
      // Same Friday, morning and night: the same list.
      expect(at(DateTime(2026, 10, 9, 8)), at(DateTime(2026, 10, 9, 23)));
      // The Friday after: a fresh order.
      expect(
        at(DateTime(2026, 10, 16, 20)),
        isNot(at(DateTime(2026, 10, 9, 20))),
      );
    });
  });

  group('the time-of-day mixes', () {
    List<PlayStamp> afterDark() => [
      for (final t in library().take(24))
        ...plays(t.sha, DateTime(2026, 10, 3, 1)),
    ];

    test('Late Night shows after dark, from what you play after dark', () {
      final m = buildMixes(inputs(stamps: afterDark(), now: friLate));
      final late = m.firstWhere((m) => m.id == 'late-night');
      expect(late.title, 'Late Night');
      final heard = library().take(24).map((t) => t.sha).toSet();
      expect(late.tracks.every((t) => heard.contains(t.sha)), isTrue);
    });

    test('and is not offered in the afternoon', () {
      final m = buildMixes(
        inputs(stamps: afterDark(), now: DateTime(2026, 10, 9, 15)),
      );
      expect(m.where((m) => m.id == 'late-night'), isEmpty);
    });

    test('Morning shows in the morning from morning plays', () {
      final stamps = [
        for (final t in library().take(24))
          ...plays(t.sha, DateTime(2026, 10, 3, 8)),
      ];
      final m = buildMixes(inputs(stamps: stamps, now: satMorning));
      expect(m.where((m) => m.id == 'morning'), hasLength(1));
      expect(m.where((m) => m.id == 'late-night'), isEmpty);
    });

    test('a few late plays are not a mix', () {
      final stamps = [
        for (final t in library().take(5))
          ...plays(t.sha, DateTime(2026, 10, 3, 1)),
      ];
      expect(
        buildMixes(inputs(stamps: stamps, now: friLate))
            .where((m) => m.id == 'late-night'),
        isEmpty,
      );
    });
  });

  group('deep cuts', () {
    test('are unplayed songs by the artists you play most', () {
      final tracks = library();
      // Artist 0 and 1 played heavily, but only some of their songs.
      final stamps = [
        for (final t in tracks.where((t) => t.artistKey == 'Artist 0').take(2))
          ...plays(t.sha, friEvening, times: 9),
      ];
      // Too few unplayed from one artist to make a mix of 15, so widen: give
      // six artists some plays.
      final more = [
        for (var a = 1; a < 6; a++) ...plays('a${a}t0', friEvening, times: 5),
      ];
      final m = buildMixes(inputs(tracks: tracks, stamps: [...stamps, ...more]))
          .where((m) => m.id == 'deep-cuts');
      expect(m, hasLength(1));
      final played = {
        for (final s in [...stamps, ...more]) s.sha,
      };
      expect(m.single.tracks.any((t) => played.contains(t.sha)), isFalse);
      // Only artists that have been played.
      expect(m.single.tracks.every((t) => t.artistKey != 'Artist 7'), isTrue);
    });

    test('are absent when nothing has been played yet', () {
      expect(buildMixes(inputs()).where((m) => m.id == 'deep-cuts'), isEmpty);
    });
  });

  group('genre lanes', () {
    // Enough artists per kind that three songs each fills a mix.
    List<ManifestTrack> tenEach() => [
      for (var a = 0; a < 24; a++)
        for (var i = 0; i < 5; i++) _t('a${a}t$i', 'Artist $a'),
    ];

    // Artists 0-11 are trap, 12-23 are phonk.
    List<ManifestArtist> twoKinds() => [
      for (var a = 0; a < 24; a++)
        ManifestArtist(
          name: 'Artist $a',
          artSha: null,
          tags: [a < 12 ? 'trap' : 'phonk'],
        ),
    ];

    int index(ManifestTrack t) => int.parse(t.artistKey.split(' ').last);

    test('make a mix of a kind of music from the artists with that tag', () {
      final m = buildMixes(inputs(tracks: tenEach(), artists: twoKinds()));
      final lanes = {
        for (final l in m.where((m) => m.kind == MixKind.genre)) l.title: l,
      };
      expect(lanes.keys, containsAll(['Trap', 'Phonk']));
      expect(lanes['Trap']!.tracks.every((t) => index(t) < 12), isTrue);
      expect(lanes['Phonk']!.tracks.every((t) => index(t) >= 12), isTrue);
      expect(lanes['Trap']!.note, contains('trap'));
    });

    test('favourites come first, so what you love is in the lane', () {
      final stamps = plays('a0t3', friEvening, times: 9);
      final m = buildMixes(
        inputs(tracks: tenEach(), artists: twoKinds(), stamps: stamps),
      );
      final trap = m.firstWhere((m) => m.title == 'Trap');
      expect(trap.tracks.any((t) => t.sha == 'a0t3'), isTrue);
    });

    test('spellings of one tag are one lane', () {
      final spelled = [
        for (var a = 0; a < 24; a++)
          ManifestArtist(
            name: 'Artist $a',
            artSha: null,
            tags: [a < 12 ? 'Hip-Hop' : 'hip hop'],
          ),
      ];
      final lanes = buildMixes(inputs(tracks: tenEach(), artists: spelled))
          .where((m) => m.kind == MixKind.genre)
          .toList();
      // One lane, holding everyone, not two half-lanes.
      expect(lanes, hasLength(1));
      expect(lanes.single.tracks.map(index).toSet().length, greaterThan(12));
    });

    test('vague tags do not make a lane', () {
      final tracks = [
        for (var a = 0; a < 8; a++)
          for (var i = 0; i < 10; i++) _t('a${a}t$i', 'Artist $a'),
      ];
      final vague = [
        for (var a = 0; a < 8; a++)
          ManifestArtist(
            name: 'Artist $a',
            artSha: null,
            tags: const ['seen live', 'american'],
          ),
      ];
      expect(
        buildMixes(inputs(tracks: tracks, artists: vague))
            .where((m) => m.kind == MixKind.genre),
        isEmpty,
      );
    });

    test('a small corner of the library is not a lane', () {
      final few = [
        for (var a = 0; a < 8; a++)
          ManifestArtist(
            name: 'Artist $a',
            artSha: null,
            tags: a == 0 ? const ['jazz'] : const [],
          ),
      ];
      expect(
        buildMixes(inputs(artists: few)).where((m) => m.kind == MixKind.genre),
        isEmpty,
      );
    });

    test('no tags at all, no lanes', () {
      expect(
        buildMixes(inputs()).where((m) => m.kind == MixKind.genre),
        isEmpty,
      );
    });
  });

  group('albums you have not heard', () {
    ManifestRelease rel(String id, String artist, List<String> shas) =>
        ManifestRelease(
          id: id,
          title: 'Album $id',
          artist: artist,
          year: '2026',
          artSha: null,
          type: 'album',
          totalTracks: shas.length,
          trackShas: shas,
        );

    ({List<ManifestTrack> tracks, List<ManifestRelease> releases}) shelf({
      DateTime? added,
    }) {
      final tracks = <ManifestTrack>[];
      final releases = <ManifestRelease>[];
      for (var r = 0; r < 6; r++) {
        final shas = [for (var i = 0; i < 4; i++) 'r${r}t$i'];
        for (final s in shas) {
          tracks.add(_t(s, 'Artist ${r % 3}', addedAt: added));
        }
        releases.add(rel('r$r', 'Artist ${r % 3}', shas));
      }
      return (tracks: tracks, releases: releases);
    }

    test('lists records with no plays, and not ones with any', () {
      final s = shelf();
      final heard = plays('r0t1', friEvening);
      final out = unheardAlbums(
        inputs(tracks: s.tracks, releases: s.releases, stamps: heard),
      );
      expect(out.map((a) => a.release.id), isNot(contains('r0')));
      expect(out.length, 5);
    });

    test('a single, or two songs, is not an album', () {
      final s = shelf();
      final short = [
        ...s.releases,
        rel('single', 'Artist 0', ['x1']),
      ];
      final out = unheardAlbums(inputs(tracks: s.tracks, releases: short));
      expect(out.map((a) => a.release.id), isNot(contains('single')));
    });

    test('recently added ones come first and say so', () {
      final newer = DateTime(2026, 10, 8);
      final tracks = <ManifestTrack>[];
      final releases = <ManifestRelease>[];
      for (var r = 0; r < 6; r++) {
        final shas = [for (var i = 0; i < 4; i++) 'r${r}t$i'];
        for (final s in shas) {
          tracks.add(
            _t(s, 'Artist $r', addedAt: r == 3 ? newer : DateTime(2025, 1, 1)),
          );
        }
        releases.add(rel('r$r', 'Artist $r', shas));
      }
      final out = unheardAlbums(inputs(tracks: tracks, releases: releases));
      expect(out.first.release.id, 'r3');
      expect(out.first.why, 'Added yesterday, not played');
    });

    test('by an artist you play says so', () {
      final s = shelf();
      // Artist 0 is played heavily through a record that is not in the list.
      final tracks = [...s.tracks, _t('known', 'Artist 0')];
      final stamps = plays('known', friEvening, times: 60);
      final out = unheardAlbums(
        inputs(tracks: tracks, releases: s.releases, stamps: stamps),
      );
      final byFan = out.firstWhere((a) => a.release.artist == 'Artist 0');
      expect(byFan.why, contains('who you play'));
    });

    test('too few to bother is nothing at all', () {
      final s = shelf();
      final out = unheardAlbums(
        inputs(tracks: s.tracks, releases: s.releases.take(2).toList()),
      );
      expect(out, isEmpty);
    });

    test('the order is stable within a day', () {
      final s = shelf();
      List<String> at(DateTime d) =>
          unheardAlbums(inputs(tracks: s.tracks, releases: s.releases, now: d))
              .map((a) => a.release.id)
              .toList();
      expect(at(DateTime(2026, 10, 9, 8)), at(DateTime(2026, 10, 9, 22)));
    });
  });
}
