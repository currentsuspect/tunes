import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/net/tunes_client.dart';

void main() {
  test('the library decodes the same off the screen thread', () async {
    final body = jsonEncode({
      'tracks': [
        {'sha': 'a' * 64, 'title': 'Make Believe', 'artist': 'Juice WRLD'},
        {
          'sha': 'c' * 64,
          'title': 'Team ceo',
          'dupeShas': ['d' * 64],
        },
      ],
    });
    final m = await decodeManifestOffMain(body);
    expect(m.tracks.map((t) => t.title), ['Make Believe', 'Team ceo']);
    expect(m.tracks.first.artist, 'Juice WRLD');
    expect(m.pointers, {'d' * 64: 'c' * 64});
  });

  test('a broken file fails the call, not the app', () async {
    await expectLater(decodeManifestOffMain('{not json'), throwsA(anything));
  });
}
