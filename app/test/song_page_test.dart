import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/audio/tune_player.dart';
import 'package:tunes/core/data/gets.dart';
import 'package:tunes/core/net/tunes_client.dart';
import 'package:tunes/domain/about.dart';
import 'package:tunes/domain/manifest.dart';
import 'package:tunes/features/song/person_page.dart';
import 'package:tunes/features/song/song_page.dart';

// Yeat's "Griddlë", as the box's /about/song answers for it (24 Oct, cut).
final _about = SongAbout.fromJson({
  'url': 'https://genius.com/Yeat-griddle-lyrics',
  'description':
      '“Griddlë” serves as the 4th track on Yeat’s sixth studio album, ADL.',
  'releaseDate': '2026-03-27',
  'producers': ['BNYX®', 'Bangs (Producer)'],
  'writers': ['Yeat', 'Don Toliver'],
  'featured': [],
  'credits': [
    {
      'role': 'Mixing Engineer',
      'names': ['Yeat'],
    },
    {
      'role': 'Label',
      'names': ['Field Trip Recordings'],
    },
  ],
  'connections': [
    {
      'type': 'samples',
      'songs': [
        {'title': 'Old One', 'artist': 'Someone'},
      ],
    },
  ],
  'album': {'id': 1168170, 'name': 'ADL'},
});

ManifestTrack _t(
  String c,
  String title, {
  String? lyrics,
  String artist = 'Yeat',
}) => ManifestTrack(
  sha: c * 64,
  size: 1,
  codec: 'flac',
  sampleRate: 44100,
  channels: 2,
  bitrate: 1,
  durationMs: 157000,
  title: title,
  artist: artist,
  album: 'ADL (Deluxe)',
  year: '2026',
  artSha: null,
  releaseId: null,
  trackNumber: 4,
  discNumber: 1,
  lyrics: lyrics,
);

const _griddleLyrics =
    '[tunesbeat:drop=67660;break=63080-67660;pulse=67610,68950]\n'
    '[01:05.16] Bitch, don\'t get hit with the b- (ah)\n'
    '[01:07.28] Oh, yeah, you\'re goin\' stupid';

class _Box extends TunesClient {
  _Box() : super('http://test');

  @override
  Future<({SongAbout? song, AlbumAbout? album})?> aboutSong(String sha) async =>
      (song: _about, album: null);

  @override
  Future<List<Work>?> aboutPerson(String name) async => [
    Work('a' * 64, ['produced']),
    Work('c' * 64, ['produced', 'written']),
  ];
}

class _Player extends TunePlayer {
  final played = <String>[];
  @override
  List<ManifestTrack> get queue => const [];
  @override
  int get index => -1;
  @override
  bool get playing => false;
  @override
  Duration get position => Duration.zero;
  @override
  Duration get duration => Duration.zero;
  @override
  ManifestTrack? get current => null;
  @override
  PlaybackRepeat get repeat => PlaybackRepeat.off;
  @override
  bool get shuffle => false;
  @override
  void playQueue(List<ManifestTrack> tracks, int startIndex) =>
      played.addAll(tracks.map((t) => t.title));
  @override
  void play() {}
  @override
  void pause() {}
  @override
  void toggle() {}
  @override
  void next() {}
  @override
  void previous() {}
  @override
  void playAt(int index) {}
  @override
  void seek(Duration target) {}
  @override
  void stop() {}
  @override
  void setRepeat(PlaybackRepeat mode) {}
  @override
  void setShuffle(bool on) {}
}

Widget _wrap(Widget child) => MaterialApp(
  home: GetsScope(
    gets: GetsController(client: _Box(), onLanded: () {}),
    child: child,
  ),
);

void main() {
  final griddle = _t('a', 'Griddlë', lyrics: _griddleLyrics);
  final marching = _t('c', 'MARCHING');
  final other = _t('d', 'Kiss', artist: 'Maajins');
  final manifest = TunesManifest(
    tracks: [griddle, marching, other],
    releases: const [],
  );

  testWidgets('a song page tells its story and opens each maker', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(
      _wrap(
        SongPage(
          track: griddle,
          manifest: manifest,
          player: _Player(),
          artUrlFor: (s) => s,
          onOpenArtist: (_) {},
          onOpenAlbum: (_) {},
          onOpenPerson: opened.add,
          onOpenLyrics: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('4th track'), findsOneWidget);
    expect(find.text('Who made it'), findsOneWidget);
    // Genius's "(Producer)" is not part of anyone's name.
    expect(find.text('Bangs'), findsOneWidget);
    await tester.tap(find.text('BNYX®'));
    expect(opened, ['BNYX®']);
    // The label is a fact, not a maker.
    expect(find.text('Field Trip Recordings'), findsNothing);
    await tester.scrollUntilVisible(find.textContaining('“ah”'), 300);
    expect(find.text('The moments'), findsOneWidget);
    expect(find.textContaining('“ah”'), findsOneWidget);
  });

  testWidgets('a person page lists their work, by role', (tester) async {
    final player = _Player();
    await tester.pumpWidget(
      _wrap(
        PersonPage(
          name: 'BNYX®',
          manifest: manifest,
          player: player,
          artUrlFor: (s) => s,
          onOpenSong: (_) {},
          onOpenArtist: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 songs in your library'), findsOneWidget);
    expect(find.text('Written · 1'), findsOneWidget);
    await tester.tap(find.text('Written · 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play their work'));
    expect(player.played, ['MARCHING']);
  });
}
