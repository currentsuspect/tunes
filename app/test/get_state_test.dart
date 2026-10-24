import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/domain/soulseek.dart';

void main() {
  GetJob job(String state) => GetJob.fromJson({
    'id': 'x',
    'title': 'CAROUSEL',
    'artist': 'Travis Scott',
    'state': state,
  });

  test('a song taken out of the line reads as cancelled and finished', () {
    final j = job('cancelled');
    expect(j.state, GetState.cancelled);
    expect(j.finished, isTrue);
  });

  test('a state this app does not know still reads as failed', () {
    expect(job('somethingNew').state, GetState.failed);
  });
}
