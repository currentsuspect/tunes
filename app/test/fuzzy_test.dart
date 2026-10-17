import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/domain/fuzzy.dart';

typedef _S = ({String title, String artist, String album});

void main() {
  const lib = <_S>[
    (
      title: 'HIGHEST IN THE ROOM',
      artist: 'Travi\$ Scott',
      album: 'HIGHEST IN THE ROOM',
    ),
    (
      title: "'03 Bonnie & Clyde (feat. Beyoncé)",
      artist: 'JAY-Z;Beyoncé',
      album: 'Dangerously In Love',
    ),
    (title: 'Work It Out', artist: 'Beyoncé', album: 'Dangerously In Love'),
    (title: 'Kanairo', artist: 'Maajins', album: 'Kanairo'),
    (title: 'PLUTOSKI', artist: 'Future', album: 'PLUTOSKI'),
  ];
  List<SearchField> f(_S s) => [
    SearchField(s.title, weight: 1.2),
    SearchField(s.artist),
    SearchField(s.album, weight: 0.8),
  ];
  List<String> find(String q) => [
    for (final s in fuzzyRank(q, lib, f)) s.title,
  ];

  test('accents and symbols fold', () {
    expect(find('beyonce'), contains('Work It Out'));
    expect(find('travis'), ['HIGHEST IN THE ROOM']);
    expect(find('bonnie and clyde').first, startsWith("'03 Bonnie"));
  });

  test('typos still land', () {
    expect(find('hihgest').first, 'HIGHEST IN THE ROOM');
    expect(find('majins').first, 'Kanairo');
    expect(find('plutoksi').first, 'PLUTOSKI');
  });

  test('words run together still land', () {
    expect(find('highestintheroom').first, 'HIGHEST IN THE ROOM');
  });

  test('every word has to land somewhere', () {
    expect(find('beyonce zzzz'), isEmpty);
    expect(find('work beyonce').first, 'Work It Out');
  });

  test('a short word matches word starts, never fuzzes into noise', () {
    expect(find('ou'), ['Work It Out']);
    expect(find('xq'), isEmpty);
  });
}
