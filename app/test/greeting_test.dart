import 'package:flutter_test/flutter_test.dart';
import 'package:tunes/core/ui/greeting.dart';

void main() {
  DateTime at(int h) => DateTime(2026, 10, 5, h);

  test('each part of the day has its own line', () {
    expect(greetingFor(at(5), ''), 'Good morning');
    expect(greetingFor(at(11), ''), 'Good morning');
    expect(greetingFor(at(12), ''), 'Good afternoon');
    expect(greetingFor(at(16), ''), 'Good afternoon');
    expect(greetingFor(at(17), ''), 'Good evening');
    expect(greetingFor(at(21), ''), 'Good evening');
  });

  test('the small hours are not called morning', () {
    expect(greetingFor(at(22), ''), 'Still up');
    expect(greetingFor(at(0), ''), 'Still up');
    expect(greetingFor(at(4), ''), 'Still up');
  });

  test('names the listener when it knows them, and not when it does not', () {
    expect(greetingFor(at(19), 'Dylan'), 'Good evening, Dylan');
    expect(greetingFor(at(19), '  Dylan '), 'Good evening, Dylan');
    expect(greetingFor(at(19), '   '), 'Good evening');
  });

  test('with a seed it speaks in more than one voice, all on time', () {
    final evening = {
      for (var s = 0; s < 60; s++) greetingFor(at(19), 'Dylan', seed: s),
    };
    expect(evening.length, greaterThan(4));
    expect(evening, contains('Good evening, Dylan'));
    expect(evening.any((l) => l.contains('morning')), isFalse);
    final late = {for (var s = 0; s < 60; s++) greetingFor(at(1), '', seed: s)};
    expect(late.any((l) => l.contains('morning')), isFalse);
    expect(late.any((l) => l.contains('{n}') || l.contains(', ')), isFalse);
  });

  test('the same seed says the same thing, so it does not flicker', () {
    expect(
      greetingFor(at(9), 'Dylan', seed: 41),
      greetingFor(at(9), 'Dylan', seed: 41),
    );
  });

  test('every line stays short enough for one line on a phone', () {
    for (final h in [1, 9, 14, 19]) {
      for (var d = 5; d < 12; d++) {
        for (var s = 0; s < 80; s++) {
          final line = greetingFor(DateTime(2026, 10, d, h), '', seed: s);
          expect(line.length, lessThanOrEqualTo(20), reason: line);
        }
      }
    }
  });

  test('each room has its own voice', () {
    final evening = DateTime(2026, 10, 17, 19);
    expect(
      greetingFor(evening, 'Dylan', voice: GreetingVoice.noir),
      'Good evening.',
    );
    final loud = greetingFor(
      evening,
      'Dylan',
      seed: 1,
      voice: GreetingVoice.crayon,
    );
    expect(loud, anyOf(endsWith('!'), endsWith('?')));
    expect(
      greetingFor(evening, '', voice: GreetingVoice.crayon),
      isNot(contains(', ')),
    );
  });
}
