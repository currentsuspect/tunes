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
}
